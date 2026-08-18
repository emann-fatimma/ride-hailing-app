import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
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
    final result = await ApiService.getNotifications();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) {
        _notifications = result['notifications'];
      } else {
        _error = result['error'];
      }
    });
  }

  Future<void> _markRead(Map<String, dynamic> notification) async {
    if (notification['read_at'] != null) return;
    setState(() => notification['read_at'] = DateTime.now().toIso8601String());
    final result = await ApiService.markNotificationRead(notification['id'] as String);
    if (!mounted) return;
    if (!result['success']) {
      setState(() => notification['read_at'] = null);
    }
  }

  String _relativeTime(String? isoTimestamp) {
    if (isoTimestamp == null) return '';
    final sentAt = DateTime.tryParse(isoTimestamp)?.toLocal();
    if (sentAt == null) return '';
    final diff = DateTime.now().difference(sentAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('Notifications', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
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
                  if (_notifications.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: Text('No notifications yet', style: AppTextStyles.body)),
                    )
                  else
                    ..._notifications.map((notification) => _NotificationTile(
                          notification: notification,
                          relativeTime: _relativeTime(notification['sent_at'] as String?),
                          onTap: () => _markRead(notification),
                        )),
                ],
              ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  final String relativeTime;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.relativeTime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUnread = notification['read_at'] == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isUnread ? const Color(0xFFF3F4FF) : Colors.white,
          border: Border.all(color: isUnread ? AppColors.primary.withValues(alpha: 0.25) : AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isUnread ? AppColors.primary : Colors.transparent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification['title'] as String? ?? '',
                    style: AppTextStyles.label.copyWith(fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(notification['body'] as String? ?? '', style: AppTextStyles.body),
                  const SizedBox(height: 4),
                  Text(relativeTime, style: AppTextStyles.helper),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
