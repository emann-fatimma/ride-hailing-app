import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';

class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  List<Map<String, dynamic>> _places = [];
  bool _isLoading = true;
  String? _error;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await ApiService.getSavedPlaces();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) {
        _places = List<Map<String, dynamic>>.from(result['data']);
      } else {
        _error = result['error'];
      }
    });
  }

  Future<void> _delete(String placeId) async {
    setState(() => _deletingId = placeId);
    final result = await ApiService.deleteSavedPlace(placeId);
    if (!mounted) return;
    setState(() => _deletingId = null);
    if (result['success']) {
      _load();
    } else {
      setState(() => _error = result['error']);
    }
  }

  Future<void> _addPlace() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const _PickPlaceScreen()),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('Saved Places', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: _addPlace,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Place', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (_places.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(child: Text('No saved places yet', style: AppTextStyles.body)),
                    )
                  else
                    ..._places.map((place) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _PlaceCard(
                            place: place,
                            isDeleting: _deletingId == place['id'],
                            onDelete: () => _delete(place['id'] as String),
                          ),
                        )),
                  const SizedBox(height: 72),
                ],
              ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final bool isDeleting;
  final VoidCallback onDelete;

  const _PlaceCard({required this.place, required this.isDeleting, required this.onDelete});

  IconData get _icon {
    final label = (place['label'] as String).toLowerCase();
    if (label == 'home') return Icons.home_outlined;
    if (label == 'work') return Icons.work_outline;
    return Icons.place_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(_icon, color: AppColors.primary, size: 26),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(place['label'] as String, style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text(place['address'] as String, style: AppTextStyles.helper, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          isDeleting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: onDelete,
                ),
        ],
      ),
    );
  }
}

// Full-screen tap-to-pick map, mirroring BookRideScreen's picker, then a label
// to save it under.
class _PickPlaceScreen extends StatefulWidget {
  const _PickPlaceScreen();

  @override
  State<_PickPlaceScreen> createState() => _PickPlaceScreenState();
}

class _PickPlaceScreenState extends State<_PickPlaceScreen> {
  final MapController _mapController = MapController();
  final _labelController = TextEditingController();
  LatLng? _point;
  String _address = 'Tap the map to choose a location';
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final position = await LocationService.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      _mapController.move(latLng, 15);
    } catch (_) {
      // Falls back to the default map center — user can still tap to pick.
    }
  }

  Future<void> _onMapTap(TapPosition tapPosition, LatLng point) async {
    setState(() {
      _point = point;
      _address = 'Loading address…';
    });
    final address = await LocationService.addressFromCoordinates(point.latitude, point.longitude);
    if (!mounted) return;
    setState(() => _address = address);
  }

  Future<void> _save() async {
    if (_point == null) {
      setState(() => _error = 'Tap the map to choose a location');
      return;
    }
    if (_labelController.text.trim().isEmpty) {
      setState(() => _error = 'Give this place a label, like Home or Work');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final result = await ApiService.addSavedPlace(
      label: _labelController.text.trim(),
      address: _address,
      lat: _point!.latitude,
      lng: _point!.longitude,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (result['success']) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = result['error']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(24.8607, 67.0011),
                    initialZoom: 13,
                    onTap: _onMapTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.mobile',
                    ),
                    if (_point != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _point!,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_on, color: AppColors.primary, size: 36),
                        ),
                      ]),
                    RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_address, style: AppTextStyles.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(labelText: 'Label (e.g. Home, Work)', border: OutlineInputBorder()),
                ),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Place', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
