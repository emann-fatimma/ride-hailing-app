import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class DriverPayoutsScreen extends StatefulWidget {
  const DriverPayoutsScreen({super.key});

  @override
  State<DriverPayoutsScreen> createState() => _DriverPayoutsScreenState();
}

class _DriverPayoutsScreenState extends State<DriverPayoutsScreen> {
  List<Map<String, dynamic>> _payouts = [];
  bool _isLoading = true;
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
    final result = await ApiService.getPayouts();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) {
        _payouts = List<Map<String, dynamic>>.from(result['data']);
      } else {
        _error = result['error'];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('Payout History', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
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
                  if (_payouts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: Text('No payouts yet', style: AppTextStyles.body)),
                    )
                  else
                    ..._payouts.map((payout) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _PayoutCard(payout: payout),
                        )),
                ],
              ),
      ),
    );
  }
}

class _PayoutCard extends StatelessWidget {
  final Map<String, dynamic> payout;

  const _PayoutCard({required this.payout});

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return AppColors.success;
      case 'failed':
        return AppColors.error;
      default:
        return const Color(0xFFB45309);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'paid':
        return 'Paid';
      case 'failed':
        return 'Failed';
      case 'processing':
        return 'Processing';
      default:
        return 'Pending';
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '—';
    final date = DateTime.tryParse(isoDate);
    if (date == null) return '—';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final status = payout['status'] as String? ?? 'pending';
    final amount = double.tryParse(payout['amount']?.toString() ?? '') ?? 0;
    final currency = payout['currency'] as String? ?? 'PKR';
    final bankAccount = payout['driver_bank_account'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, color: _statusColor(status), size: 26),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$currency ${amount.toStringAsFixed(2)}', style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text(
                  bankAccount != null
                      ? '${bankAccount['bank_name']} ${bankAccount['account_number_masked']}'
                      : 'Requested ${_formatDate(payout['initiated_at'] as String?)}',
                  style: AppTextStyles.helper,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_statusLabel(status), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(status))),
          ),
        ],
      ),
    );
  }
}
