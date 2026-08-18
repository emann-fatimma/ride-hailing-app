require('dotenv').config();
const crypto = require('crypto');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { PrismaClient } = require('@prisma/client');
const { smsConfigured, emailConfigured, sendSms, sendEmail } = require('./services/notifications');

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

function round2(value) {
  return Math.round(value * 100) / 100;
}

// Driver keeps this share of every completed ride/parcel fare; the remainder is
// platform commission. No payment gateway is integrated yet, so this only affects
// the numbers on driver.lifetime_earnings / current_balance and payout requests.
const DRIVER_EARNINGS_SHARE = 0.8;

// KYC documents a driver must have approved before kyc_status flips to 'approved'.
// Matches the driver_document_doc_type_check constraint in the database — do not
// add values here without also widening that constraint.
const REQUIRED_DRIVER_DOC_TYPES = ['license', 'insurance', 'registration', 'background_check', 'profile_photo'];

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

// notification_preference's own DB check constraint only allows channel in
// ('push','sms','email') — not 'in_app'. That's the schema telling us in-app is
// the always-on system inbox, and preferences only govern optional extra pings on
// top of it. 'push' is left out here because there's no push provider (no FCM/APNs)
// wired up; sms/email reuse the same Twilio/Gmail helpers OTP delivery already uses.
const NOTIFICATION_CHANNELS = ['sms', 'email'];
// The category check constraint allows ride_updates/promotions/account/safety, but
// this app only ever raises ride_updates-shaped events (ride + parcel lifecycle) —
// the others are reserved for future use, not exposed as controls for nothing.
const NOTIFICATION_CATEGORIES = ['ride_updates'];

// Always writes the in-app notification (the row the inbox screen reads), then —
// only for categories/channels the user has opted into via notification_preference —
// also sends a real SMS/email using the existing OTP delivery infrastructure.
// Opt-in, not opt-out: no preference row means no extra SMS/email, just the in-app one.
async function createNotification(userId, { template_key, title, body }) {
  const notification = await prisma.notification.create({
    data: { user_id: userId, channel: 'in_app', template_key, title, body, status: 'sent', sent_at: new Date() }
  });

  const category = 'ride_updates';
  const extraChannels = await prisma.notification_preference.findMany({
    where: { user_id: userId, category, channel: { in: NOTIFICATION_CHANNELS }, enabled: true }
  });

  if (extraChannels.length > 0) {
    const user = await prisma.app_user.findUnique({ where: { id: userId } });
    for (const pref of extraChannels) {
      try {
        if (pref.channel === 'sms' && user?.phone) {
          if (smsConfigured) await sendSms(user.phone, `${title}: ${body}`);
          else console.log(`[DEV SMS] ${user.phone}: ${title} — ${body}`);
        } else if (pref.channel === 'email' && user?.email) {
          if (emailConfigured) await sendEmail(user.email, title, body);
          else console.log(`[DEV EMAIL] ${user.email}: ${title} — ${body}`);
        }
      } catch (error) {
        console.warn(`[NOTIFY] Could not deliver ${pref.channel} notification to user ${userId}: ${error.message}`);
      }
    }
  }

  return notification;
}

// SOS is safety-critical, so unlike createNotification it doesn't gate delivery behind
// notification_preference opt-in — it always tries to reach the rider's emergency
// contacts and every active admin.
async function notifySosContacts(user, sosEvent) {
  const contacts = await prisma.emergency_contact.findMany({ where: { user_id: user.id } });
  const location = sosEvent.lat != null && sosEvent.lng != null
    ? `https://maps.google.com/?q=${sosEvent.lat},${sosEvent.lng}`
    : 'location unavailable';
  const body = `SAFETY ALERT: ${user.name} triggered an SOS on RideEasy. Location: ${location}. If you can't reach them, contact local emergency services.`;

  for (const contact of contacts) {
    try {
      if (smsConfigured) await sendSms(contact.phone, body);
      else console.log(`[DEV SMS] ${contact.phone}: ${body}`);
    } catch (error) {
      console.warn(`[SOS] Could not notify emergency contact ${contact.id}: ${error.message}`);
    }
  }
}

async function notifySosAdmins(user, sosEvent) {
  const admins = await prisma.admin.findMany({ where: { status: 'active' }, include: { app_user: true } });
  const title = 'SOS Triggered';
  const location = sosEvent.lat != null && sosEvent.lng != null ? `${sosEvent.lat}, ${sosEvent.lng}` : 'unknown';
  const body = `${user.name} (${user.phone}) triggered an SOS${sosEvent.ride_id ? ` during ride ${sosEvent.ride_id}` : ''}. Location: ${location}.`;

  for (const admin of admins) {
    await prisma.notification.create({
      data: { user_id: admin.user_id, channel: 'in_app', template_key: 'sos_alert', title, body, status: 'sent', sent_at: new Date() }
    });
    try {
      if (admin.app_user?.phone) {
        if (smsConfigured) await sendSms(admin.app_user.phone, `${title}: ${body}`);
        else console.log(`[DEV SMS] ${admin.app_user.phone}: ${title} — ${body}`);
      }
    } catch (error) {
      console.warn(`[SOS] Could not notify admin ${admin.user_id}: ${error.message}`);
    }
  }
}

