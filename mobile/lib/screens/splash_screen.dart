import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/auth_state.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'driver_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final minSplash = Future.delayed(const Duration(seconds: 1));
    await AuthState.load();
    await minSplash;
    if (!mounted) return;
    final isDriver = AuthState.user?['role'] == 'driver';
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) {
          if (!AuthState.isLoggedIn) return const LoginScreen();
          return isDriver ? const DriverHomeScreen() : const HomeScreen();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_taxi, color: Colors.white, size: 64),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'RideEasy',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
