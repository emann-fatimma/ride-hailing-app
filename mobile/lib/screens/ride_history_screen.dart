import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/api_service.dart';
import 'ride_status_screen.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  List<Map<String, dynamic>> _rides = [];
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
    final result = await ApiService.getMyRides();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) {
        _rides = List<Map<String, dynamic>>.from(result['data']);
      } else {
        _error = result['error'];
      }
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'in_progress':
      case 'matched':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('My Rides', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(child: Text(_error!, style: AppTextStyles.errorText)),
                    ],
                  )
                : _rides.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          Center(child: Text('No rides yet', style: AppTextStyles.body)),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: _rides.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final ride = _rides[index];
                          final status = ride['status'] as String;
                          final requestedAt = DateTime.tryParse(ride['requested_at'] as String? ?? '');
                          return InkWell(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => RideStatusScreen(rideId: ride['id'] as String)),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        requestedAt != null ? DateFormat('MMM d, h:mm a').format(requestedAt.toLocal()) : '',
                                        style: AppTextStyles.helper,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _statusColor(status).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          status.replaceAll('_', ' '),
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(status)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.my_location, size: 14, color: AppColors.success),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(ride['pickup_address'] as String, style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on, size: 14, color: AppColors.error),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(ride['dropoff_address'] as String, style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                  if (ride['total_fare'] != null) ...[
                                    const SizedBox(height: 6),
                                    Text('PKR ${ride['total_fare']}', style: AppTextStyles.label),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
