import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  List<Map<String, dynamic>> _contacts = [];
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
    final result = await ApiService.getEmergencyContacts();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) {
        _contacts = List<Map<String, dynamic>>.from(result['data']);
      } else {
        _error = result['error'];
      }
    });
  }

  Future<void> _delete(String contactId) async {
    setState(() => _deletingId = contactId);
    final result = await ApiService.deleteEmergencyContact(contactId);
    if (!mounted) return;
    setState(() => _deletingId = null);
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
      builder: (context) => _AddContactSheet(onAdded: _load),
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
        title: Text('Emergency Contacts', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  const Text(
                    "These are the people we text — along with our safety team — the moment you press "
                    "the SOS button during a ride.",
                    style: AppTextStyles.helper,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_error != null) ...[
                    Text(_error!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (_contacts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(child: Text('No emergency contacts yet', style: AppTextStyles.body)),
                    )
                  else
                    ..._contacts.map((contact) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _ContactCard(
                            contact: contact,
                            isDeleting: _deletingId == contact['id'],
                            onDelete: () => _delete(contact['id'] as String),
                          ),
                        )),
                  const SizedBox(height: 72),
                ],
              ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Map<String, dynamic> contact;
  final bool isDeleting;
  final VoidCallback onDelete;

  const _ContactCard({required this.contact, required this.isDeleting, required this.onDelete});

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
          const Icon(Icons.person_outline, color: AppColors.textSecondary, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact['name'] as String, style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text(
                  [contact['phone'], contact['relation']]
                      .where((s) => s != null && (s as String).isNotEmpty)
                      .join(' · '),
                  style: AppTextStyles.helper,
                ),
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

class _AddContactSheet extends StatefulWidget {
  final VoidCallback onAdded;

  const _AddContactSheet({required this.onAdded});

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) {
      setState(() => _error = 'Name and phone are required');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await ApiService.addEmergencyContact(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      relation: _relationController.text.trim(),
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
            Text('Add Emergency Contact', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _relationController,
              decoration: const InputDecoration(labelText: 'Relation (optional)', border: OutlineInputBorder()),
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
                    : const Text('Save Contact', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
