import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class DriverVehicleScreen extends StatefulWidget {
  const DriverVehicleScreen({super.key});

  @override
  State<DriverVehicleScreen> createState() => _DriverVehicleScreenState();
}

class _DriverVehicleScreenState extends State<DriverVehicleScreen> {
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _vehicleTypes = [];
  bool _isLoading = true;
  String? _error;
  String? _activatingId;

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
    final results = await Future.wait([ApiService.getMyVehicles(), ApiService.getVehicleTypes()]);
    if (!mounted) return;
    final vehiclesResult = results[0];
    final typesResult = results[1];
    setState(() {
      _isLoading = false;
      if (vehiclesResult['success']) {
        _vehicles = List<Map<String, dynamic>>.from(vehiclesResult['data']);
      } else {
        _error = vehiclesResult['error'];
      }
      if (typesResult['success']) {
        _vehicleTypes = List<Map<String, dynamic>>.from(typesResult['data']);
      }
    });
  }

  Future<void> _activate(String vehicleId) async {
    setState(() => _activatingId = vehicleId);
    final result = await ApiService.activateVehicle(vehicleId);
    if (!mounted) return;
    setState(() => _activatingId = null);
    if (result['success']) {
      _load();
    } else {
      setState(() => _error = result['error']);
    }
  }

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _AddVehicleSheet(
        vehicleTypes: _vehicleTypes,
        onAdded: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('My Vehicles', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Vehicle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                  if (_vehicles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: Text('No vehicles yet — add one to start driving', style: AppTextStyles.body)),
                    )
                  else
                    ..._vehicles.map((vehicle) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _VehicleCard(
                            vehicle: vehicle,
                            isActivating: _activatingId == vehicle['id'],
                            onActivate: () => _activate(vehicle['id'] as String),
                          ),
                        )),
                  const SizedBox(height: 72),
                ],
              ),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  final bool isActivating;
  final VoidCallback onActivate;

  const _VehicleCard({required this.vehicle, required this.isActivating, required this.onActivate});

  @override
  Widget build(BuildContext context) {
    final isActive = vehicle['is_active'] == true;
    final vehicleType = vehicle['vehicle_type'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: isActive ? AppColors.primary : AppColors.border, width: isActive ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_car, color: isActive ? AppColors.primary : AppColors.textSecondary, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vehicle['make_model'] as String, style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text(
                  [vehicle['plate'], vehicleType?['name'], vehicle['color']]
                      .where((s) => s != null && (s as String).isNotEmpty)
                      .join(' · '),
                  style: AppTextStyles.helper,
                ),
              ],
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
            )
          else
            TextButton(
              onPressed: isActivating ? null : onActivate,
              child: isActivating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Set Active', style: AppTextStyles.link),
            ),
        ],
      ),
    );
  }
}

class _AddVehicleSheet extends StatefulWidget {
  final List<Map<String, dynamic>> vehicleTypes;
  final VoidCallback onAdded;

  const _AddVehicleSheet({required this.vehicleTypes, required this.onAdded});

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  final _plateController = TextEditingController();
  final _makeModelController = TextEditingController();
  final _colorController = TextEditingController();
  final _yearController = TextEditingController();
  String? _selectedTypeId;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedTypeId = widget.vehicleTypes.isNotEmpty ? widget.vehicleTypes.first['id'] as String : null;
  }

  Future<void> _submit() async {
    if (_plateController.text.trim().isEmpty || _makeModelController.text.trim().isEmpty || _selectedTypeId == null) {
      setState(() => _error = 'Plate, make/model, and vehicle type are required');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await ApiService.registerVehicle(
      vehicleTypeId: _selectedTypeId!,
      plate: _plateController.text.trim(),
      makeModel: _makeModelController.text.trim(),
      color: _colorController.text.trim(),
      year: int.tryParse(_yearController.text.trim()),
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (result['success']) {
      widget.onAdded();
      Navigator.pop(context);
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
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add Vehicle', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
            const SizedBox(height: AppSpacing.md),
            if (widget.vehicleTypes.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedTypeId,
                items: widget.vehicleTypes
                    .map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['name'] as String)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedTypeId = value),
                decoration: const InputDecoration(labelText: 'Vehicle type', border: OutlineInputBorder()),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextField(
              controller: _plateController,
              decoration: const InputDecoration(labelText: 'Plate number', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _makeModelController,
              decoration: const InputDecoration(labelText: 'Make & model', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _colorController,
                    decoration: const InputDecoration(labelText: 'Color', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
                  ),
                ),
              ],
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
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Vehicle', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
