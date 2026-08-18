import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import 'location_picker_screen.dart';

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
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (context) => const LocationPickerScreen(title: 'Choose a location')),
    );
    if (picked == null || !mounted) return;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => _LabelPlaceSheet(picked: picked),
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

// Bottom sheet shown after picking a location — just the label + save step,
// since LocationPickerScreen now owns the search/map picking itself.
class _LabelPlaceSheet extends StatefulWidget {
  final Map<String, dynamic> picked; // {'lat','lng','address'}

  const _LabelPlaceSheet({required this.picked});

  @override
  State<_LabelPlaceSheet> createState() => _LabelPlaceSheetState();
}

class _LabelPlaceSheetState extends State<_LabelPlaceSheet> {
  final _labelController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  Future<void> _save() async {
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
      address: widget.picked['address'] as String,
      lat: widget.picked['lat'] as double,
      lng: widget.picked['lng'] as double,
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Save this place', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.picked['address'] as String,
            style: AppTextStyles.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _labelController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Label (e.g. Home, Work)', border: OutlineInputBorder()),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: AppTextStyles.errorText),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
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
    );
  }
}