// Advances the driver's progress on every active incentive program that applies to
// their current city (or a global, city-less program) after a completed ride.
// Hour-based targets aren't tracked here — there's no shift-timer in this codebase to
// drive them — so only programs with a target_rides are updated.
async function updateIncentiveProgress(driver) {
  try {
    const today = new Date();
    const programs = await prisma.incentive_program.findMany({
      where: {
        is_active: true,
        target_rides: { not: null },
        starts_on: { lte: today },
        ends_on: { gte: today },
        OR: [{ city_id: driver.current_city_id }, { city_id: null }]
      }
    });

    for (const program of programs) {
      const key = { driver_id_program_id_period: { driver_id: driver.user_id, program_id: program.id, period: program.starts_on } };
      const existing = await prisma.driver_incentive.findUnique({ where: key });
      if (existing?.status === 'completed') continue;

      const newProgressRides = (existing?.progress_rides || 0) + 1;
      const justCompleted = newProgressRides >= program.target_rides;

      await prisma.driver_incentive.upsert({
        where: key,
        update: {
          progress_rides: newProgressRides,
          status: justCompleted ? 'completed' : 'active',
          bonus_earned: justCompleted ? program.bonus_amount : existing?.bonus_earned ?? 0,
          last_updated_at: new Date()
        },
        create: {
          driver_id: driver.user_id,
          program_id: program.id,
          period: program.starts_on,
          progress_rides: newProgressRides,
          status: justCompleted ? 'completed' : 'active',
          bonus_earned: justCompleted ? program.bonus_amount : 0
        }
      });

      if (justCompleted) {
        await prisma.driver.update({
          where: { user_id: driver.user_id },
          data: {
            lifetime_earnings: { increment: program.bonus_amount },
            current_balance: { increment: program.bonus_amount }
          }
        });
        await createNotification(driver.user_id, {
          template_key: 'incentive_completed',
          title: 'Bonus unlocked!',
          body: `You completed "${program.name}" and earned a ${program.bonus_amount} PKR bonus.`
        });
      }
    }
  } catch (error) {
    console.warn('[INCENTIVE] Could not update progress:', error.message);
  }
}

