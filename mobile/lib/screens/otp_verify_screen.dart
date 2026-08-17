import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/auth_state.dart';
import 'home_screen.dart';

class OtpVerifyScreen extends StatefulWidget {
  final String channel; // 'phone' or 'email'
  final String destination;
  final String? devCode;

  const OtpVerifyScreen({
    super.key,
    required this.channel,
    required this.destination,
    this.devCode,
  });

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _codeController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String? _devCode;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _devCode = widget.devCode;
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown -= 1);
      }
    });
  }

  void _resend() async {
    final result = await ApiService.sendCode(
      channel: widget.channel,
      destination: widget.destination,
    );
    if (result['success']) {
      setState(() {
        _devCode = result['data']['dev_code'];
        _error = null;
      });
      _startCooldown();
    } else {
      setState(() => _error = result['error']);
    }
  }

  void _verify() async {
    setState(() => _error = null);

    if (_codeController.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }

    setState(() => _isLoading = true);
    final result = await ApiService.verifyCode(
      channel: widget.channel,
      destination: widget.destination,
      code: _codeController.text.trim(),
    );
    setState(() => _isLoading = false);

    if (!result['success']) {
      setState(() => _error = result['error']);
      return;
    }

    AuthState.set(result['data']['token'], result['data']['user']);
    if (!mounted) return;
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: AppSpacing.md),
              Text('Verify Your ${widget.channel == 'email' ? 'Email' : 'Number'}', style: AppTextStyles.heading1),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Enter the 6-digit code sent to ${widget.destination}',
                style: AppTextStyles.subtitle,
                textAlign: TextAlign.center,
              ),

              if (_devCode != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    border: Border.all(color: const Color(0xFFF5C542)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'DEV MODE — no real ${widget.channel == 'email' ? 'email' : 'SMS'} provider is wired up. '
                    'Your code is: $_devCode',
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.xl),

              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: AppTextStyles.heading1,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _error != null ? AppColors.error : AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _error != null ? AppColors.error : AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!, style: AppTextStyles.errorText),
                ),
              ],

              const SizedBox(height: AppSpacing.xl),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primaryLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _verify,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Verify', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              GestureDetector(
                onTap: _resendCooldown == 0 ? _resend : null,
                child: Text(
                  _resendCooldown == 0 ? 'Resend Code' : 'Resend Code (${_resendCooldown}s)',
                  style: _resendCooldown == 0
                      ? AppTextStyles.link
                      : const TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
