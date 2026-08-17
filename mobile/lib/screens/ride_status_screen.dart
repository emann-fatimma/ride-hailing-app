import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../services/api_service.dart';
import 'rate_ride_screen.dart';
import 'home_screen.dart';

const _statusLabels = {
  'requested': 'Finding you a driver…',
  'scheduled': 'Ride scheduled',
  'matched': 'Driver is on the way',
  'in_progress': 'Trip in progress',
  'completed': 'Trip completed',
  'cancelled': 'Ride cancelled',
};

const _cancellableStatuses = {'requested', 'scheduled', 'matched'};

class RideStatusScreen extends StatefulWidget {
  final String rideId;

  const RideStatusScreen({super.key, required this.rideId});

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen> {
  Timer? _pollTimer;
  Map<String, dynamic>? _ride;
  bool _isCancelling = false;
  String? _error;
  bool _navigatedToRating = false;

  @override
  void initState() {
    super.initState();
    _fetchRide();
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
      if (status == 'completed' && !_navigatedToRating) {
        _navigatedToRating = true;
        _pollTimer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => RateRideScreen(rideId: widget.rideId)),
        );
      } else if (status == 'cancelled') {
        _pollTimer?.cancel();
      }
    } else {
      setState(() => _error = result['error']);
    }
  }

  Future<void> _cancelRide() async {
    setState(() => _isCancelling = true);
    final result = await ApiService.cancelRide(widget.rideId);
    if (!mounted) return;
    setState(() => _isCancelling = false);
    if (result['success']) {
      setState(() => _ride = result['data']);
      _pollTimer?.cancel();
    } else {
      setState(() => _error = result['error']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    final status = ride?['status'] as String?;
    final canCancel = status != null && _cancellableStatuses.contains(status);

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
                        if (status == 'cancelled')
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(builder: (context) => const HomeScreen()),
                                (route) => false,
                              ),
                              child: const Text('Back to Home', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          )
                        else if (canCancel)
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.error),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isCancelling ? null : _cancelRide,
                              child: _isCancelling
                                  ? const SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(color: AppColors.error, strokeWidth: 2),
                                    )
                                  : const Text('Cancel Ride', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
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
