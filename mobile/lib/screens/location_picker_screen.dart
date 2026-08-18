import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';

// Shared "where is it?" picker: search-as-you-type with debounced backend
// autocomplete, a saved-places shortcut list, "use current location", and a
// map that still supports tap-to-refine. Pops with {'lat','lng','address'}.
class LocationPickerScreen extends StatefulWidget {
  final String title;
  final LatLng? initialPoint;
  final String? initialAddress;

  const LocationPickerScreen({
    super.key,
    this.title = 'Choose a location',
    this.initialPoint,
    this.initialAddress,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _fallbackCenter = LatLng(24.8607, 67.0011); // Karachi — replaced once GPS/selection resolves

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  int _requestId = 0;

  LatLng? _point;
  String _address = '';
  LatLng? _biasPoint;

  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearching = false;
  String? _searchError;

  List<Map<String, dynamic>> _savedPlaces = [];
  bool _isLocatingCurrent = false;
  bool _isReverseGeocoding = false;

  bool get _searchActive => _focusNode.hasFocus || _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _point = widget.initialPoint;
    _address = widget.initialAddress ?? '';
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _loadInitialLocation();
    _loadSavedPlaces();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitialLocation() async {
    if (widget.initialPoint != null) {
      setState(() => _biasPoint = widget.initialPoint);
      _mapController.move(widget.initialPoint!, 15);
      return;
    }
    try {
      final position = await LocationService.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _biasPoint = latLng);
      _mapController.move(latLng, 14);
    } catch (_) {
      // No bias point available — search still works, just unbiased.
    }
  }

  Future<void> _loadSavedPlaces() async {
    final result = await ApiService.getSavedPlaces();
    if (!mounted) return;
    if (result['success']) {
      setState(() => _savedPlaces = List<Map<String, dynamic>>.from(result['data']));
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() {
      if (trimmed.length < 3) {
        _suggestions = [];
        _isSearching = false;
        _searchError = null;
      }
    });
    if (trimmed.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    final myRequestId = ++_requestId;
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    final result = await ApiService.searchAddress(
      query: query,
      biasLat: _biasPoint?.latitude,
      biasLng: _biasPoint?.longitude,
    );
    if (!mounted || myRequestId != _requestId) return; // a newer query has since started
    setState(() {
      _isSearching = false;
      if (result['success']) {
        _suggestions = List<Map<String, dynamic>>.from(result['data']);
      } else {
        _suggestions = [];
        _searchError = result['error'] as String?;
      }
    });
  }

  void _selectResult(LatLng point, String address) {
    _debounce?.cancel();
    _searchController.clear();
    _focusNode.unfocus();
    setState(() {
      _point = point;
      _address = address;
      _suggestions = [];
      _searchError = null;
    });
    _mapController.move(point, 16);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocatingCurrent = true);
    try {
      final position = await LocationService.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      final address = await LocationService.addressFromCoordinates(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _biasPoint = point);
      _selectResult(point, address);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLocatingCurrent = false);
    }
  }

  Future<void> _onMapTap(TapPosition tapPosition, LatLng point) async {
    setState(() {
      _point = point;
      _address = 'Loading address…';
      _isReverseGeocoding = true;
    });
    final address = await LocationService.addressFromCoordinates(point.latitude, point.longitude);
    if (!mounted) return;
    setState(() {
      _address = address;
      _isReverseGeocoding = false;
    });
  }

  void _confirm() {
    if (_point == null) return;
    Navigator.pop(context, {'lat': _point!.latitude, 'lng': _point!.longitude, 'address': _address});
  }

  IconData _placeIcon(String label) {
    final l = label.toLowerCase();
    if (l == 'home') return Icons.home_outlined;
    if (l == 'work') return Icons.work_outline;
    return Icons.bookmark_border;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      onChanged: _onQueryChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: widget.title,
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _onQueryChanged('');
                                  setState(() {});
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _searchActive ? _buildResultsList() : _buildMapMode()),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    final query = _searchController.text.trim();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        ListTile(
          leading: _isLocatingCurrent
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, color: AppColors.primary),
          title: const Text('Use current location', style: AppTextStyles.body),
          onTap: _isLocatingCurrent ? null : _useCurrentLocation,
        ),
        const Divider(height: 1),
        if (query.length < 3) ...[
          if (_savedPlaces.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Saved places', style: AppTextStyles.helper),
            ),
            ..._savedPlaces.map((place) => ListTile(
                  leading: Icon(_placeIcon(place['label'] as String), color: AppColors.textSecondary),
                  title: Text(place['label'] as String, style: AppTextStyles.body),
                  subtitle: Text(place['address'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _selectResult(
                    LatLng((place['lat'] as num).toDouble(), (place['lng'] as num).toDouble()),
                    place['address'] as String,
                  ),
                )),
          ] else
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Text('Type at least 3 characters to search for an address', style: AppTextStyles.helper),
            ),
        ] else if (_isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_searchError != null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(_searchError!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
          )
        else if (_suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Text('No results for "$query"', style: AppTextStyles.helper),
          )
        else
          ..._suggestions.map((s) => ListTile(
                leading: const Icon(Icons.place_outlined, color: AppColors.textSecondary),
                title: Text(
                  s['display_name'] as String,
                  style: AppTextStyles.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _selectResult(
                  LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
                  s['display_name'] as String,
                ),
              )),
      ],
    );
  }

  Widget _buildMapMode() {
    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _point ?? _fallbackCenter,
              initialZoom: _point != null ? 15 : 12,
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
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, -2))],
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _isReverseGeocoding
                        ? const Text('Loading address…', style: AppTextStyles.body)
                        : Text(
                            _point == null ? 'Search above or tap the map to choose a location' : _address,
                            style: AppTextStyles.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primaryLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _point == null ? null : _confirm,
                  child: const Text(
                    'Confirm Location',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
