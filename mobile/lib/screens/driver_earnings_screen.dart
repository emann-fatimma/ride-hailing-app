import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import 'driver_bank_accounts_screen.dart';
import 'driver_payouts_screen.dart';
import 'driver_incentives_screen.dart';
import 'driver_documents_screen.dart';

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  Map<String, dynamic>? _driver;
  String? _kycStatus;
  bool _hasVerifiedBankAccount = false;
  bool _isLoading = true;
  bool _isRequestingPayout = false;
  String? _error;

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
    final results = await Future.wait([
      ApiService.getMe(),
      ApiService.getBankAccounts(),
      ApiService.getDriverDocuments(),
    ]);
    if (!mounted) return;
    final meResult = results[0];
    final bankResult = results[1];
    final docsResult = results[2];
    setState(() {
      _isLoading = false;
      if (meResult['success']) {
        _driver = (meResult['data'] as Map<String, dynamic>)['driver'] as Map<String, dynamic>?;
      } else {
        _error = meResult['error'];
      }
      if (bankResult['success']) {
        final accounts = List<Map<String, dynamic>>.from(bankResult['data']);
        _hasVerifiedBankAccount = accounts.any((a) => a['status'] == 'verified');
      }
      if (docsResult['success']) {
        _kycStatus = docsResult['kycStatus'] as String?;
      }
    });
  }

  double _num(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _requestPayout() async {
    final balance = _num(_driver?['current_balance']);
    if (balance <= 0) return;

    if (!_hasVerifiedBankAccount) {
      final goToBank = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No verified bank account'),
          content: const Text('Add and get a bank account verified before requesting a payout.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add Bank Account')),
          ],
        ),
      );
      if (goToBank == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (context) => const DriverBankAccountsScreen()));
        _load();
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Payout'),
        content: Text('Request a payout of PKR ${balance.toStringAsFixed(2)} to your default bank account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRequestingPayout = true);
    final result = await ApiService.requestPayout();
    if (!mounted) return;
    setState(() => _isRequestingPayout = false);
    if (result['success']) {
      _load();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => const DriverPayoutsScreen()));
    } else {
      setState(() => _error = result['error']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = _num(_driver?['current_balance']);
    final lifetimeEarnings = _num(_driver?['lifetime_earnings']);
    final totalRides = _driver?['total_rides'] ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('Earnings', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Available balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          'PKR ${balance.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Lifetime earnings', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                Text('PKR ${lifetimeEarnings.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Total rides', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                Text('$totalRides', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: (balance > 0 && !_isRequestingPayout) ? _requestPayout : null,
                            child: _isRequestingPayout
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(
                                    balance > 0 ? 'Request Payout' : 'No balance to pay out',
                                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _EarningsMenuTile(
                    icon: Icons.account_balance_outlined,
                    label: 'Bank Accounts',
                    trailing: _hasVerifiedBankAccount ? null : 'Setup needed',
                    trailingColor: AppColors.error,
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (context) => const DriverBankAccountsScreen()))
                        .then((_) => _load()),
                  ),
                  _EarningsMenuTile(
                    icon: Icons.history,
                    label: 'Payout History',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const DriverPayoutsScreen())),
                  ),
                  _EarningsMenuTile(
                    icon: Icons.emoji_events_outlined,
                    label: 'Incentives',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const DriverIncentivesScreen())),
                  ),
                  _EarningsMenuTile(
                    icon: Icons.badge_outlined,
                    label: 'KYC Documents',
                    trailing: _kycStatusLabel(_kycStatus),
                    trailingColor: _kycStatusColor(_kycStatus),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (context) => const DriverDocumentsScreen()))
                        .then((_) => _load()),
                  ),
                ],
              ),
            ),
    );
  }
}

String? _kycStatusLabel(String? status) {
  switch (status) {
    case 'approved':
      return 'Verified';
    case 'in_review':
      return 'In review';
    case 'rejected':
      return 'Action needed';
    case 'pending':
      return 'Pending';
    default:
      return 'Not started';
  }
}

Color _kycStatusColor(String? status) {
  switch (status) {
    case 'approved':
      return AppColors.success;
    case 'rejected':
      return AppColors.error;
    default:
      return const Color(0xFFB45309);
  }
}

class _EarningsMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final Color? trailingColor;
  final VoidCallback onTap;

  const _EarningsMenuTile({required this.icon, required this.label, required this.onTap, this.trailing, this.trailingColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.textPrimary),
        title: Text(label, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null) ...[
              Text(trailing!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: trailingColor ?? AppColors.textSecondary)),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
