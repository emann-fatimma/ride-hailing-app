import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'location_picker_screen.dart';
import 'ride_status_screen.dart';

class BookRideScreen extends StatefulWidget {
  const BookRideScreen({super.key});

  @override
  State<BookRideScreen> createState() => _BookRideScreenState();
}

class _BookRideScreenState extends State<BookRideScreen> {
  final MapController _mapController = MapController();

  LatLng? _pickup;
  LatLng? _dropoff;
  String _pickupAddress = 'Locating you…';
  String _dropoffAddress = 'Where to?';

  List<Map<String, dynamic>> _vehicleTypes = [];
  String? _selectedVehicleTypeId;
  bool _loadingVehicleTypes = true;

  Map<String, dynamic>? _estimate;
  bool _isEstimating = false;
  bool _isRequesting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadVehicleTypes();
  }

  Future<void> _pickPickup() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: 'Set pickup location',
          initialPoint: _pickup,
          initialAddress: _pickup != null ? _pickupAddress : null,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pickup = LatLng(result['lat'] as double, result['lng'] as double);
      _pickupAddress = result['address'] as String;
      _estimate = null;
    });
    _mapController.move(_pickup!, 15);
  }

  Future<void> _pickDropoff() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: 'Set dropoff location',
          initialPoint: _dropoff,
          initialAddress: _dropoff != null ? _dropoffAddress : null,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _dropoff = LatLng(result['lat'] as double, result['lng'] as double);
      _dropoffAddress = result['address'] as String;
      _estimate = null;
    });
    _mapController.move(_dropoff!, 15);
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final position = await LocationService.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);
      final address = await LocationService.addressFromCoordinates(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _pickup = latLng;
        _pickupAddress = address;
      });
      _mapController.move(latLng, 15);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pickupAddress = 'Could not detect location — tap map to set pickup');
    }
  }

  Future<void> _loadVehicleTypes() async {
    final result = await ApiService.getVehicleTypes();
    if (!mounted) return;
    if (result['success']) {
      final types = List<Map<String, dynamic>>.from(result['data']);
      setState(() {
        _vehicleTypes = types;
        _selectedVehicleTypeId = types.isNotEmpty ? types.first['id'] as String : null;
        _loadingVehicleTypes = false;
      });
    } else {
      setState(() => _loadingVehicleTypes = false);
    }
  }

  Future<void> _getEstimate() async {
    if (_pickup == null || _dropoff == null || _selectedVehicleTypeId == null) return;
    setState(() {
      _isEstimating = true;
      _error = null;
      _estimate = null;
    });
    final result = await ApiService.estimateRide(
      vehicleTypeId: _selectedVehicleTypeId!,
      pickupLat: _pickup!.latitude,
      pickupLng: _pickup!.longitude,
      dropoffLat: _dropoff!.latitude,
      dropoffLng: _dropoff!.longitude,
    );
    if (!mounted) return;
    setState(() {
      _isEstimating = false;
      if (result['success']) {
        _estimate = result['data'];
      } else {
        _error = result['error'];
      }
    });
  }

  Future<void> _requestRide() async {
    if (_pickup == null || _dropoff == null || _estimate == null) return;
    setState(() {
      _isRequesting = true;
      _error = null;
    });
    final result = await ApiService.createRide(
      pickupAddress: _pickupAddress,
      dropoffAddress: _dropoffAddress,
      pickupLat: _pickup!.latitude,
      pickupLng: _pickup!.longitude,
      dropoffLat: _dropoff!.latitude,
      dropoffLng: _dropoff!.longitude,
      fareEstimateId: _estimate!['id'] as String?,
    );
    if (!mounted) return;
    setState(() => _isRequesting = false);
    if (result['success']) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => RideStatusScreen(rideId: result['data']['id'] as String)),
      );
    } else {
      setState(() => _error = result['error']);
    }
  }

  List<Marker> get _markers => [
        if (_pickup != null)
          Marker(
            point: _pickup!,
            width: 40,
            height: 40,
            child: const Icon(Icons.my_location, color: AppColors.success, size: 32),
          ),
        if (_dropoff != null)
          Marker(
            point: _dropoff!,
            width: 40,
            height: 40,
            child: const Icon(Icons.location_on, color: AppColors.error, size: 36),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final canEstimate = _pickup != null && _dropoff != null && _selectedVehicleTypeId != null && !_isEstimating;
    final canRequest = _estimate != null && !_isRequesting;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(24.8607, 67.0011), // Karachi — replaced once GPS resolves
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.mobile',
                    ),
                    MarkerLayer(markers: _markers),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, -2))],
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAddressRow(
                    icon: Icons.my_location,
                    color: AppColors.success,
                    label: 'Pickup',
                    address: _pickupAddress,
                    onTap: _pickPickup,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildAddressRow(
                    icon: Icons.location_on,
                    color: AppColors.error,
                    label: 'Dropoff',
                    address: _dropoffAddress,
                    onTap: _pickDropoff,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  Text('Vehicle', style: AppTextStyles.label),
                  const SizedBox(height: AppSpacing.sm),
                  if (_loadingVehicleTypes)
                    const Center(child: CircularProgressIndicator())
                  else
                    SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _vehicleTypes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final type = _vehicleTypes[index];
                          final selected = type['id'] == _selectedVehicleTypeId;
                          return GestureDetector(
                            onTap: () => setState(() {
                              _selectedVehicleTypeId = type['id'] as String;
                              _estimate = null;
                            }),
                            child: Container(
                              width: 110,
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: selected ? AppColors.primary : Colors.white,
                                border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    type['name'] as String,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: selected ? Colors.white : AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Up to ${type['capacity']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: selected ? Colors.white70 : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: AppSpacing.md),

                  if (_estimate != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Estimated fare', style: AppTextStyles.helper),
                              Text(
                                'PKR ${_estimate!['estimated_min']} – ${_estimate!['estimated_max']}',
                                style: AppTextStyles.heading1.copyWith(fontSize: 18),
                              ),
                            ],
                          ),
                          Text(
                            '${_estimate!['estimated_distance_km']} km',
                            style: AppTextStyles.body,
                          ),
                        ],
                      ),
                    ),

                  if (_error != null) ...[
                    Text(_error!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                  ],

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.primaryLight,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _estimate == null
                          ? (canEstimate ? _getEstimate : null)
                          : (canRequest ? _requestRide : null),
                      child: (_isEstimating || _isRequesting)
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _estimate == null ? 'Get Fare Estimate' : 'Request Ride',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow({
    required IconData icon,
    required Color color,
    required String label,
    required String address,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.helper),
                  Text(address, style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
