import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class DriverIncentivesScreen extends StatefulWidget {
  const DriverIncentivesScreen({super.key});

  @override
  State<DriverIncentivesScreen> createState() => _DriverIncentivesScreenState();
}

class _DriverIncentivesScreenState extends State<DriverIncentivesScreen> {
  List<Map<String, dynamic>> _incentives = [];
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
    final result = await ApiService.getIncentives();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) {
        _incentives = List<Map<String, dynamic>>.from(result['data']);
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
        title: Text('Incentives', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
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
                  if (_incentives.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: Text('No active incentive programs right now', style: AppTextStyles.body)),
                    )
                  else
                    ..._incentives.map((incentive) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _IncentiveCard(incentive: incentive),
                        )),
                ],
              ),
      ),
    );
  }
}

class _IncentiveCard extends StatelessWidget {
  final Map<String, dynamic> incentive;

  const _IncentiveCard({required this.incentive});

  @override
  Widget build(BuildContext context) {
    final program = incentive['program'] as Map<String, dynamic>;
    final progress = incentive['progress'] as Map<String, dynamic>;
    final targetRides = program['target_rides'] as int?;
    final progressRides = progress['progress_rides'] as int? ?? 0;
    final status = progress['status'] as String? ?? 'active';
    final isCompleted = status == 'completed';
    final bonusAmount = double.tryParse(program['bonus_amount']?.toString() ?? '') ?? 0;
    final ratio = (targetRides != null && targetRides > 0) ? (progressRides / targetRides).clamp(0.0, 1.0) : 0.0;
    final endsOn = DateTime.tryParse(program['ends_on']?.toString() ?? '');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: isCompleted ? AppColors.success : AppColors.border, width: isCompleted ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: isCompleted ? AppColors.success : const Color(0xFFF5C542), size: 24),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(program['name'] as String, style: AppTextStyles.label)),
              Text(
                'PKR ${bonusAmount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 15),
              ),
            ],
          ),
          if ((program['description'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(program['description'] as String, style: AppTextStyles.helper),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (targetRides != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: isCompleted ? AppColors.success : AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isCompleted ? 'Bonus unlocked · $progressRides/$targetRides rides' : '$progressRides of $targetRides rides',
              style: AppTextStyles.helper,
            ),
          ],
          if (endsOn != null) ...[
            const SizedBox(height: 4),
            Text(
              'Ends ${endsOn.year}-${endsOn.month.toString().padLeft(2, '0')}-${endsOn.day.toString().padLeft(2, '0')}',
              style: AppTextStyles.helper,
            ),
          ],
        ],
      ),
    );
  }
}
