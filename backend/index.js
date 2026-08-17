require('dotenv').config();
const crypto = require('crypto');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { PrismaClient } = require('@prisma/client');

const app = express();
const prisma = new PrismaClient();
const PORT = 3000;

app.use(cors());
app.use(express.json());

// ============================================================
// HELPERS
// ============================================================

// Haversine formula: distance in km between two lat/lng points
function calculateDistanceKm(lat1, lng1, lat2, lng2) {
  const R = 6371; // Earth's radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Zone type -> fare multiplier
const ZONE_MULTIPLIER = {
  normal: 1.0,
  discounted: 0.8,
  expensive: 1.5
};

// Finds online, idle drivers near a pickup point (same city, within maxRadiusKm), closest first
async function findNearbyDrivers(cityId, pickupLat, pickupLng, { limit = 5, maxRadiusKm = 10 } = {}) {
  const candidates = await prisma.driver.findMany({
    where: {
      online_status: 'available',
      current_city_id: cityId || undefined,
      last_known_lat: { not: null },
      last_known_lng: { not: null },
      ride: { none: { status: { in: ['matched', 'in_progress'] } } }
    }
  });

  return candidates
    .map((driver) => ({
      driver,
      distanceKm: calculateDistanceKm(pickupLat, pickupLng, driver.last_known_lat, driver.last_known_lng)
    }))
    .filter(({ distanceKm }) => distanceKm <= maxRadiusKm)
    .sort((a, b) => a.distanceKm - b.distanceKm)
    .slice(0, limit);
}

// Finds unclaimed parcels near a driver's current location (same city, within maxRadiusKm), closest first
async function findNearbyParcels(cityId, driverLat, driverLng, { limit = 10, maxRadiusKm = 15 } = {}) {
  const candidates = await prisma.parcel_delivery.findMany({
    where: {
      status: 'requested',
      driver_id: null,
      city_id: cityId || undefined
    }
  });

  return candidates
    .map((parcel) => ({
      parcel,
      distanceKm: calculateDistanceKm(driverLat, driverLng, parcel.pickup_lat, parcel.pickup_lng)
    }))
    .filter(({ distanceKm }) => distanceKm <= maxRadiusKm)
    .sort((a, b) => a.distanceKm - b.distanceKm)
    .slice(0, limit);
}

// Logs an in-app notification (no external channel is wired up yet, so it's marked sent immediately)
function createNotification(userId, { channel = 'in_app', template_key, title, body }) {
  return prisma.notification.create({
    data: { user_id: userId, channel, template_key, title, body, status: 'sent', sent_at: new Date() }
  });
}

function hashOtp(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

// Generates and stores a verification code. No real SMS/email provider is wired up yet, so
// "delivery" is a server log line — the caller returns the plaintext code in the API response
// (marked dev_code) so the client can display it until a real provider is configured.
async function issueVerificationCode(user, channel) {
  const destination = channel === 'email' ? user.email : user.phone;
  const code = crypto.randomInt(100000, 1000000).toString();
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

  await prisma.verification_code.create({
    data: {
      user_id: user.id,
      channel,
      destination,
      code_hash: hashOtp(code),
      purpose: 'signup',
      expires_at: expiresAt
    }
  });

  console.log(`[DEV OTP] ${channel} code for ${destination}: ${code} (expires ${expiresAt.toISOString()})`);

  return { code, destination, expiresAt };
}

// ============================================================
// MIDDLEWARE
// ============================================================

function authenticate(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// ============================================================
// PUBLIC ROUTES
// ============================================================

app.get('/', (req, res) => {
  res.json({ message: 'Ride-hailing API is running' });
});

// ------------------------------------------------------------
// POST /api/auth/signup
// ------------------------------------------------------------
app.post('/api/auth/signup', async (req, res) => {
  try {
    const { name, email, phone, password, role, home_city_id, verify_channel } = req.body;

    if (!name || !email || !phone || !password || !role) {
      return res.status(400).json({
        error: 'Missing required fields: name, email, phone, password, role'
      });
    }
    if (role !== 'rider') {
      return res.status(400).json({
        error: "Invalid role. Must be 'rider'. Use /api/auth/signup/driver to create a driver account."
      });
    }
    if (password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }

    const channel = ['phone', 'email'].includes(verify_channel) ? verify_channel : 'phone';
    if (channel === 'email' && email.endsWith('@rideeasy.temp')) {
      return res.status(400).json({ error: 'A real email address is required to verify via email' });
    }

    const existing = await prisma.app_user.findFirst({
      where: { OR: [{ email }, { phone }] }
    });
    if (existing) {
      return res.status(409).json({ error: 'A user with this email or phone already exists' });
    }

    const password_hash = await bcrypt.hash(password, 12);

    const user = await prisma.$transaction(async (tx) => {
      const newUser = await tx.app_user.create({
        data: {
          name, email, phone, password_hash, role,
          home_city_id: home_city_id || null,
          status: 'pending_verification'
        }
      });

      await tx.rider.create({ data: { user_id: newUser.id } });

      await tx.wallet.create({
        data: { user_id: newUser.id, currency: 'PKR' }
      });

      return newUser;
    });

    const { code, destination, expiresAt } = await issueVerificationCode(user, channel);

    const { password_hash: _, ...safeUser } = user;
    res.status(201).json({
      message: 'Account created successfully',
      user: safeUser,
      verify_channel: channel,
      destination,
      dev_code: code,
      expires_at: expiresAt
    });

  } catch (error) {
    console.error('Signup error:', error);
    res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
});

// ------------------------------------------------------------
// POST /api/auth/login
// ------------------------------------------------------------
app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, phone, password } = req.body;

    if ((!email && !phone) || !password) {
      return res.status(400).json({ error: 'Phone or email, and password are required' });
    }

    const user = await prisma.app_user.findUnique({
      where: phone ? { phone } : { email }
    });
    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const passwordValid = await bcrypt.compare(password, user.password_hash);
    if (!passwordValid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    if (user.status === 'blocked' || user.status === 'deleted') {
      return res.status(403).json({ error: 'Account is not active' });
    }

    const token = jwt.sign(
      { userId: user.id, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    await prisma.app_user.update({
      where: { id: user.id },
      data: { last_login_at: new Date() }
    });

    const { password_hash: _, ...safeUser } = user;
    res.json({ message: 'Login successful', token, user: safeUser });

  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
});

// ------------------------------------------------------------
// POST /api/auth/send-code
// (Re)issues a verification code for signup — used for "Resend code"
// ------------------------------------------------------------
app.post('/api/auth/send-code', async (req, res) => {
  try {
    const { channel, destination } = req.body || {};
    if (!['phone', 'email'].includes(channel) || !destination) {
      return res.status(400).json({ error: 'channel and destination are required' });
    }

    const user = await prisma.app_user.findUnique({
      where: channel === 'email' ? { email: destination } : { phone: destination }
    });
    if (!user) {
      return res.status(404).json({ error: `No account found for that ${channel}` });
    }

    const { code, expiresAt } = await issueVerificationCode(user, channel);
    res.json({ message: 'Code sent', dev_code: code, expires_at: expiresAt, channel, destination });
  } catch (error) {
    console.error('Send code error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/auth/verify-code
// Verifies a signup code and logs the user in (returns a JWT, like login)
// ------------------------------------------------------------
app.post('/api/auth/verify-code', async (req, res) => {
  try {
    const { channel, destination, code } = req.body || {};
    if (!['phone', 'email'].includes(channel) || !destination || !code) {
      return res.status(400).json({ error: 'channel, destination, and code are required' });
    }

    const user = await prisma.app_user.findUnique({
      where: channel === 'email' ? { email: destination } : { phone: destination }
    });
    if (!user) {
      return res.status(404).json({ error: `No account found for that ${channel}` });
    }

    const record = await prisma.verification_code.findFirst({
      where: { user_id: user.id, channel, destination, verified_at: null },
      orderBy: { created_at: 'desc' }
    });
    if (!record) {
      return res.status(404).json({ error: 'No pending code found. Request a new one.' });
    }
    if (record.expires_at < new Date()) {
      return res.status(410).json({ error: 'Code expired. Request a new one.' });
    }
    if (record.attempts >= record.max_attempts) {
      return res.status(429).json({ error: 'Too many incorrect attempts. Request a new code.' });
    }

    if (hashOtp(code) !== record.code_hash) {
      await prisma.verification_code.update({
        where: { id: record.id },
        data: { attempts: { increment: 1 } }
      });
      return res.status(401).json({ error: 'Incorrect code' });
    }

    await prisma.verification_code.update({
      where: { id: record.id },
      data: { verified_at: new Date() }
    });

    const updateData = channel === 'email' ? { is_email_verified: true } : { is_phone_verified: true };
    if (user.status === 'pending_verification') updateData.status = 'active';

    const updatedUser = await prisma.app_user.update({
      where: { id: user.id },
      data: updateData
    });

    const token = jwt.sign(
      { userId: updatedUser.id, role: updatedUser.role },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    const { password_hash: _, ...safeUser } = updatedUser;
    res.json({ message: 'Verified', token, user: safeUser });
  } catch (error) {
    console.error('Verify code error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/countries  (public — no login needed)
// Returns countries the platform operates in, for phone dial-code pickers etc.
// ------------------------------------------------------------
app.get('/api/countries', async (req, res) => {
  try {
    const countries = await prisma.country.findMany({
      where: { is_active: true },
      select: { id: true, name: true, iso_code: true, phone_prefix: true, currency: true },
      orderBy: { name: 'asc' }
    });
    res.json({ countries });
  } catch (error) {
    console.error('Get countries error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/cities  (public — no login needed)
// Returns cities the platform operates in
// ------------------------------------------------------------
app.get('/api/cities', async (req, res) => {
  try {
    const cities = await prisma.city.findMany({
      where: { is_active: true },
      include: { country: true },
      orderBy: { name: 'asc' }
    });
    res.json({ cities });
  } catch (error) {
    console.error('Get cities error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/vehicle-types  (public — no login needed)
// Returns available vehicle tiers with pricing
// ------------------------------------------------------------
app.get('/api/vehicle-types', async (req, res) => {
  try {
    const vehicleTypes = await prisma.vehicle_type.findMany({
      where: { is_active: true },
      orderBy: { base_fare: 'asc' }
    });
    res.json({ vehicle_types: vehicleTypes });
  } catch (error) {
    console.error('Get vehicle types error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// PROTECTED ROUTES (require valid JWT token)
// ============================================================

// ------------------------------------------------------------
// GET /api/me
// Returns the logged-in user's profile
// ------------------------------------------------------------
app.get('/api/me', authenticate, async (req, res) => {
  try {
    const user = await prisma.app_user.findUnique({
      where: { id: req.user.userId },
      include: {
        rider: true,
        driver: true,
        admin: true,
        wallet: true,
        city: true
      }
    });

    if (!user) return res.status(404).json({ error: 'User not found' });

    const { password_hash: _, ...safeUser } = user;
    res.json({ user: safeUser });
  } catch (error) {
    console.error('Get me error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/rides/estimate
// Returns a fare estimate for a proposed trip
// ------------------------------------------------------------
app.post('/api/rides/estimate', authenticate, async (req, res) => {
  try {
    const {
      vehicle_type_id, city_id,
      pickup_lat, pickup_lng,
      dropoff_lat, dropoff_lng
    } = req.body;

    if (!vehicle_type_id || pickup_lat == null || pickup_lng == null ||
        dropoff_lat == null || dropoff_lng == null) {
      return res.status(400).json({
        error: 'Missing required fields: vehicle_type_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng'
      });
    }

    // Verify the rider exists
    const rider = await prisma.rider.findUnique({ where: { user_id: req.user.userId } });
    if (!rider) {
      return res.status(403).json({ error: 'Only riders can request fare estimates' });
    }

    // Look up vehicle type pricing
    const vehicleType = await prisma.vehicle_type.findUnique({
      where: { id: vehicle_type_id }
    });
    if (!vehicleType) {
      return res.status(404).json({ error: 'Vehicle type not found' });
    }

    // Calculate distance
    const distanceKm = calculateDistanceKm(pickup_lat, pickup_lng, dropoff_lat, dropoff_lng);
    // Rough time estimate: assume avg 25 km/h in city traffic
    const durationSeconds = Math.round((distanceKm / 25) * 3600);
    const durationMinutes = durationSeconds / 60;

    // Check for active zone at pickup (simplified — no polygon check, uses city-wide only)
    const activeZone = await prisma.zone.findFirst({
      where: {
        city_id: city_id || null,
        effective_from: { lte: new Date() },
        effective_to: { gte: new Date() }
      }
    });
    const surgeMultiplier = activeZone
      ? ZONE_MULTIPLIER[activeZone.zone_type]
      : 1.0;

    // Fare formula: (base + distance*perKm + time*perMin + booking_fee) * surge
    const baseFare = Number(vehicleType.base_fare);
    const distanceFare = distanceKm * Number(vehicleType.per_km_rate);
    const timeFare = durationMinutes * Number(vehicleType.per_min_rate);
    const bookingFee = Number(vehicleType.booking_fee);
    const subtotal = baseFare + distanceFare + timeFare + bookingFee;
    const total = Math.max(Number(vehicleType.min_fare), subtotal * surgeMultiplier);

    // Give a range: total ± 10%
    const estimatedMin = Math.round(total * 0.9 * 100) / 100;
    const estimatedMax = Math.round(total * 1.1 * 100) / 100;

    // Save the estimate (expires in 5 minutes)
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000);
    const estimate = await prisma.fare_estimate.create({
      data: {
        rider_id: rider.user_id,
        vehicle_type_id,
        city_id: city_id || null,
        pickup_lat, pickup_lng,
        dropoff_lat, dropoff_lng,
        estimated_min: estimatedMin,
        estimated_max: estimatedMax,
        surge_multiplier: surgeMultiplier,
        estimated_duration_seconds: durationSeconds,
        estimated_distance_km: Math.round(distanceKm * 100) / 100,
        expires_at: expiresAt
      }
    });

    res.status(201).json({
      estimate: {
        ...estimate,
        zone_type: activeZone?.zone_type || 'normal'
      }
    });

  } catch (error) {
    console.error('Estimate error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/rides
// Creates a new ride request
// ------------------------------------------------------------
app.post('/api/rides', authenticate, async (req, res) => {
  try {
    const {
      pickup_address, dropoff_address,
      pickup_lat, pickup_lng,
      dropoff_lat, dropoff_lng,
      city_id, country_id,
      fare_estimate_id,
      scheduled_for
    } = req.body;

    if (!pickup_address || !dropoff_address ||
        pickup_lat == null || pickup_lng == null ||
        dropoff_lat == null || dropoff_lng == null) {
      return res.status(400).json({
        error: 'Missing required fields: pickup/dropoff address, pickup/dropoff coordinates'
      });
    }

    const rider = await prisma.rider.findUnique({ where: { user_id: req.user.userId } });
    if (!rider) {
      return res.status(403).json({ error: 'Only riders can book rides' });
    }

    // If a fare estimate was provided, use its total_fare and multiplier
    let baseFare = null, surgeMultiplier = 1.0, totalFare = null;
    if (fare_estimate_id) {
      const est = await prisma.fare_estimate.findUnique({ where: { id: fare_estimate_id } });
      if (est && est.rider_id === rider.user_id) {
        surgeMultiplier = Number(est.surge_multiplier);
        totalFare = Number(est.estimated_max); // charge upper bound; actual finalized on completion
      }
    }

    const ride = await prisma.ride.create({
      data: {
        rider_id: rider.user_id,
        city_id: city_id || null,
        country_id: country_id || null,
        fare_estimate_id: fare_estimate_id || null,
        pickup_address, dropoff_address,
        pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
        status: scheduled_for ? 'scheduled' : 'requested',
        surge_multiplier: surgeMultiplier,
        total_fare: totalFare,
        scheduled_for: scheduled_for ? new Date(scheduled_for) : null
      }
    });

    // Dispatch to nearby online drivers (skip for scheduled/future rides)
    let nearbyDrivers = [];
    if (!scheduled_for) {
      nearbyDrivers = await findNearbyDrivers(ride.city_id, pickup_lat, pickup_lng);
      if (nearbyDrivers.length > 0) {
        await prisma.ride_dispatch.createMany({
          data: nearbyDrivers.map(({ driver, distanceKm }) => ({
            ride_id: ride.id,
            driver_id: driver.user_id,
            distance_to_pickup_km: Math.round(distanceKm * 100) / 100
          }))
        });
      }
    }

    if (!scheduled_for) {
      await createNotification(ride.rider_id, {
        template_key: 'ride_requested',
        title: 'Finding your driver',
        body: nearbyDrivers.length > 0
          ? `We're looking for a nearby driver. ${nearbyDrivers.length} driver(s) notified.`
          : 'No drivers are nearby right now. We will keep looking.'
      });
    }

    // TODO: emit real-time event via WebSocket

    res.status(201).json({
      message: 'Ride requested successfully',
      ride,
      drivers_notified: nearbyDrivers.length
    });

  } catch (error) {
    console.error('Create ride error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/rides/my
// Returns the logged-in rider's ride history
// ------------------------------------------------------------
app.get('/api/rides/my', authenticate, async (req, res) => {
  try {
    const rides = await prisma.ride.findMany({
      where: { rider_id: req.user.userId },
      orderBy: { requested_at: 'desc' },
      take: 50, // most recent 50
      include: {
        vehicle: true,
        payment: true
      }
    });
    res.json({ rides });
  } catch (error) {
    console.error('Get my rides error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/rides/:id
// Returns details of a specific ride (must belong to the logged-in user)
// ------------------------------------------------------------
app.get('/api/rides/:id', authenticate, async (req, res) => {
  try {
    const ride = await prisma.ride.findUnique({
      where: { id: req.params.id },
      include: {
        vehicle: true,
        payment: true,
        rating: true
      }
    });

    if (!ride) return res.status(404).json({ error: 'Ride not found' });

    // Only the rider or driver of this ride can view it
    if (ride.rider_id !== req.user.userId && ride.driver_id !== req.user.userId) {
      return res.status(403).json({ error: 'You do not have access to this ride' });
    }

    res.json({ ride });
  } catch (error) {
    console.error('Get ride error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/rides/:id/cancel
// Rider or the assigned driver cancels a ride that hasn't finished
// ------------------------------------------------------------
app.post('/api/rides/:id/cancel', authenticate, async (req, res) => {
  try {
    const ride = await prisma.ride.findUnique({ where: { id: req.params.id } });
    if (!ride) return res.status(404).json({ error: 'Ride not found' });

    let cancelledBy;
    if (ride.rider_id === req.user.userId) cancelledBy = 'rider';
    else if (ride.driver_id === req.user.userId) cancelledBy = 'driver';
    else return res.status(403).json({ error: 'You do not have access to this ride' });

    if (['completed', 'cancelled'].includes(ride.status)) {
      return res.status(409).json({ error: `Ride is already ${ride.status}` });
    }

    const { reason } = req.body || {};

    const updatedRide = await prisma.ride.update({
      where: { id: ride.id },
      data: {
        status: 'cancelled',
        cancellation_reason: reason || null,
        cancelled_by: cancelledBy
      }
    });

    if (ride.driver_id) {
      await prisma.driver.updateMany({
        where: { user_id: ride.driver_id, online_status: 'on_trip' },
        data: { online_status: 'available' }
      });
    }

    await prisma.ride_dispatch.updateMany({
      where: { ride_id: ride.id, offer_status: 'pending' },
      data: { offer_status: 'expired', responded_at: new Date() }
    });

    res.json({ message: 'Ride cancelled', ride: updatedRide });
  } catch (error) {
    console.error('Cancel ride error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/rides/:id/rate
// Rider or driver rates the other party after a completed ride
// ------------------------------------------------------------
app.post('/api/rides/:id/rate', authenticate, async (req, res) => {
  try {
    const ride = await prisma.ride.findUnique({ where: { id: req.params.id } });
    if (!ride) return res.status(404).json({ error: 'Ride not found' });
    if (ride.status !== 'completed') {
      return res.status(409).json({ error: 'Only completed rides can be rated' });
    }

    let raterRole, rateeId;
    if (ride.rider_id === req.user.userId) {
      raterRole = 'rider';
      rateeId = ride.driver_id;
    } else if (ride.driver_id === req.user.userId) {
      raterRole = 'driver';
      rateeId = ride.rider_id;
    } else {
      return res.status(403).json({ error: 'You do not have access to this ride' });
    }
    if (!rateeId) {
      return res.status(409).json({ error: 'This ride has no counterpart to rate' });
    }

    const { stars, comment } = req.body || {};
    if (!Number.isInteger(stars) || stars < 1 || stars > 5) {
      return res.status(400).json({ error: 'stars must be an integer between 1 and 5' });
    }

    const rating = await prisma.rating.create({
      data: {
        ride_id: ride.id,
        rater_id: req.user.userId,
        ratee_id: rateeId,
        rater_role: raterRole,
        stars,
        comment: comment || null
      }
    });

    const agg = await prisma.rating.aggregate({
      where: { ratee_id: rateeId },
      _avg: { stars: true }
    });
    const newAvg = agg._avg.stars != null ? Math.round(agg._avg.stars * 100) / 100 : stars;

    if (raterRole === 'rider') {
      await prisma.driver.update({ where: { user_id: rateeId }, data: { rating_avg: newAvg } });
    } else {
      await prisma.rider.update({ where: { user_id: rateeId }, data: { rating_avg: newAvg } });
    }

    res.status(201).json({ message: 'Rating submitted', rating });
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(409).json({ error: 'You have already rated this ride' });
    }
    console.error('Rate ride error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/rides/:id/messages
// Send a chat message on a ride (rider or driver only)
// ------------------------------------------------------------
app.post('/api/rides/:id/messages', authenticate, async (req, res) => {
  try {
    const ride = await prisma.ride.findUnique({ where: { id: req.params.id } });
    if (!ride) return res.status(404).json({ error: 'Ride not found' });

    let senderRole;
    if (ride.rider_id === req.user.userId) senderRole = 'rider';
    else if (ride.driver_id === req.user.userId) senderRole = 'driver';
    else return res.status(403).json({ error: 'You do not have access to this ride' });

    const { message } = req.body || {};
    if (!message || !message.trim()) {
      return res.status(400).json({ error: 'message is required' });
    }

    const chatMessage = await prisma.chat_message.create({
      data: {
        ride_id: ride.id,
        sender_id: req.user.userId,
        sender_role: senderRole,
        message: message.trim()
      }
    });

    res.status(201).json({ message: chatMessage });
  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/rides/:id/messages
// Fetch chat history for a ride (marks the other party's messages read)
// ------------------------------------------------------------
app.get('/api/rides/:id/messages', authenticate, async (req, res) => {
  try {
    const ride = await prisma.ride.findUnique({ where: { id: req.params.id } });
    if (!ride) return res.status(404).json({ error: 'Ride not found' });
    if (ride.rider_id !== req.user.userId && ride.driver_id !== req.user.userId) {
      return res.status(403).json({ error: 'You do not have access to this ride' });
    }

    await prisma.chat_message.updateMany({
      where: { ride_id: ride.id, sender_id: { not: req.user.userId }, is_read: false },
      data: { is_read: true, read_at: new Date() }
    });

    const messages = await prisma.chat_message.findMany({
      where: { ride_id: ride.id },
      orderBy: { sent_at: 'asc' }
    });

    res.json({ messages });
  } catch (error) {
    console.error('Get messages error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// DRIVER ROUTES
// ============================================================

// ------------------------------------------------------------
// POST /api/auth/signup/driver
// ------------------------------------------------------------
app.post('/api/auth/signup/driver', async (req, res) => {
  try {
    const { name, email, phone, password, license_number, license_expiry, home_city_id } = req.body;

    if (!name || !email || !phone || !password || !license_number || !license_expiry) {
      return res.status(400).json({
        error: 'Missing required fields: name, email, phone, password, license_number, license_expiry'
      });
    }
    if (password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }
    const licenseExpiryDate = new Date(license_expiry);
    if (isNaN(licenseExpiryDate.getTime())) {
      return res.status(400).json({ error: 'license_expiry must be a valid date (YYYY-MM-DD)' });
    }

    const existing = await prisma.app_user.findFirst({
      where: { OR: [{ email }, { phone }] }
    });
    if (existing) {
      return res.status(409).json({ error: 'A user with this email or phone already exists' });
    }

    const existingLicense = await prisma.driver.findUnique({ where: { license_number } });
    if (existingLicense) {
      return res.status(409).json({ error: 'A driver with this license number already exists' });
    }

    const password_hash = await bcrypt.hash(password, 12);

    const user = await prisma.$transaction(async (tx) => {
      const newUser = await tx.app_user.create({
        data: {
          name, email, phone, password_hash, role: 'driver',
          home_city_id: home_city_id || null,
          status: 'pending_verification'
        }
      });

      await tx.driver.create({
        data: {
          user_id: newUser.id,
          license_number,
          license_expiry: licenseExpiryDate,
          current_city_id: home_city_id || null
        }
      });

      await tx.wallet.create({
        data: { user_id: newUser.id, currency: 'PKR' }
      });

      return newUser;
    });

    const { password_hash: _, ...safeUser } = user;
    res.status(201).json({ message: 'Driver account created successfully', user: safeUser });

  } catch (error) {
    console.error('Driver signup error:', error);
    res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
});

// ------------------------------------------------------------
// POST /api/drivers/online
// Toggles the logged-in driver's online/offline status
// ------------------------------------------------------------
app.post('/api/drivers/online', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can go online' });
    }

    const { status } = req.body;
    if (!['available', 'offline', 'away'].includes(status)) {
      return res.status(400).json({ error: "status must be 'available', 'offline', or 'away'" });
    }

    const updated = await prisma.driver.update({
      where: { user_id: driver.user_id },
      data: { online_status: status }
    });

    res.json({ message: `Driver is now ${status}`, driver: updated });
  } catch (error) {
    console.error('Driver online error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/drivers/location
// Driver GPS update; logs a ride_tracking point if on an active ride
// ------------------------------------------------------------
app.post('/api/drivers/location', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can send location updates' });
    }

    const { lat, lng, speed, bearing, accuracy } = req.body;
    if (lat == null || lng == null) {
      return res.status(400).json({ error: 'lat and lng are required' });
    }

    await prisma.driver.update({
      where: { user_id: driver.user_id },
      data: { last_known_lat: lat, last_known_lng: lng, last_known_ts: new Date() }
    });

    const activeRide = await prisma.ride.findFirst({
      where: { driver_id: driver.user_id, status: { in: ['matched', 'in_progress'] } }
    });

    if (activeRide) {
      await prisma.ride_tracking.create({
        data: {
          ride_id: activeRide.id,
          driver_id: driver.user_id,
          city_id: activeRide.city_id,
          country_id: activeRide.country_id,
          lat, lng, speed, bearing, accuracy
        }
      });
    }

    res.json({ message: 'Location updated', tracked_ride_id: activeRide ? activeRide.id : null });
  } catch (error) {
    console.error('Driver location error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/rides/:id/accept
// Driver accepts a dispatched ride
// ------------------------------------------------------------
app.post('/api/rides/:id/accept', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can accept rides' });
    }
    if (driver.online_status !== 'available') {
      return res.status(400).json({ error: 'You must be available to accept rides' });
    }

    const rideId = req.params.id;

    // Atomic claim: only succeeds if the ride is still unassigned
    const claim = await prisma.ride.updateMany({
      where: { id: rideId, status: 'requested', driver_id: null },
      data: {
        driver_id: driver.user_id,
        vehicle_id: driver.active_vehicle_id,
        status: 'matched',
        matched_at: new Date()
      }
    });

    if (claim.count === 0) {
      const ride = await prisma.ride.findUnique({ where: { id: rideId } });
      if (!ride) return res.status(404).json({ error: 'Ride not found' });
      return res.status(409).json({ error: 'Ride is no longer available' });
    }

    await prisma.driver.update({
      where: { user_id: driver.user_id },
      data: { online_status: 'on_trip' }
    });

    const existingDispatch = await prisma.ride_dispatch.findFirst({
      where: { ride_id: rideId, driver_id: driver.user_id }
    });
    if (existingDispatch) {
      await prisma.ride_dispatch.update({
        where: { id: existingDispatch.id },
        data: { offer_status: 'accepted', responded_at: new Date() }
      });
    } else {
      await prisma.ride_dispatch.create({
        data: { ride_id: rideId, driver_id: driver.user_id, offer_status: 'accepted', responded_at: new Date() }
      });
    }

    // Other drivers' pending offers for this ride are now moot
    await prisma.ride_dispatch.updateMany({
      where: { ride_id: rideId, driver_id: { not: driver.user_id }, offer_status: 'pending' },
      data: { offer_status: 'expired', responded_at: new Date() }
    });

    const ride = await prisma.ride.findUnique({ where: { id: rideId } });

    await createNotification(ride.rider_id, {
      template_key: 'ride_matched',
      title: 'Driver is on the way',
      body: 'A driver has accepted your ride request and is heading to the pickup location.'
    });

    res.json({ message: 'Ride accepted', ride });
  } catch (error) {
    console.error('Accept ride error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/rides/:id/start
// Driver marks a matched ride as in progress
// ------------------------------------------------------------
app.post('/api/rides/:id/start', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can start rides' });
    }

    const updateResult = await prisma.ride.updateMany({
      where: { id: req.params.id, driver_id: driver.user_id, status: 'matched' },
      data: { status: 'in_progress', started_at: new Date() }
    });

    if (updateResult.count === 0) {
      return res.status(409).json({ error: 'Ride cannot be started (not matched to you, or already started)' });
    }

    const ride = await prisma.ride.findUnique({ where: { id: req.params.id } });
    res.json({ message: 'Ride started', ride });
  } catch (error) {
    console.error('Start ride error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/rides/:id/complete
// Driver marks an in-progress ride as completed and triggers payment
// ------------------------------------------------------------
app.post('/api/rides/:id/complete', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can complete rides' });
    }

    const ride = await prisma.ride.findUnique({ where: { id: req.params.id } });
    if (!ride) return res.status(404).json({ error: 'Ride not found' });
    if (ride.driver_id !== driver.user_id) {
      return res.status(403).json({ error: 'This ride is not assigned to you' });
    }
    if (ride.status !== 'in_progress') {
      return res.status(409).json({ error: 'Ride must be in progress to complete' });
    }

    const finalFare = ride.total_fare != null ? ride.total_fare : ride.base_fare;
    if (finalFare == null) {
      return res.status(400).json({ error: 'Ride has no fare on record — cannot create payment' });
    }

    const { distance_km, duration_seconds } = req.body || {};
    const finalDistance = distance_km != null
      ? distance_km
      : calculateDistanceKm(ride.pickup_lat, ride.pickup_lng, ride.dropoff_lat, ride.dropoff_lng);
    const finalDuration = duration_seconds != null
      ? duration_seconds
      : (ride.started_at ? Math.round((Date.now() - ride.started_at.getTime()) / 1000) : null);

    const [updatedRide] = await prisma.$transaction([
      prisma.ride.update({
        where: { id: ride.id },
        data: {
          status: 'completed',
          completed_at: new Date(),
          distance_km: finalDistance,
          duration_seconds: finalDuration
        }
      }),
      prisma.payment.create({
        data: {
          ride_id: ride.id,
          amount: finalFare,
          currency: 'PKR',
          status: 'captured',
          authorized_at: new Date(),
          captured_at: new Date()
        }
      }),
      prisma.driver.update({
        where: { user_id: driver.user_id },
        data: { total_rides: { increment: 1 }, online_status: 'available' }
      })
    ]);

    await createNotification(updatedRide.rider_id, {
      template_key: 'ride_completed',
      title: 'Trip completed',
      body: `Your ride has been completed. Total fare: ${updatedRide.total_fare} PKR.`
    });

    res.json({ message: 'Ride completed', ride: updatedRide });
  } catch (error) {
    console.error('Complete ride error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// SOS
// ============================================================

// ------------------------------------------------------------
// POST /api/sos
// Triggers an SOS event, optionally tied to an active ride
// ------------------------------------------------------------
app.post('/api/sos', authenticate, async (req, res) => {
  try {
    const { ride_id, lat, lng, notes, dispatched_to } = req.body || {};

    let city_id = null, country_id = null;
    if (ride_id) {
      const ride = await prisma.ride.findUnique({ where: { id: ride_id } });
      if (!ride || (ride.rider_id !== req.user.userId && ride.driver_id !== req.user.userId)) {
        return res.status(403).json({ error: 'You do not have access to this ride' });
      }
      city_id = ride.city_id;
      country_id = ride.country_id;
    }

    const validDispatch = ['police', 'ambulance', 'in_house_safety', 'multiple'];
    const sosEvent = await prisma.sos_event.create({
      data: {
        user_id: req.user.userId,
        ride_id: ride_id || null,
        city_id, country_id,
        lat: lat != null ? lat : null,
        lng: lng != null ? lng : null,
        dispatched_to: validDispatch.includes(dispatched_to) ? dispatched_to : 'in_house_safety',
        notes: notes || null
      }
    });

    res.status(201).json({ message: 'SOS triggered', sos_event: sosEvent });
  } catch (error) {
    console.error('SOS trigger error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/sos/my
// ------------------------------------------------------------
app.get('/api/sos/my', authenticate, async (req, res) => {
  try {
    const sosEvents = await prisma.sos_event.findMany({
      where: { user_id: req.user.userId },
      orderBy: { triggered_at: 'desc' }
    });
    res.json({ sos_events: sosEvents });
  } catch (error) {
    console.error('Get SOS events error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/sos/:id/resolve
// The triggering user or an admin can close out an SOS event
// ------------------------------------------------------------
app.post('/api/sos/:id/resolve', authenticate, async (req, res) => {
  try {
    const event = await prisma.sos_event.findUnique({ where: { id: req.params.id } });
    if (!event) return res.status(404).json({ error: 'SOS event not found' });

    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (event.user_id !== req.user.userId && !admin) {
      return res.status(403).json({ error: 'You do not have access to this SOS event' });
    }

    const { status, notes } = req.body || {};
    if (!['resolved', 'false_alarm'].includes(status)) {
      return res.status(400).json({ error: "status must be 'resolved' or 'false_alarm'" });
    }

    const updated = await prisma.sos_event.update({
      where: { id: event.id },
      data: { status, notes: notes || event.notes, resolved_at: new Date() }
    });

    res.json({ message: 'SOS event updated', sos_event: updated });
  } catch (error) {
    console.error('Resolve SOS error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// SUPPORT TICKETS
// ============================================================

const SUPPORT_CATEGORIES = ['payment', 'safety', 'driver_complaint', 'rider_complaint', 'app_issue', 'account', 'other'];
const SUPPORT_PRIORITIES = ['low', 'medium', 'high', 'urgent'];

// ------------------------------------------------------------
// POST /api/support/tickets
// ------------------------------------------------------------
app.post('/api/support/tickets', authenticate, async (req, res) => {
  try {
    const { category, subject, description, ride_id, priority } = req.body || {};
    if (!SUPPORT_CATEGORIES.includes(category) || !subject) {
      return res.status(400).json({
        error: `category (one of ${SUPPORT_CATEGORIES.join(', ')}) and subject are required`
      });
    }
    const finalPriority = SUPPORT_PRIORITIES.includes(priority) ? priority : 'medium';

    if (ride_id) {
      const ride = await prisma.ride.findUnique({ where: { id: ride_id } });
      if (!ride || (ride.rider_id !== req.user.userId && ride.driver_id !== req.user.userId)) {
        return res.status(403).json({ error: 'You do not have access to this ride' });
      }
    }

    const ticket = await prisma.support_ticket.create({
      data: {
        user_id: req.user.userId,
        ride_id: ride_id || null,
        category, subject,
        description: description || null,
        priority: finalPriority
      }
    });

    res.status(201).json({ message: 'Support ticket created', ticket });
  } catch (error) {
    console.error('Create ticket error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/support/tickets/my
// ------------------------------------------------------------
app.get('/api/support/tickets/my', authenticate, async (req, res) => {
  try {
    const tickets = await prisma.support_ticket.findMany({
      where: { user_id: req.user.userId },
      orderBy: { opened_at: 'desc' }
    });
    res.json({ tickets });
  } catch (error) {
    console.error('Get my tickets error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/support/tickets/:id
// ------------------------------------------------------------
app.get('/api/support/tickets/:id', authenticate, async (req, res) => {
  try {
    const ticket = await prisma.support_ticket.findUnique({ where: { id: req.params.id } });
    if (!ticket) return res.status(404).json({ error: 'Ticket not found' });

    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (ticket.user_id !== req.user.userId && !admin) {
      return res.status(403).json({ error: 'You do not have access to this ticket' });
    }

    res.json({ ticket });
  } catch (error) {
    console.error('Get ticket error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// ADMIN ROUTES
// ============================================================

// ------------------------------------------------------------
// GET /api/admin/support-tickets?status=open
// ------------------------------------------------------------
app.get('/api/admin/support-tickets', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const { status } = req.query;
    const tickets = await prisma.support_ticket.findMany({
      where: status ? { status } : {},
      orderBy: { opened_at: 'desc' },
      take: 100
    });

    res.json({ tickets });
  } catch (error) {
    console.error('Admin list tickets error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/admin/support-tickets/:id/assign
// ------------------------------------------------------------
app.post('/api/admin/support-tickets/:id/assign', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const ticket = await prisma.support_ticket.update({
      where: { id: req.params.id },
      data: { assigned_admin_id: admin.user_id, status: 'in_progress' }
    });

    res.json({ message: 'Ticket assigned', ticket });
  } catch (error) {
    console.error('Assign ticket error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/admin/support-tickets/:id/resolve
// ------------------------------------------------------------
app.post('/api/admin/support-tickets/:id/resolve', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const { resolution_notes, status } = req.body || {};
    const finalStatus = ['resolved', 'closed'].includes(status) ? status : 'resolved';

    const ticket = await prisma.support_ticket.update({
      where: { id: req.params.id },
      data: { status: finalStatus, resolution_notes: resolution_notes || null, resolved_at: new Date() }
    });

    res.json({ message: 'Ticket resolved', ticket });
  } catch (error) {
    console.error('Resolve ticket error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// NOTIFICATIONS
// ============================================================

// ------------------------------------------------------------
// GET /api/notifications
// ------------------------------------------------------------
app.get('/api/notifications', authenticate, async (req, res) => {
  try {
    const notifications = await prisma.notification.findMany({
      where: { user_id: req.user.userId },
      orderBy: { sent_at: 'desc' },
      take: 50
    });
    res.json({ notifications });
  } catch (error) {
    console.error('Get notifications error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/notifications/:id/read
// ------------------------------------------------------------
app.post('/api/notifications/:id/read', authenticate, async (req, res) => {
  try {
    const result = await prisma.notification.updateMany({
      where: { id: req.params.id, user_id: req.user.userId },
      data: { status: 'read', read_at: new Date() }
    });
    if (result.count === 0) {
      return res.status(404).json({ error: 'Notification not found' });
    }
    res.json({ message: 'Notification marked as read' });
  } catch (error) {
    console.error('Mark notification read error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// PARCEL DELIVERY
// ============================================================

// ------------------------------------------------------------
// POST /api/parcels
// Any logged-in user can send a parcel
// ------------------------------------------------------------
app.post('/api/parcels', authenticate, async (req, res) => {
  try {
    const {
      receiver_name, receiver_phone, receiver_id,
      pickup_address, dropoff_address,
      pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
      package_size, package_description,
      delivery_fee, city_id, country_id
    } = req.body || {};

    if (!receiver_name || !receiver_phone || !pickup_address || !dropoff_address ||
        pickup_lat == null || pickup_lng == null || dropoff_lat == null || dropoff_lng == null ||
        !package_size || delivery_fee == null) {
      return res.status(400).json({
        error: 'Missing required fields: receiver_name, receiver_phone, pickup/dropoff address & coordinates, package_size, delivery_fee'
      });
    }
    if (!['small', 'medium', 'large'].includes(package_size)) {
      return res.status(400).json({ error: "package_size must be 'small', 'medium', or 'large'" });
    }

    const parcel = await prisma.parcel_delivery.create({
      data: {
        sender_id: req.user.userId,
        receiver_id: receiver_id || null,
        receiver_name, receiver_phone,
        pickup_address, dropoff_address,
        pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
        package_size,
        package_description: package_description || null,
        delivery_fee,
        city_id: city_id || null,
        country_id: country_id || null
      }
    });

    res.status(201).json({ message: 'Parcel delivery requested', parcel });
  } catch (error) {
    console.error('Create parcel error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/parcels/available
// Driver browses unclaimed parcels near their current location
// ------------------------------------------------------------
app.get('/api/parcels/available', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can browse available parcels' });
    if (driver.last_known_lat == null || driver.last_known_lng == null) {
      return res.status(400).json({ error: 'Send a location update first via /api/drivers/location' });
    }

    const nearby = await findNearbyParcels(driver.current_city_id, driver.last_known_lat, driver.last_known_lng);
    res.json({
      parcels: nearby.map(({ parcel, distanceKm }) => ({
        ...parcel,
        distance_km: Math.round(distanceKm * 100) / 100
      }))
    });
  } catch (error) {
    console.error('List available parcels error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/parcels/my
// ------------------------------------------------------------
app.get('/api/parcels/my', authenticate, async (req, res) => {
  try {
    const parcels = await prisma.parcel_delivery.findMany({
      where: { sender_id: req.user.userId },
      orderBy: { requested_at: 'desc' },
      take: 50
    });
    res.json({ parcels });
  } catch (error) {
    console.error('Get my parcels error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/parcels/:id
// ------------------------------------------------------------
app.get('/api/parcels/:id', authenticate, async (req, res) => {
  try {
    const parcel = await prisma.parcel_delivery.findUnique({
      where: { id: req.params.id },
      include: { parcel_delivery_proof: true, payment: true }
    });
    if (!parcel) return res.status(404).json({ error: 'Parcel not found' });
    if (parcel.sender_id !== req.user.userId && parcel.driver_id !== req.user.userId) {
      return res.status(403).json({ error: 'You do not have access to this parcel' });
    }
    res.json({ parcel });
  } catch (error) {
    console.error('Get parcel error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/parcels/:id/accept
// ------------------------------------------------------------
app.post('/api/parcels/:id/accept', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can accept parcels' });
    if (driver.online_status !== 'available') {
      return res.status(400).json({ error: 'You must be available to accept parcels' });
    }

    const claim = await prisma.parcel_delivery.updateMany({
      where: { id: req.params.id, status: 'requested', driver_id: null },
      data: {
        driver_id: driver.user_id,
        vehicle_id: driver.active_vehicle_id,
        status: 'matched',
        matched_at: new Date()
      }
    });

    if (claim.count === 0) {
      return res.status(409).json({ error: 'Parcel is no longer available' });
    }

    await prisma.driver.update({
      where: { user_id: driver.user_id },
      data: { online_status: 'on_trip' }
    });

    const parcel = await prisma.parcel_delivery.findUnique({ where: { id: req.params.id } });
    res.json({ message: 'Parcel accepted', parcel });
  } catch (error) {
    console.error('Accept parcel error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/parcels/:id/pickup
// ------------------------------------------------------------
app.post('/api/parcels/:id/pickup', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can update parcel status' });

    const result = await prisma.parcel_delivery.updateMany({
      where: { id: req.params.id, driver_id: driver.user_id, status: 'matched' },
      data: { status: 'in_transit', picked_up_at: new Date() }
    });

    if (result.count === 0) {
      return res.status(409).json({ error: 'Parcel cannot be picked up (not matched to you, or already picked up)' });
    }

    const parcel = await prisma.parcel_delivery.findUnique({ where: { id: req.params.id } });
    res.json({ message: 'Parcel picked up', parcel });
  } catch (error) {
    console.error('Pickup parcel error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/parcels/:id/deliver
// Captures proof of delivery and triggers payment
// ------------------------------------------------------------
app.post('/api/parcels/:id/deliver', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can update parcel status' });

    const parcel = await prisma.parcel_delivery.findUnique({ where: { id: req.params.id } });
    if (!parcel) return res.status(404).json({ error: 'Parcel not found' });
    if (parcel.driver_id !== driver.user_id) {
      return res.status(403).json({ error: 'This parcel is not assigned to you' });
    }
    if (parcel.status !== 'in_transit') {
      return res.status(409).json({ error: 'Parcel must be in transit to deliver' });
    }

    const { proof_type, photo_url, signature_url, otp_code, confirmed_by } = req.body || {};
    const validProofTypes = ['photo', 'signature', 'otp_confirmation'];
    const validConfirmedBy = ['receiver', 'left_at_door', 'returned_to_sender', 'failed_no_answer'];
    if (!validProofTypes.includes(proof_type) || !validConfirmedBy.includes(confirmed_by)) {
      return res.status(400).json({
        error: `proof_type (one of ${validProofTypes.join(', ')}) and confirmed_by (one of ${validConfirmedBy.join(', ')}) are required`
      });
    }

    const finalStatus = confirmed_by === 'failed_no_answer' ? 'failed'
      : confirmed_by === 'returned_to_sender' ? 'returned'
      : 'delivered';

    const operations = [
      prisma.parcel_delivery.update({
        where: { id: parcel.id },
        data: { status: finalStatus, delivered_at: new Date() }
      }),
      prisma.parcel_delivery_proof.create({
        data: {
          parcel_id: parcel.id,
          proof_type,
          photo_url: photo_url || null,
          signature_url: signature_url || null,
          otp_code: otp_code || null,
          confirmed_by
        }
      }),
      prisma.driver.update({
        where: { user_id: driver.user_id },
        data: { online_status: 'available' }
      })
    ];

    if (finalStatus === 'delivered') {
      operations.push(
        prisma.payment.create({
          data: {
            parcel_id: parcel.id,
            amount: parcel.delivery_fee,
            currency: 'PKR',
            status: 'captured',
            authorized_at: new Date(),
            captured_at: new Date()
          }
        })
      );
    }

    const [updatedParcel] = await prisma.$transaction(operations);

    await createNotification(updatedParcel.sender_id, {
      template_key: finalStatus === 'delivered' ? 'parcel_delivered' : 'parcel_delivery_issue',
      title: finalStatus === 'delivered' ? 'Parcel delivered' : 'Parcel delivery issue',
      body: finalStatus === 'delivered'
        ? 'Your parcel has been delivered successfully.'
        : `Delivery could not be completed as planned (${finalStatus}).`
    });

    res.json({ message: 'Parcel delivery updated', parcel: updatedParcel });
  } catch (error) {
    console.error('Deliver parcel error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// START SERVER
// ============================================================
app.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
});