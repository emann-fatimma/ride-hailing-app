import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/auth_state.dart';
import 'driver_vehicle_screen.dart';
import 'emergency_contacts_screen.dart';
import 'saved_places_screen.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _user = AuthState.user;
    _load();
  }

  Future<void> _load() async {
    final result = await ApiService.getMe();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) _user = result['data'];
    });
  }

  Future<void> _logout() async {
    await AuthState.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => _EditProfileSheet(
        user: _user!,
        onSaved: (updated) => setState(() => _user = updated),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final isDriver = user?['role'] == 'driver';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('Profile', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
      ),
      body: _isLoading || user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          (user['name'] as String? ?? '?').trim().isNotEmpty
                              ? (user['name'] as String).trim()[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user['name'] as String? ?? '', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
                            const SizedBox(height: 2),
                            Text(user['phone'] as String? ?? '', style: AppTextStyles.helper),
                            Text(user['email'] as String? ?? '', style: AppTextStyles.helper),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                        onPressed: _openEditSheet,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (isDriver)
                  _MenuTile(
                    icon: Icons.directions_car_outlined,
                    label: 'My Vehicles',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const DriverVehicleScreen())),
                  ),
                _MenuTile(
                  icon: Icons.contact_emergency_outlined,
                  label: 'Emergency Contacts',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const EmergencyContactsScreen())),
                ),
                if (!isDriver)
                  _MenuTile(
                    icon: Icons.bookmark_border,
                    label: 'Saved Places',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SavedPlacesScreen())),
                  ),
                _MenuTile(
                  icon: Icons.lock_outline,
                  label: 'Change Password',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ChangePasswordScreen())),
                ),
                const SizedBox(height: AppSpacing.md),
                _MenuTile(
                  icon: Icons.logout,
                  label: 'Log Out',
                  color: AppColors.error,
                  onTap: _logout,
                ),
              ],
            ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final tileColor = color ?? AppColors.textPrimary;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: tileColor),
        title: Text(label, style: AppTextStyles.body.copyWith(color: tileColor, fontWeight: FontWeight.w600)),
        trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final ValueChanged<Map<String, dynamic>> onSaved;

  const _EditProfileSheet({required this.user, required this.onSaved});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameController;
  String? _gender;
  DateTime? _dob;
  bool _isSaving = false;
  String? _error;

  static const _genderOptions = ['male', 'female', 'other'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user['name'] as String? ?? '');
    _gender = widget.user['gender'] as String?;
    final dobRaw = widget.user['date_of_birth'] as String?;
    _dob = dobRaw != null ? DateTime.tryParse(dobRaw) : null;
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Name cannot be empty');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final result = await ApiService.updateProfile(
      name: _nameController.text.trim(),
      gender: _gender,
      dateOfBirth: _dob != null
          ? '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}'
          : null,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (result['success']) {
      await AuthState.set(AuthState.token!, result['data']);
      widget.onSaved(result['data']);
      if (!mounted) return;
      Navigator.pop(context);
    } else {
      setState(() => _error = result['error']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Edit Profile', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              items: _genderOptions.map((g) => DropdownMenuItem(value: g, child: Text(g[0].toUpperCase() + g.substring(1)))).toList(),
              onChanged: (value) => setState(() => _gender = value),
              decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: _pickDob,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date of birth', border: OutlineInputBorder()),
                child: Text(
                  _dob != null
                      ? '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}'
                      : 'Not set',
                ),
              ),
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
                    : const Text('Save Changes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
