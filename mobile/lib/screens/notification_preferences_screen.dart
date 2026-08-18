import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  List<Map<String, dynamic>> _preferences = [];
  bool _isLoading = true;
  String? _savingKey;
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
    final result = await ApiService.getNotificationPreferences();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) {
        _preferences = result['data'];
      } else {
        _error = result['error'];
      }
    });
  }

  Future<void> _toggle(Map<String, dynamic> preference, bool value) async {
    final key = '${preference['channel']}:${preference['category']}';
    setState(() {
      _savingKey = key;
      preference['enabled'] = value;
    });
    final result = await ApiService.updateNotificationPreferences([
      {'channel': preference['channel'], 'category': preference['category'], 'enabled': value},
    ]);
    if (!mounted) return;
    setState(() => _savingKey = null);
    if (!result['success']) {
      setState(() {
        preference['enabled'] = !value;
        _error = result['error'];
      });
    }
  }

  String _channelLabel(String channel) => channel == 'sms' ? 'Text message' : 'Email';
  String _channelDescription(String channel) => channel == 'sms'
      ? 'Get a text for ride updates, in addition to the in-app notification.'
      : 'Get an email for ride updates, in addition to the in-app notification.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('Notification Settings', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const Text(
                  "You'll always see ride and delivery updates in your notification inbox. "
                  'These settings only control extra pings on top of that.',
                  style: AppTextStyles.helper,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_error != null) ...[
                  Text(_error!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.md),
                ],
                ..._preferences.map((preference) {
                  final key = '${preference['channel']}:${preference['category']}';
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_channelLabel(preference['channel'] as String), style: AppTextStyles.label),
                              const SizedBox(height: 2),
                              Text(_channelDescription(preference['channel'] as String), style: AppTextStyles.helper),
                            ],
                          ),
                        ),
                        _savingKey == key
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Switch(
                                value: preference['enabled'] as bool,
                                activeThumbColor: AppColors.primary,
                                onChanged: (value) => _toggle(preference, value),
                              ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
