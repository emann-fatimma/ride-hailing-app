import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../widgets/country_code_field.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _dialCode = '+92';
  String? _fullPhone;
  String? _devCode;
  bool _codeRequested = false;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _requestCode() async {
    if (_phoneController.text.trim().isEmpty) {
      setState(() => _error = 'Enter your phone number');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final fullPhone = '$_dialCode${_phoneController.text.trim()}';
    final result = await ApiService.forgotPassword(phone: fullPhone);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (result['success']) {
      setState(() {
        _fullPhone = fullPhone;
        _devCode = result['devCode'];
        _codeRequested = true;
      });
    } else {
      setState(() => _error = result['error']);
    }
  }

  Future<void> _resetPassword() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    if (_newPasswordController.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await ApiService.resetPassword(
      phone: _fullPhone,
      code: _codeController.text.trim(),
      newPassword: _newPasswordController.text,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success']) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset — log in with your new password'), backgroundColor: AppColors.success),
      );
    } else {
      setState(() => _error = result['error']);
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Reset Password', style: AppTextStyles.heading1),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _codeRequested
                    ? 'Enter the code sent to $_fullPhone and choose a new password'
                    : 'Enter your phone number and we\'ll send you a reset code',
                style: AppTextStyles.subtitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),

              if (!_codeRequested) ...[
                Row(
                  children: [
                    CountryCodeField(onChanged: (country) => setState(() => _dialCode = country['phone_prefix'] as String)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(hintText: 'Phone Number', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                if (_devCode != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      border: Border.all(color: const Color(0xFFF5C542)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'DEV MODE — no real SMS provider is wired up. Your reset code is: $_devCode',
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.heading1,
                  decoration: const InputDecoration(counterText: '', hintText: '000000', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm new password', border: OutlineInputBorder()),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
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
                  onPressed: _isSubmitting ? null : (_codeRequested ? _resetPassword : _requestCode),
                  child: _isSubmitting
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          _codeRequested ? 'Reset Password' : 'Send Reset Code',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
