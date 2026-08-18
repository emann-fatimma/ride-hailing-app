import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'driver_active_ride_screen.dart';
import 'profile_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentLocation;

  bool _isOnline = false;
  bool _isTogglingOnline = false;
  bool _isLoadingProfile = true;
  Map<String, dynamic>? _driverProfile;

  Timer? _locationTimer;
  Timer? _dispatchTimer;
  Map<String, dynamic>? _currentOffer;
  bool _isRespondingToOffer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _dispatchTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final result = await ApiService.getMe();
    if (!mounted) return;
    if (result['success']) {
      final user = result['data'] as Map<String, dynamic>;
      final driver = user['driver'] as Map<String, dynamic>?;
      setState(() {
        _driverProfile = {'name': user['name'], ...?driver};
        _isLoadingProfile = false;
        _isOnline = driver?['online_status'] == 'available';
      });
      if (_isOnline) _startPolling();
    } else {
      setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final position = await LocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
      _mapController.move(_currentLocation!, 15);
    } catch (_) {
      // Map just falls back to a default center; going online still works.
    }
  }

  void _startPolling() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) => _pingLocation());
    _dispatchTimer?.cancel();
    _dispatchTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollDispatches());
    _pingLocation();
    _pollDispatches();
  }

  void _stopPolling() {
    _locationTimer?.cancel();
    _dispatchTimer?.cancel();
    setState(() => _currentOffer = null);
  }

  Future<void> _pingLocation() async {
    try {
      final position = await LocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
      await ApiService.updateDriverLocation(lat: position.latitude, lng: position.longitude);
    } catch (_) {
      // Skip this tick — will retry on the next timer fire.
    }
  }

  Future<void> _pollDispatches() async {
    if (_currentOffer != null || _isRespondingToOffer) return;
    final result = await ApiService.getDispatches();
    if (!mounted) return;
    if (result['success']) {
      final offers = List<Map<String, dynamic>>.from(result['data']);
      if (offers.isNotEmpty) {
        setState(() => _currentOffer = offers.first);
      }
    }
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => _isTogglingOnline = true);
    final result = await ApiService.setDriverOnline(value ? 'available' : 'offline');
    if (!mounted) return;
    setState(() => _isTogglingOnline = false);
    if (result['success']) {
      setState(() => _isOnline = value);
      if (value) {
        _startPolling();
      } else {
        _stopPolling();
      }
    } else {
      setState(() => _error = result['error']);
    }
  }

  Future<void> _acceptOffer() async {
    final ride = _currentOffer?['ride'] as Map<String, dynamic>?;
    if (ride == null) return;
    setState(() => _isRespondingToOffer = true);
    final result = await ApiService.acceptRide(ride['id'] as String);
    if (!mounted) return;
    setState(() {
      _isRespondingToOffer = false;
      _currentOffer = null;
    });
    if (result['success']) {
      _locationTimer?.cancel();
      _dispatchTimer?.cancel();
      Navigator.of(context)
          .push(MaterialPageRoute(
            builder: (context) => DriverActiveRideScreen(rideId: ride['id'] as String, initialRide: result['data']),
          ))
          .then((_) {
        if (_isOnline) _startPolling();
      });
    } else {
      setState(() => _error = result['error']);
    }
  }

  Future<void> _declineOffer() async {
    final ride = _currentOffer?['ride'] as Map<String, dynamic>?;
    if (ride == null) return;
    setState(() => _isRespondingToOffer = true);
    await ApiService.declineRide(ride['id'] as String);
    if (!mounted) return;
    setState(() {
      _isRespondingToOffer = false;
      _currentOffer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _driverProfile?['name'] as String? ?? 'Driver';
    final rating = _driverProfile?['rating_avg'];
    final totalRides = _driverProfile?['total_rides'];
    final offerRide = _currentOffer?['ride'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? const LatLng(24.8607, 67.0011),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.mobile',
              ),
              if (_currentLocation != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _currentLocation!,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.local_taxi, color: AppColors.primary, size: 32),
                  ),
                ]),
              RichAttributionWidget(
                attributions: [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_isOnline ? 'Online' : 'Offline', style: AppTextStyles.label),
                        Switch(
                          value: _isOnline,
                          onChanged: _isTogglingOnline || _isLoadingProfile ? null : _toggleOnline,
                          activeThumbColor: AppColors.success,
                        ),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.person_outline, color: AppColors.textPrimary),
                      tooltip: 'Profile',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const ProfileScreen()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (offerRide != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('New Ride Request', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
                      const SizedBox(height: AppSpacing.sm),
                      Row(children: [
                        const Icon(Icons.my_location, size: 16, color: AppColors.success),
                        const SizedBox(width: 6),
                        Expanded(child: Text(offerRide['pickup_address'] as String, style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on, size: 16, color: AppColors.error),
                        const SizedBox(width: 6),
                        Expanded(child: Text(offerRide['dropoff_address'] as String, style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      if (_currentOffer?['distance_to_pickup_km'] != null) ...[
                        const SizedBox(height: 4),
                        Text('${_currentOffer!['distance_to_pickup_km']} km to pickup', style: AppTextStyles.helper),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.error),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: _isRespondingToOffer ? null : _declineOffer,
                              child: const Text('Decline', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: _isRespondingToOffer ? null : _acceptOffer,
                              child: _isRespondingToOffer
                                  ? const SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Text('Accept', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 16)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hi, $name', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
                          const SizedBox(height: 4),
                          Text(
                            _isOnline ? 'Waiting for ride requests…' : 'Go online to start receiving rides',
                            style: AppTextStyles.subtitle,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 4),
                            Text(_error!, style: AppTextStyles.errorText),
                          ],
                        ],
                      ),
                      if (rating != null || totalRides != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(children: [
                              const Icon(Icons.star, size: 16, color: Color(0xFFF5C542)),
                              const SizedBox(width: 4),
                              Text('${rating ?? '—'}', style: AppTextStyles.label),
                            ]),
                            Text('$totalRides rides', style: AppTextStyles.helper),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
