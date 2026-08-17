import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class RateRideScreen extends StatefulWidget {
  final String rideId;

  const RateRideScreen({super.key, required this.rideId});

  @override
  State<RateRideScreen> createState() => _RateRideScreenState();
}

class _RateRideScreenState extends State<RateRideScreen> {
  final _commentController = TextEditingController();
  int _stars = 5;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await ApiService.rateRide(
      widget.rideId,
      stars: _stars,
      comment: _commentController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (result['success']) {
      _goHome();
    } else {
      setState(() => _error = result['error']);
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 56),
              const SizedBox(height: AppSpacing.md),
              Text('Trip Completed', style: AppTextStyles.heading1),
              const SizedBox(height: AppSpacing.xs),
              const Text('How was your ride?', style: AppTextStyles.subtitle),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starValue = index + 1;
                  return IconButton(
                    iconSize: 36,
                    icon: Icon(
                      starValue <= _stars ? Icons.star : Icons.star_border,
                      color: const Color(0xFFF5C542),
                    ),
                    onPressed: () => setState(() => _stars = starValue),
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Leave a comment (optional)',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Submit Rating', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _isSubmitting ? null : _goHome,
                child: const Text('Skip', style: AppTextStyles.link),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
