import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class DriverBankAccountsScreen extends StatefulWidget {
  const DriverBankAccountsScreen({super.key});

  @override
  State<DriverBankAccountsScreen> createState() => _DriverBankAccountsScreenState();
}

class _DriverBankAccountsScreenState extends State<DriverBankAccountsScreen> {
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _countries = [];
  bool _isLoading = true;
  String? _error;
  String? _busyAccountId;

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
    final accountsResult = await ApiService.getBankAccounts();
    final countries = await ApiService.getCountries();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (accountsResult['success']) {
        _accounts = List<Map<String, dynamic>>.from(accountsResult['data']);
      } else {
        _error = accountsResult['error'];
      }
      _countries = countries;
    });
  }

  Future<void> _setDefault(String accountId) async {
    setState(() => _busyAccountId = accountId);
    final result = await ApiService.setDefaultBankAccount(accountId);
    if (!mounted) return;
    setState(() => _busyAccountId = null);
    if (result['success']) {
      _load();
    } else {
      setState(() => _error = result['error']);
    }
  }

  Future<void> _delete(String accountId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove bank account?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyAccountId = accountId);
    final result = await ApiService.deleteBankAccount(accountId);
    if (!mounted) return;
    setState(() => _busyAccountId = null);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => _AddBankAccountSheet(countries: _countries, onAdded: _load),
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
        title: Text('Bank Accounts', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                  if (_accounts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: Text('No bank accounts yet — add one to receive payouts', style: AppTextStyles.body)),
                    )
                  else
                    ..._accounts.map((account) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _BankAccountCard(
                            account: account,
                            isBusy: _busyAccountId == account['id'],
                            onSetDefault: () => _setDefault(account['id'] as String),
                            onDelete: () => _delete(account['id'] as String),
                          ),
                        )),
                  const SizedBox(height: 72),
                ],
              ),
      ),
    );
  }
}

class _BankAccountCard extends StatelessWidget {
  final Map<String, dynamic> account;
  final bool isBusy;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  const _BankAccountCard({required this.account, required this.isBusy, required this.onSetDefault, required this.onDelete});

  Color _statusColor(String status) {
    switch (status) {
      case 'verified':
        return AppColors.success;
      case 'rejected':
      case 'suspended':
        return AppColors.error;
      default:
        return const Color(0xFFB45309);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'verified':
        return 'Verified';
      case 'rejected':
        return 'Rejected';
      case 'suspended':
        return 'Suspended';
      default:
        return 'Pending verification';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDefault = account['is_default'] == true;
    final status = account['status'] as String? ?? 'pending_verification';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: isDefault ? AppColors.primary : AppColors.border, width: isDefault ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance, color: isDefault ? AppColors.primary : AppColors.textSecondary, size: 26),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account['bank_name'] as String, style: AppTextStyles.label),
                    const SizedBox(height: 2),
                    Text(
                      '${account['account_holder_name']} · ${account['account_number_masked']}',
                      style: AppTextStyles.helper,
                    ),
                  ],
                ),
              ),
              if (isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Default', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_statusLabel(status), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(status))),
              if (isBusy)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Row(
                  children: [
                    if (!isDefault)
                      TextButton(onPressed: onSetDefault, child: const Text('Set Default', style: AppTextStyles.link)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                      onPressed: onDelete,
                      tooltip: 'Remove',
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddBankAccountSheet extends StatefulWidget {
  final List<Map<String, dynamic>> countries;
  final VoidCallback onAdded;

  const _AddBankAccountSheet({required this.countries, required this.onAdded});

  @override
  State<_AddBankAccountSheet> createState() => _AddBankAccountSheetState();
}

class _AddBankAccountSheetState extends State<_AddBankAccountSheet> {
  final _holderController = TextEditingController();
  final _bankController = TextEditingController();
  final _accountNumberController = TextEditingController();
  String? _selectedCountryId;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedCountryId = widget.countries.isNotEmpty ? widget.countries.first['id'] as String : null;
  }

  @override
  void dispose() {
    _holderController.dispose();
    _bankController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final accountNumber = _accountNumberController.text.trim();
    if (_holderController.text.trim().isEmpty ||
        _bankController.text.trim().isEmpty ||
        accountNumber.replaceAll(RegExp(r'\D'), '').length < 4 ||
        _selectedCountryId == null) {
      setState(() => _error = 'Account holder name, bank name, a valid account number, and country are required');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await ApiService.addBankAccount(
      accountHolderName: _holderController.text.trim(),
      bankName: _bankController.text.trim(),
      accountNumber: accountNumber,
      countryId: _selectedCountryId!,
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
            Text('Add Bank Account', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
            const SizedBox(height: AppSpacing.md),
            if (widget.countries.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedCountryId,
                items: widget.countries
                    .map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] as String)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedCountryId = value),
                decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextField(
              controller: _holderController,
              decoration: const InputDecoration(labelText: 'Account holder name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _bankController,
              decoration: const InputDecoration(labelText: 'Bank name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _accountNumberController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Account number', border: OutlineInputBorder()),
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
                    : const Text('Save Bank Account', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
