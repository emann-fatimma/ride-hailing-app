import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

// Used when the backend is unreachable, so the picker still works offline.
const _fallbackCountries = [
  {'name': 'Pakistan', 'iso_code': 'PK', 'phone_prefix': '+92'},
  {'name': 'Nigeria', 'iso_code': 'NG', 'phone_prefix': '+234'},
  {'name': 'India', 'iso_code': 'IN', 'phone_prefix': '+91'},
  {'name': 'United Arab Emirates', 'iso_code': 'AE', 'phone_prefix': '+971'},
  {'name': 'United Kingdom', 'iso_code': 'GB', 'phone_prefix': '+44'},
  {'name': 'United States', 'iso_code': 'US', 'phone_prefix': '+1'},
];

class CountryCodeField extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onChanged;

  const CountryCodeField({super.key, required this.onChanged});

  @override
  State<CountryCodeField> createState() => _CountryCodeFieldState();
}

class _CountryCodeFieldState extends State<CountryCodeField> {
  List<Map<String, dynamic>> _countries = [];
  Map<String, dynamic>? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    final fetched = await ApiService.getCountries();
    final countries = fetched.isNotEmpty ? fetched : _fallbackCountries;
    if (!mounted) return;
    setState(() {
      _countries = countries;
      _selected = countries.first;
      _loading = false;
    });
    widget.onChanged(_selected!);
  }

  void _openPicker() {
    if (_countries.isEmpty) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: _countries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final country = _countries[index];
              return ListTile(
                title: Text(country['name'] as String, style: AppTextStyles.body),
                trailing: Text(country['phone_prefix'] as String, style: AppTextStyles.label),
                onTap: () {
                  setState(() => _selected = country);
                  widget.onChanged(country);
                  Navigator.pop(context);
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : _openPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(_selected?['phone_prefix'] as String? ?? '+--', style: const TextStyle(color: AppColors.textPrimary)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