function hashOtp(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

// Generates and stores a verification code, then tries to deliver it over the real
// channel (Twilio SMS / Gmail SMTP). If the provider isn't configured (no API keys yet)
// or delivery fails, falls back to a server log line — the caller then returns the
// plaintext code in the API response (marked dev_code) so the client can display it.
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

  // Dev mode by default: only attempt real delivery once Twilio/Gmail credentials are
  // set in .env. Until then this always falls through to the console log + dev_code below.
  let delivered = false;
  const providerConfigured = channel === 'phone' ? smsConfigured : emailConfigured;
  if (providerConfigured) {
    try {
      if (channel === 'phone') {
        await sendSms(destination, `Your RideEasy verification code is ${code}. It expires in 10 minutes.`);
      } else {
        await sendEmail(destination, 'Your RideEasy verification code', `Your verification code is ${code}. It expires in 10 minutes.`);
      }
      delivered = true;
    } catch (error) {
      console.warn(`[OTP] Could not deliver ${channel} code to ${destination}: ${error.message}`);
    }
  }

  if (!delivered) {
    console.log(`[DEV OTP] ${channel} code for ${destination}: ${code} (expires ${expiresAt.toISOString()})`);
  }

  return { code, destination, expiresAt, delivered };
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
    const { name, email, phone, password, role, home_city_id, verify_channel, emergency_contacts } = req.body;

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

    // Riders must register two emergency contacts up front — they're who the SOS
    // button alerts, so the safety flow has no one to reach without them.
    if (!Array.isArray(emergency_contacts) || emergency_contacts.length !== 2) {
      return res.status(400).json({ error: 'Exactly two emergency contacts are required' });
    }
    for (const contact of emergency_contacts) {
      if (!contact || !contact.name || !contact.phone) {
        return res.status(400).json({ error: 'Each emergency contact needs a name and phone number' });
      }
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

      await tx.emergency_contact.createMany({
        data: emergency_contacts.map((contact, index) => ({
          user_id: newUser.id,
          name: contact.name,
          phone: contact.phone,
          relation: contact.relation || null,
          priority: index + 1
        }))
      });

      return newUser;
    });

    const { code, destination, expiresAt, delivered } = await issueVerificationCode(user, channel);

    const { password_hash: _, ...safeUser } = user;
    res.status(201).json({
      message: delivered ? 'Account created successfully' : 'Account created successfully (dev mode — no provider configured)',
      user: safeUser,
      verify_channel: channel,
      destination,
      dev_code: delivered ? undefined : code,
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

    const { code, expiresAt, delivered } = await issueVerificationCode(user, channel);
    res.json({
      message: delivered ? 'Code sent' : 'Code sent (dev mode — no provider configured)',
      dev_code: delivered ? undefined : code,
      expires_at: expiresAt,
      channel,
      destination
    });
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
// POST /api/auth/forgot-password
// Issues a reset code if the phone/email matches an account. Always
// responds the same way either way, so this can't be used to probe
// which phones/emails have accounts.
// ------------------------------------------------------------
app.post('/api/auth/forgot-password', async (req, res) => {
  try {
    const { phone, email } = req.body || {};
    if (!phone && !email) {
      return res.status(400).json({ error: 'phone or email is required' });
    }

    const user = await prisma.app_user.findUnique({ where: phone ? { phone } : { email } });

    const genericResponse = { message: 'If an account exists, a reset code has been sent.' };
    if (!user) {
      return res.json(genericResponse);
    }

    const channel = phone ? 'phone' : 'email';
    const destination = phone ? user.phone : user.email;
    const code = crypto.randomInt(100000, 1000000).toString();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

    await prisma.password_reset.create({
      data: { user_id: user.id, token_hash: hashOtp(code), expires_at: expiresAt }
    });

    let delivered = false;
    const providerConfigured = channel === 'phone' ? smsConfigured : emailConfigured;
    if (providerConfigured) {
      try {
        if (channel === 'phone') {
          await sendSms(destination, `Your RideEasy password reset code is ${code}. It expires in 15 minutes.`);
        } else {
          await sendEmail(destination, 'Reset your RideEasy password', `Your password reset code is ${code}. It expires in 15 minutes.`);
        }
        delivered = true;
      } catch (error) {
        console.warn(`[RESET] Could not deliver ${channel} code to ${destination}: ${error.message}`);
      }
    }

    if (!delivered) {
      console.log(`[DEV RESET CODE] ${channel} code for ${destination}: ${code} (expires ${expiresAt.toISOString()})`);
    }

    res.json({ ...genericResponse, ...(delivered ? {} : { dev_code: code }) });
  } catch (error) {
    console.error('Forgot password error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/auth/reset-password
// ------------------------------------------------------------
app.post('/api/auth/reset-password', async (req, res) => {
  try {
    const { phone, email, code, new_password } = req.body || {};
    if ((!phone && !email) || !code || !new_password) {
      return res.status(400).json({ error: 'phone or email, code, and new_password are required' });
    }
    if (new_password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }

    const user = await prisma.app_user.findUnique({ where: phone ? { phone } : { email } });
    if (!user) {
      return res.status(400).json({ error: 'Invalid or expired code' });
    }

    const record = await prisma.password_reset.findFirst({
      where: { user_id: user.id, used_at: null, token_hash: hashOtp(code), expires_at: { gt: new Date() } },
      orderBy: { created_at: 'desc' }
    });
    if (!record) {
      return res.status(400).json({ error: 'Invalid or expired code' });
    }

    const password_hash = await bcrypt.hash(new_password, 12);
    await prisma.$transaction([
      prisma.app_user.update({ where: { id: user.id }, data: { password_hash } }),
      prisma.password_reset.update({ where: { id: record.id }, data: { used_at: new Date() } })
    ]);

    res.json({ message: 'Password reset successfully' });
  } catch (error) {
    console.error('Reset password error:', error);
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
// PUT /api/me
// Updates editable profile fields for the logged-in user
// ------------------------------------------------------------
app.put('/api/me', authenticate, async (req, res) => {
  try {
    const { name, profile_photo_url, date_of_birth, gender } = req.body || {};

    const data = {};
    if (name !== undefined) data.name = name;
    if (profile_photo_url !== undefined) data.profile_photo_url = profile_photo_url;
    if (date_of_birth !== undefined) data.date_of_birth = date_of_birth ? new Date(date_of_birth) : null;
    if (gender !== undefined) data.gender = gender;

    const user = await prisma.app_user.update({
      where: { id: req.user.userId },
      data,
      include: { rider: true, driver: true, admin: true, wallet: true, city: true }
    });

    const { password_hash: _, ...safeUser } = user;
    res.json({ message: 'Profile updated', user: safeUser });
  } catch (error) {
    console.error('Update profile error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/auth/change-password
// ------------------------------------------------------------
app.post('/api/auth/change-password', authenticate, async (req, res) => {
  try {
    const { current_password, new_password } = req.body || {};
    if (!current_password || !new_password) {
      return res.status(400).json({ error: 'current_password and new_password are required' });
    }
    if (new_password.length < 8) {
      return res.status(400).json({ error: 'New password must be at least 8 characters' });
    }

    const user = await prisma.app_user.findUnique({ where: { id: req.user.userId } });
    const passwordValid = await bcrypt.compare(current_password, user.password_hash);
    if (!passwordValid) {
      return res.status(401).json({ error: 'Current password is incorrect' });
    }

    const password_hash = await bcrypt.hash(new_password, 12);
    await prisma.app_user.update({ where: { id: user.id }, data: { password_hash } });

    res.json({ message: 'Password changed successfully' });
  } catch (error) {
    console.error('Change password error:', error);
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

// ============================================================
// VEHICLES
// ============================================================

// ------------------------------------------------------------
// POST /api/vehicles
// Driver registers a vehicle. The first vehicle a driver adds
// automatically becomes their active one.
// ------------------------------------------------------------
app.post('/api/vehicles', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can register vehicles' });
    }

    const { vehicle_type_id, plate, make_model, color, year } = req.body;
    if (!vehicle_type_id || !plate || !make_model) {
      return res.status(400).json({ error: 'Missing required fields: vehicle_type_id, plate, make_model' });
    }

    const vehicle = await prisma.vehicle.create({
      data: {
        driver_id: driver.user_id,
        vehicle_type_id,
        city_id: driver.current_city_id || null,
        plate,
        make_model,
        color: color || null,
        year: year || null,
        registered_on: new Date()
      }
    });

    if (!driver.active_vehicle_id) {
      await prisma.driver.update({
        where: { user_id: driver.user_id },
        data: { active_vehicle_id: vehicle.id }
      });
    }

    res.status(201).json({ message: 'Vehicle registered', vehicle });
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(409).json({ error: 'A vehicle with this plate is already registered' });
    }
    console.error('Register vehicle error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/vehicles/my
// Lists the logged-in driver's vehicles
// ------------------------------------------------------------
app.get('/api/vehicles/my', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can view vehicles' });
    }

    const vehicles = await prisma.vehicle.findMany({
      where: { driver_id: driver.user_id },
      include: { vehicle_type: true },
      orderBy: { registered_on: 'desc' }
    });

    res.json({
      vehicles: vehicles.map((v) => ({ ...v, is_active: v.id === driver.active_vehicle_id }))
    });
  } catch (error) {
    console.error('List vehicles error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// PUT /api/vehicles/:id
// Edit a vehicle's details (ownership required)
// ------------------------------------------------------------
app.put('/api/vehicles/:id', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can edit vehicles' });
    }

    const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.id } });
    if (!vehicle || vehicle.driver_id !== driver.user_id) {
      return res.status(404).json({ error: 'Vehicle not found' });
    }

    const { make_model, color, year, status } = req.body;
    const updated = await prisma.vehicle.update({
      where: { id: vehicle.id },
      data: {
        make_model: make_model ?? vehicle.make_model,
        color: color ?? vehicle.color,
        year: year ?? vehicle.year,
        status: status ?? vehicle.status
      }
    });

    res.json({ message: 'Vehicle updated', vehicle: updated });
  } catch (error) {
    console.error('Update vehicle error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/vehicles/:id/activate
// Switches which of the driver's vehicles is their active one
// ------------------------------------------------------------
app.post('/api/vehicles/:id/activate', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can activate vehicles' });
    }

    const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.id } });
    if (!vehicle || vehicle.driver_id !== driver.user_id) {
      return res.status(404).json({ error: 'Vehicle not found' });
    }

    await prisma.driver.update({
      where: { user_id: driver.user_id },
      data: { active_vehicle_id: vehicle.id }
    });

    res.json({ message: 'Active vehicle updated', vehicle });
  } catch (error) {
    console.error('Activate vehicle error:', error);
    res.status(500).json({ error: 'Something went wrong' });
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
// GET /api/drivers/dispatches
// Lists this driver's pending ride offers, most recent first
// ------------------------------------------------------------
app.get('/api/drivers/dispatches', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can view ride offers' });
    }

    const dispatches = await prisma.ride_dispatch.findMany({
      where: { driver_id: driver.user_id, offer_status: 'pending' },
      orderBy: { offered_at: 'desc' },
      include: { ride: true }
    });

    res.json({ dispatches });
  } catch (error) {
    console.error('Get dispatches error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/rides/:id/decline
// Driver turns down a dispatched offer without claiming the ride
// ------------------------------------------------------------
app.post('/api/rides/:id/decline', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) {
      return res.status(403).json({ error: 'Only drivers can decline ride offers' });
    }

    const dispatch = await prisma.ride_dispatch.findFirst({
      where: { ride_id: req.params.id, driver_id: driver.user_id, offer_status: 'pending' }
    });
    if (!dispatch) {
      return res.status(404).json({ error: 'No pending offer found for this ride' });
    }

    const { reason } = req.body || {};
    const updated = await prisma.ride_dispatch.update({
      where: { id: dispatch.id },
      data: { offer_status: 'rejected', responded_at: new Date(), rejection_reason: reason || null }
    });

    res.json({ message: 'Ride declined', dispatch: updated });
  } catch (error) {
    console.error('Decline ride error:', error);
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

    const driverEarnings = round2(Number(finalFare) * DRIVER_EARNINGS_SHARE);

    const [updatedRide, , updatedDriver] = await prisma.$transaction([
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
        data: {
          total_rides: { increment: 1 },
          online_status: 'available',
          lifetime_earnings: { increment: driverEarnings },
          current_balance: { increment: driverEarnings }
        }
      })
    ]);

    await updateIncentiveProgress(updatedDriver);

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

    const triggeringUser = await prisma.app_user.findUnique({ where: { id: req.user.userId } });
    try {
      await Promise.all([
        notifySosContacts(triggeringUser, sosEvent),
        notifySosAdmins(triggeringUser, sosEvent)
      ]);
    } catch (notifyError) {
      console.warn('[SOS] Notification dispatch failed:', notifyError.message);
    }

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
// GET /api/admin/sos-events?status=triggered
// ------------------------------------------------------------
app.get('/api/admin/sos-events', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const { status } = req.query;
    const sosEvents = await prisma.sos_event.findMany({
      where: status ? { status } : {},
      orderBy: { triggered_at: 'desc' },
      take: 100,
      include: { app_user: { select: { name: true, phone: true } } }
    });

    res.json({ sos_events: sosEvents });
  } catch (error) {
    console.error('Admin list SOS events error:', error);
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
// EMERGENCY CONTACTS
// ============================================================

// ------------------------------------------------------------
// POST /api/emergency-contacts
// ------------------------------------------------------------
app.post('/api/emergency-contacts', authenticate, async (req, res) => {
  try {
    const { name, phone, relation, priority } = req.body || {};
    if (!name || !phone) {
      return res.status(400).json({ error: 'Missing required fields: name, phone' });
    }

    const contact = await prisma.emergency_contact.create({
      data: {
        user_id: req.user.userId,
        name,
        phone,
        relation: relation || null,
        priority: priority != null ? Number(priority) : 1
      }
    });

    res.status(201).json({ message: 'Emergency contact added', contact });
  } catch (error) {
    console.error('Add emergency contact error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/emergency-contacts
// ------------------------------------------------------------
app.get('/api/emergency-contacts', authenticate, async (req, res) => {
  try {
    const contacts = await prisma.emergency_contact.findMany({
      where: { user_id: req.user.userId },
      orderBy: { priority: 'asc' }
    });
    res.json({ contacts });
  } catch (error) {
    console.error('List emergency contacts error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// DELETE /api/emergency-contacts/:id
// ------------------------------------------------------------
app.delete('/api/emergency-contacts/:id', authenticate, async (req, res) => {
  try {
    const contact = await prisma.emergency_contact.findUnique({ where: { id: req.params.id } });
    if (!contact || contact.user_id !== req.user.userId) {
      return res.status(404).json({ error: 'Emergency contact not found' });
    }

    if (req.user.role === 'rider') {
      const count = await prisma.emergency_contact.count({ where: { user_id: req.user.userId } });
      if (count <= 2) {
        return res.status(400).json({ error: 'Riders must keep at least two emergency contacts on file' });
      }
    }

    await prisma.emergency_contact.delete({ where: { id: contact.id } });
    res.json({ message: 'Emergency contact removed' });
  } catch (error) {
    console.error('Delete emergency contact error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// SAVED PLACES
// ============================================================

// ------------------------------------------------------------
// POST /api/saved-places
// ------------------------------------------------------------
app.post('/api/saved-places', authenticate, async (req, res) => {
  try {
    const { label, address, lat, lng, city_id, country_id } = req.body || {};
    if (!label || !address || lat == null || lng == null) {
      return res.status(400).json({ error: 'Missing required fields: label, address, lat, lng' });
    }

    const place = await prisma.saved_place.create({
      data: {
        user_id: req.user.userId,
        label,
        address,
        lat,
        lng,
        city_id: city_id || null,
        country_id: country_id || null
      }
    });

    res.status(201).json({ message: 'Place saved', place });
  } catch (error) {
    console.error('Add saved place error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/saved-places
// ------------------------------------------------------------
app.get('/api/saved-places', authenticate, async (req, res) => {
  try {
    const places = await prisma.saved_place.findMany({
      where: { user_id: req.user.userId }
    });
    res.json({ places });
  } catch (error) {
    console.error('List saved places error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// DELETE /api/saved-places/:id
// ------------------------------------------------------------
app.delete('/api/saved-places/:id', authenticate, async (req, res) => {
  try {
    const place = await prisma.saved_place.findUnique({ where: { id: req.params.id } });
    if (!place || place.user_id !== req.user.userId) {
      return res.status(404).json({ error: 'Saved place not found' });
    }

    await prisma.saved_place.delete({ where: { id: place.id } });
    res.json({ message: 'Saved place removed' });
  } catch (error) {
    console.error('Delete saved place error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// GEOCODING
// ============================================================

// Nominatim's public endpoint asks callers to stay at/under 1 request per
// second and to identify the app via User-Agent — this queue enforces that
// across every user of this server, and the cache below cuts down repeat
// lookups for the same query. Swap the fetch call for a paid provider
// (Google Places/Mapbox) behind this same route if usage ever needs to
// scale past what Nominatim's fair-use policy allows.
const NOMINATIM_MIN_INTERVAL_MS = 1100;
let nominatimQueueTail = Promise.resolve();
let nominatimLastCallAt = 0;

function queueNominatimCall(task) {
  const run = nominatimQueueTail.then(async () => {
    const wait = Math.max(0, nominatimLastCallAt + NOMINATIM_MIN_INTERVAL_MS - Date.now());
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    nominatimLastCallAt = Date.now();
    return task();
  });
  // Keep the queue alive even if this call fails, so later searches still run.
  nominatimQueueTail = run.catch(() => {});
  return run;
}

const GEOCODE_CACHE_TTL_MS = 5 * 60 * 1000;
const geocodeCache = new Map();

// ------------------------------------------------------------
// GET /api/geocode/search?q=...&lat=&lng=
// Forward-geocodes free text into address suggestions for autocomplete,
// optionally biased toward a lat/lng (e.g. the rider's current location).
// ------------------------------------------------------------
app.get('/api/geocode/search', authenticate, async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    if (q.length < 3) {
      return res.status(400).json({ error: 'q must be at least 3 characters' });
    }

    const lat = req.query.lat != null ? Number(req.query.lat) : null;
    const lng = req.query.lng != null ? Number(req.query.lng) : null;
    const hasBias = lat != null && lng != null && !Number.isNaN(lat) && !Number.isNaN(lng);

    const cacheKey = `${q.toLowerCase()}|${hasBias ? lat.toFixed(2) : ''}|${hasBias ? lng.toFixed(2) : ''}`;
    const cached = geocodeCache.get(cacheKey);
    if (cached && Date.now() - cached.at < GEOCODE_CACHE_TTL_MS) {
      return res.json({ suggestions: cached.suggestions });
    }

    const params = new URLSearchParams({ q, format: 'jsonv2', addressdetails: '1', limit: '8', 'accept-language': 'en' });
    if (hasBias) {
      const span = 0.5; // roughly a ~50km box around the bias point — biases, doesn't restrict
      params.set('viewbox', `${lng - span},${lat + span},${lng + span},${lat - span}`);
      params.set('bounded', '0');
    }

    const suggestions = await queueNominatimCall(async () => {
      const response = await fetch(`https://nominatim.openstreetmap.org/search?${params.toString()}`, {
        headers: { 'User-Agent': 'RideEasy/1.0 (ride-hailing app; contact: support@rideeasy.app)' }
      });
      if (!response.ok) {
        throw new Error(`Nominatim responded with ${response.status}`);
      }
      const results = await response.json();
      return results.map((r) => ({
        display_name: r.display_name,
        lat: Number(r.lat),
        lng: Number(r.lon),
        type: r.type || null
      }));
    });

    if (geocodeCache.size > 500) geocodeCache.clear();
    geocodeCache.set(cacheKey, { suggestions, at: Date.now() });

    res.json({ suggestions });
  } catch (error) {
    console.error('Geocode search error:', error);
    res.status(502).json({ error: 'Address search is temporarily unavailable' });
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
    const [notifications, unread_count] = await Promise.all([
      prisma.notification.findMany({
        where: { user_id: req.user.userId },
        orderBy: { sent_at: 'desc' },
        take: 50
      }),
      prisma.notification.count({
        where: { user_id: req.user.userId, status: { not: 'read' } }
      })
    ]);
    res.json({ notifications, unread_count });
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

// ------------------------------------------------------------
// GET /api/notification-preferences
// Returns every known category/channel combination, defaulting to
// disabled when the user has never opted in (these are extra SMS/email
// pings on top of the always-on in-app inbox, not a mute switch for it).
// ------------------------------------------------------------
app.get('/api/notification-preferences', authenticate, async (req, res) => {
  try {
    const rows = await prisma.notification_preference.findMany({ where: { user_id: req.user.userId } });
    const byKey = new Map(rows.map((r) => [`${r.channel}:${r.category}`, r]));

    const preferences = NOTIFICATION_CHANNELS.flatMap((channel) =>
      NOTIFICATION_CATEGORIES.map((category) => {
        const existing = byKey.get(`${channel}:${category}`);
        return { channel, category, enabled: existing ? existing.enabled : false };
      })
    );

    res.json({ preferences });
  } catch (error) {
    console.error('Get notification preferences error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// PUT /api/notification-preferences
// Body: { preferences: [{ channel, category, enabled }, ...] }
// ------------------------------------------------------------
app.put('/api/notification-preferences', authenticate, async (req, res) => {
  try {
    const { preferences } = req.body || {};
    if (!Array.isArray(preferences) || preferences.length === 0) {
      return res.status(400).json({ error: 'preferences must be a non-empty array' });
    }

    const valid = preferences.filter(
      (p) => NOTIFICATION_CHANNELS.includes(p.channel) && NOTIFICATION_CATEGORIES.includes(p.category)
    );
    if (valid.length === 0) {
      return res.status(400).json({ error: 'No valid channel/category combinations provided' });
    }

    await Promise.all(
      valid.map((p) =>
        prisma.notification_preference.upsert({
          where: { user_id_channel_category: { user_id: req.user.userId, channel: p.channel, category: p.category } },
          update: { enabled: !!p.enabled },
          create: { user_id: req.user.userId, channel: p.channel, category: p.category, enabled: !!p.enabled }
        })
      )
    );

    const rows = await prisma.notification_preference.findMany({ where: { user_id: req.user.userId } });
    const byKey = new Map(rows.map((r) => [`${r.channel}:${r.category}`, r]));
    const merged = NOTIFICATION_CHANNELS.flatMap((channel) =>
      NOTIFICATION_CATEGORIES.map((category) => {
        const existing = byKey.get(`${channel}:${category}`);
        return { channel, category, enabled: existing ? existing.enabled : false };
      })
    );

    res.json({ message: 'Preferences updated', preferences: merged });
  } catch (error) {
    console.error('Update notification preferences error:', error);
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
        data:
          finalStatus === 'delivered' && parcel.delivery_fee != null
            ? {
                online_status: 'available',
                lifetime_earnings: { increment: round2(Number(parcel.delivery_fee) * DRIVER_EARNINGS_SHARE) },
                current_balance: { increment: round2(Number(parcel.delivery_fee) * DRIVER_EARNINGS_SHARE) }
              }
            : { online_status: 'available' }
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
// DRIVER BANK ACCOUNTS
// ============================================================

// ------------------------------------------------------------
// POST /api/driver/bank-accounts
// Registers a payout bank account. The raw account number is never persisted —
// only a masked version — same principle as payment_method's card last4.
// ------------------------------------------------------------
app.post('/api/driver/bank-accounts', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can add bank accounts' });

    const { account_holder_name, bank_name, account_number, country_id } = req.body || {};
    if (!account_holder_name || !bank_name || !account_number || !country_id) {
      return res.status(400).json({
        error: 'Missing required fields: account_holder_name, bank_name, account_number, country_id'
      });
    }

    const digitsOnly = String(account_number).replace(/\D/g, '');
    if (digitsOnly.length < 4) {
      return res.status(400).json({ error: 'account_number must have at least 4 digits' });
    }

    const existingCount = await prisma.driver_bank_account.count({ where: { driver_id: driver.user_id } });

    const bankAccount = await prisma.driver_bank_account.create({
      data: {
        driver_id: driver.user_id,
        country_id,
        account_holder_name,
        bank_name,
        account_number_masked: `•••• ${digitsOnly.slice(-4)}`,
        is_default: existingCount === 0
      }
    });

    res.status(201).json({ message: 'Bank account added', bank_account: bankAccount });
  } catch (error) {
    console.error('Add bank account error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/driver/bank-accounts
// ------------------------------------------------------------
app.get('/api/driver/bank-accounts', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can view bank accounts' });

    const bankAccounts = await prisma.driver_bank_account.findMany({
      where: { driver_id: driver.user_id },
      orderBy: [{ is_default: 'desc' }, { added_at: 'desc' }]
    });
    res.json({ bank_accounts: bankAccounts });
  } catch (error) {
    console.error('List bank accounts error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/driver/bank-accounts/:id/default
// ------------------------------------------------------------
app.post('/api/driver/bank-accounts/:id/default', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can update bank accounts' });

    const account = await prisma.driver_bank_account.findUnique({ where: { id: req.params.id } });
    if (!account || account.driver_id !== driver.user_id) {
      return res.status(404).json({ error: 'Bank account not found' });
    }

    await prisma.$transaction([
      prisma.driver_bank_account.updateMany({
        where: { driver_id: driver.user_id, is_default: true },
        data: { is_default: false }
      }),
      prisma.driver_bank_account.update({ where: { id: account.id }, data: { is_default: true } })
    ]);

    res.json({ message: 'Default bank account updated' });
  } catch (error) {
    console.error('Set default bank account error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// DELETE /api/driver/bank-accounts/:id
// ------------------------------------------------------------
app.delete('/api/driver/bank-accounts/:id', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can remove bank accounts' });

    const account = await prisma.driver_bank_account.findUnique({ where: { id: req.params.id } });
    if (!account || account.driver_id !== driver.user_id) {
      return res.status(404).json({ error: 'Bank account not found' });
    }

    // Any payout — settled or not — holds a hard FK to the bank account, so it can
    // never actually be deleted once used. Surface that as a clear 409 instead of a 500.
    const linkedPayout = await prisma.driver_payout.findFirst({
      where: { bank_account_id: account.id }
    });
    if (linkedPayout) {
      return res.status(409).json({ error: 'Cannot remove a bank account that has payout history' });
    }

    await prisma.driver_bank_account.delete({ where: { id: account.id } });

    if (account.is_default) {
      const nextAccount = await prisma.driver_bank_account.findFirst({
        where: { driver_id: driver.user_id },
        orderBy: { added_at: 'asc' }
      });
      if (nextAccount) {
        await prisma.driver_bank_account.update({ where: { id: nextAccount.id }, data: { is_default: true } });
      }
    }

    res.json({ message: 'Bank account removed' });
  } catch (error) {
    console.error('Delete bank account error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/admin/driver-bank-accounts?status=pending_verification
// ------------------------------------------------------------
app.get('/api/admin/driver-bank-accounts', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const { status } = req.query;
    const bankAccounts = await prisma.driver_bank_account.findMany({
      where: status ? { status } : {},
      orderBy: { added_at: 'desc' },
      take: 100,
      include: { driver: { include: { app_user: true } }, country: true }
    });

    res.json({ bank_accounts: bankAccounts });
  } catch (error) {
    console.error('Admin list bank accounts error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/admin/driver-bank-accounts/:id/review
// ------------------------------------------------------------
app.post('/api/admin/driver-bank-accounts/:id/review', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const account = await prisma.driver_bank_account.findUnique({ where: { id: req.params.id } });
    if (!account) return res.status(404).json({ error: 'Bank account not found' });

    const { decision } = req.body || {};
    if (!['verified', 'rejected'].includes(decision)) {
      return res.status(400).json({ error: "decision must be 'verified' or 'rejected'" });
    }

    const updated = await prisma.driver_bank_account.update({
      where: { id: account.id },
      data: { status: decision, verified_at: decision === 'verified' ? new Date() : null }
    });

    await createNotification(account.driver_id, {
      template_key: decision === 'verified' ? 'bank_account_verified' : 'bank_account_rejected',
      title: decision === 'verified' ? 'Bank account verified' : 'Bank account rejected',
      body: decision === 'verified'
        ? `Your bank account ending in ${account.account_number_masked.slice(-4)} is verified and ready for payouts.`
        : 'Your bank account could not be verified — please check the details and re-add it.'
    });

    res.json({ message: 'Bank account reviewed', bank_account: updated });
  } catch (error) {
    console.error('Review bank account error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// DRIVER PAYOUTS
// ============================================================

// ------------------------------------------------------------
// POST /api/driver/payouts
// Requests a payout of the driver's available balance to a bank account.
// No payment gateway is wired up — this reserves the funds (moves them out of
// current_balance immediately) and records a 'pending' payout for an admin to settle.
// ------------------------------------------------------------
app.post('/api/driver/payouts', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can request payouts' });

    const { bank_account_id, amount } = req.body || {};
    const bankAccount = bank_account_id
      ? await prisma.driver_bank_account.findUnique({ where: { id: bank_account_id } })
      : await prisma.driver_bank_account.findFirst({ where: { driver_id: driver.user_id, is_default: true } });

    if (!bankAccount || bankAccount.driver_id !== driver.user_id) {
      return res.status(400).json({ error: 'A valid bank account is required — add one first' });
    }
    if (bankAccount.status !== 'verified') {
      return res.status(400).json({ error: 'This bank account is not verified yet' });
    }

    const availableBalance = Number(driver.current_balance);
    const requestedAmount = amount != null ? round2(Number(amount)) : availableBalance;

    if (!(requestedAmount > 0)) {
      return res.status(400).json({ error: 'Nothing available to pay out' });
    }
    if (requestedAmount > availableBalance) {
      return res.status(400).json({ error: 'Requested amount exceeds available balance' });
    }

    const lastPayout = await prisma.driver_payout.findFirst({
      where: { driver_id: driver.user_id },
      orderBy: { initiated_at: 'desc' }
    });

    const [payout] = await prisma.$transaction([
      prisma.driver_payout.create({
        data: {
          driver_id: driver.user_id,
          bank_account_id: bankAccount.id,
          amount: requestedAmount,
          currency: 'PKR',
          status: 'pending',
          period_start: lastPayout?.period_end || new Date(0),
          period_end: new Date()
        }
      }),
      prisma.driver.update({
        where: { user_id: driver.user_id },
        data: { current_balance: { decrement: requestedAmount } }
      })
    ]);

    res.status(201).json({ message: 'Payout requested', payout });
  } catch (error) {
    console.error('Request payout error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/driver/payouts
// ------------------------------------------------------------
app.get('/api/driver/payouts', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can view payouts' });

    const payouts = await prisma.driver_payout.findMany({
      where: { driver_id: driver.user_id },
      orderBy: { initiated_at: 'desc' },
      include: { driver_bank_account: true }
    });
    res.json({ payouts });
  } catch (error) {
    console.error('List payouts error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/admin/driver-payouts?status=pending
// ------------------------------------------------------------
app.get('/api/admin/driver-payouts', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const { status } = req.query;
    const payouts = await prisma.driver_payout.findMany({
      where: status ? { status } : {},
      orderBy: { initiated_at: 'desc' },
      take: 100,
      include: { driver: { include: { app_user: true } }, driver_bank_account: true }
    });

    res.json({ payouts });
  } catch (error) {
    console.error('Admin list payouts error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/admin/driver-payouts/:id/settle
// Marks a pending payout paid or failed. No real payment gateway is integrated —
// this records the outcome, and refunds the driver's balance if it failed.
// ------------------------------------------------------------
app.post('/api/admin/driver-payouts/:id/settle', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const payout = await prisma.driver_payout.findUnique({ where: { id: req.params.id } });
    if (!payout) return res.status(404).json({ error: 'Payout not found' });
    if (payout.status !== 'pending') {
      return res.status(409).json({ error: 'Payout has already been settled' });
    }

    const { outcome, gateway_ref } = req.body || {};
    if (!['paid', 'failed'].includes(outcome)) {
      return res.status(400).json({ error: "outcome must be 'paid' or 'failed'" });
    }

    const operations = [
      prisma.driver_payout.update({
        where: { id: payout.id },
        data: {
          status: outcome,
          gateway_ref: outcome === 'paid' ? (gateway_ref || null) : undefined,
          paid_at: outcome === 'paid' ? new Date() : undefined
        }
      })
    ];
    if (outcome === 'failed') {
      operations.push(
        prisma.driver.update({
          where: { user_id: payout.driver_id },
          data: { current_balance: { increment: payout.amount } }
        })
      );
    }

    const [updatedPayout] = await prisma.$transaction(operations);

    await createNotification(payout.driver_id, {
      template_key: outcome === 'paid' ? 'payout_paid' : 'payout_failed',
      title: outcome === 'paid' ? 'Payout sent' : 'Payout failed',
      body: outcome === 'paid'
        ? `${payout.amount} ${payout.currency} has been sent to your bank account.`
        : `Your payout of ${payout.amount} ${payout.currency} failed and has been returned to your balance.`
    });

    res.json({ message: 'Payout settled', payout: updatedPayout });
  } catch (error) {
    console.error('Settle payout error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// DRIVER INCENTIVES
// ============================================================

// ------------------------------------------------------------
// GET /api/driver/incentives
// Active incentive programs for the driver's current city (plus any global,
// city-less programs), merged with the driver's own progress on each.
// ------------------------------------------------------------
app.get('/api/driver/incentives', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can view incentives' });

    const today = new Date();
    const programs = await prisma.incentive_program.findMany({
      where: {
        is_active: true,
        starts_on: { lte: today },
        ends_on: { gte: today },
        OR: [{ city_id: driver.current_city_id }, { city_id: null }]
      },
      orderBy: { ends_on: 'asc' }
    });

    const progressRows = await prisma.driver_incentive.findMany({
      where: { driver_id: driver.user_id, program_id: { in: programs.map((p) => p.id) } }
    });
    const progressByProgram = Object.fromEntries(progressRows.map((row) => [row.program_id, row]));

    const incentives = programs.map((program) => ({
      program,
      progress: progressByProgram[program.id] || {
        progress_rides: 0,
        progress_hours: 0,
        bonus_earned: 0,
        status: 'active'
      }
    }));

    res.json({ incentives });
  } catch (error) {
    console.error('List incentives error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// DRIVER DOCUMENTS (KYC)
// ============================================================

// ------------------------------------------------------------
// POST /api/driver/documents
// Submits (or resubmits) a KYC document for review.
// ------------------------------------------------------------
app.post('/api/driver/documents', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can submit documents' });

    const { doc_type, url, expires_at } = req.body || {};
    if (!REQUIRED_DRIVER_DOC_TYPES.includes(doc_type) || !url) {
      return res.status(400).json({
        error: `doc_type (one of ${REQUIRED_DRIVER_DOC_TYPES.join(', ')}) and url are required`
      });
    }

    const document = await prisma.driver_document.create({
      data: {
        driver_id: driver.user_id,
        doc_type,
        url,
        expires_at: expires_at ? new Date(expires_at) : null
      }
    });

    if (driver.kyc_status === 'not_started' || driver.kyc_status === 'rejected') {
      await prisma.driver.update({ where: { user_id: driver.user_id }, data: { kyc_status: 'in_review' } });
    }

    res.status(201).json({ message: 'Document submitted for review', document });
  } catch (error) {
    console.error('Submit document error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/driver/documents
// ------------------------------------------------------------
app.get('/api/driver/documents', authenticate, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { user_id: req.user.userId } });
    if (!driver) return res.status(403).json({ error: 'Only drivers can view documents' });

    const documents = await prisma.driver_document.findMany({
      where: { driver_id: driver.user_id },
      orderBy: { uploaded_at: 'desc' }
    });
    res.json({ documents, required_doc_types: REQUIRED_DRIVER_DOC_TYPES, kyc_status: driver.kyc_status });
  } catch (error) {
    console.error('List documents error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// GET /api/admin/driver-documents?status=pending
// ------------------------------------------------------------
app.get('/api/admin/driver-documents', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const { status } = req.query;
    const documents = await prisma.driver_document.findMany({
      where: status ? { verification_status: status } : {},
      orderBy: { uploaded_at: 'desc' },
      take: 100,
      include: { driver: { include: { app_user: true } } }
    });

    res.json({ documents });
  } catch (error) {
    console.error('Admin list driver documents error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ------------------------------------------------------------
// POST /api/admin/driver-documents/:id/review
// ------------------------------------------------------------
app.post('/api/admin/driver-documents/:id/review', authenticate, async (req, res) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { user_id: req.user.userId } });
    if (!admin) return res.status(403).json({ error: 'Admin access required' });

    const document = await prisma.driver_document.findUnique({ where: { id: req.params.id } });
    if (!document) return res.status(404).json({ error: 'Document not found' });

    const { decision, rejection_reason } = req.body || {};
    if (!['approved', 'rejected'].includes(decision)) {
      return res.status(400).json({ error: "decision must be 'approved' or 'rejected'" });
    }
    if (decision === 'rejected' && !rejection_reason) {
      return res.status(400).json({ error: 'rejection_reason is required when rejecting a document' });
    }

    const updated = await prisma.driver_document.update({
      where: { id: document.id },
      data: {
        verification_status: decision,
        rejection_reason: decision === 'rejected' ? rejection_reason : null,
        reviewed_at: new Date()
      }
    });

    if (decision === 'rejected') {
      await prisma.driver.update({ where: { user_id: document.driver_id }, data: { kyc_status: 'rejected' } });
    } else {
      const approvedDocs = await prisma.driver_document.findMany({
        where: { driver_id: document.driver_id, verification_status: 'approved' }
      });
      const approvedTypes = new Set(approvedDocs.map((d) => d.doc_type));
      const allRequiredApproved = REQUIRED_DRIVER_DOC_TYPES.every((type) => approvedTypes.has(type));
      if (allRequiredApproved) {
        await prisma.driver.update({ where: { user_id: document.driver_id }, data: { kyc_status: 'approved' } });
      }
    }

    await createNotification(document.driver_id, {
      template_key: decision === 'approved' ? 'document_approved' : 'document_rejected',
      title: decision === 'approved' ? 'Document approved' : 'Document needs attention',
      body: decision === 'approved'
        ? `Your ${document.doc_type.replace(/_/g, ' ')} was approved.`
        : `Your ${document.doc_type.replace(/_/g, ' ')} was rejected: ${rejection_reason}`
    });

    res.json({ message: 'Document reviewed', document: updated });
  } catch (error) {
    console.error('Review document error:', error);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// ============================================================
// START SERVER
// ============================================================
app.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
});