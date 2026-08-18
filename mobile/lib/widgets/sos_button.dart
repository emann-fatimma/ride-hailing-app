import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

// A confirm-then-trigger SOS control, shared by the rider and driver
// active-ride screens. `rideId` ties the event to the current trip when given.
class SosButton extends StatefulWidget {
  final String? rideId;
  final double? lat;
  final double? lng;

  const SosButton({super.key, this.rideId, this.lat, this.lng});

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> {
  bool _isSending = false;

  Future<void> _confirmAndTrigger() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trigger SOS?'),
        content: const Text(
          'This alerts our safety team with your location and trip details. '
          'For an immediate threat to life, call local emergency services first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trigger SOS', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);
    final result = await ApiService.triggerSos(rideId: widget.rideId, lat: widget.lat, lng: widget.lng);
    if (!mounted) return;
    setState(() => _isSending = false);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success']
              ? 'SOS sent — our safety team has been notified'
              : (result['error'] ?? 'Could not send SOS. Try again.'),
        ),
        backgroundColor: result['success'] ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.white,
      child: _isSending
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
          : IconButton(
              icon: const Icon(Icons.warning_amber_rounded, color: AppColors.error),
              tooltip: 'SOS',
              onPressed: _confirmAndTrigger,
            ),
    );
  }
}
