import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../services/api_service.dart';
import 'driver_home_screen.dart';

const _statusLabels = {
  'matched': 'Heading to pickup',
  'in_progress': 'Trip in progress',
  'completed': 'Trip completed',
  'cancelled': 'Ride was cancelled',
};

class DriverActiveRideScreen extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic>? initialRide;

  const DriverActiveRideScreen({super.key, required this.rideId, this.initialRide});

  @override
  State<DriverActiveRideScreen> createState() => _DriverActiveRideScreenState();
}

class _DriverActiveRideScreenState extends State<DriverActiveRideScreen> {
  Timer? _pollTimer;
  Map<String, dynamic>? _ride;
  bool _isActing = false;
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _ride = widget.initialRide;
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchRide());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchRide() async {
    final result = await ApiService.getRide(widget.rideId);
    if (!mounted) return;
    if (result['success']) {
      setState(() => _ride = result['data']);
      final status = _ride?['status'];
      if ((status == 'completed' || status == 'cancelled') && !_finished) {
        _finished = true;
        _pollTimer?.cancel();
      }
    } else {
      setState(() => _error = result['error']);
    }
  }

  Future<void> _startTrip() async {
    setState(() {
      _isActing = true;
      _error = null;
    });
    final result = await ApiService.startRide(widget.rideId);
    if (!mounted) return;
    setState(() => _isActing = false);
    if (result['success']) {
      setState(() => _ride = result['data']);
    } else {
      setState(() => _error = result['error']);
    }
  }

  Future<void> _completeTrip() async {
    setState(() {
      _isActing = true;
      _error = null;
    });
    final result = await ApiService.completeRide(widget.rideId);
    if (!mounted) return;
    setState(() => _isActing = false);
    if (result['success']) {
      setState(() => _ride = result['data']);
    } else {
      setState(() => _error = result['error']);
    }
  }

  void _backToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const DriverHomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    final status = ride?['status'] as String?;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ride == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(
                          (ride['pickup_lat'] as num).toDouble(),
                          (ride['pickup_lng'] as num).toDouble(),
                        ),
                        initialZoom: 13,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.mobile',
                        ),
                        MarkerLayer(markers: [
                          Marker(
                            point: LatLng(
                              (ride['pickup_lat'] as num).toDouble(),
                              (ride['pickup_lng'] as num).toDouble(),
                            ),
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.my_location, color: AppColors.success, size: 32),
                          ),
                          Marker(
                            point: LatLng(
                              (ride['dropoff_lat'] as num).toDouble(),
                              (ride['dropoff_lng'] as num).toDouble(),
                            ),
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: AppColors.error, size: 36),
                          ),
                        ]),
                        RichAttributionWidget(
                          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, -2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_statusLabels[status] ?? status ?? '', style: AppTextStyles.heading1),
                        const SizedBox(height: AppSpacing.sm),
                        _buildAddressLine(Icons.my_location, AppColors.success, ride['pickup_address'] as String),
                        const SizedBox(height: 4),
                        _buildAddressLine(Icons.location_on, AppColors.error, ride['dropoff_address'] as String),
                        if (ride['total_fare'] != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text('Fare: PKR ${ride['total_fare']}', style: AppTextStyles.body),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(_error!, style: AppTextStyles.errorText),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              disabledBackgroundColor: AppColors.primaryLight,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isActing
                                ? null
                                : switch (status) {
                                    'matched' => _startTrip,
                                    'in_progress' => _completeTrip,
                                    'completed' || 'cancelled' => _backToHome,
                                    _ => null,
                                  },
                            child: _isActing
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    switch (status) {
                                      'matched' => 'Start Trip',
                                      'in_progress' => 'Complete Trip',
                                      'completed' || 'cancelled' => 'Back to Home',
                                      _ => '...',
                                    },
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAddressLine(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
