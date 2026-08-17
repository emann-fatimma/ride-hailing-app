import 'package:flutter/material.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 64),
            const SizedBox(height: AppSpacing.md),
            Text('You\'re in!', style: AppTextStyles.heading1),
            const SizedBox(height: AppSpacing.sm),
            const Text('Home screen coming next.', style: AppTextStyles.body),
          ],
        ),
      ),
    );
  }
}