import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'otp_verify_screen.dart';
import '../widgets/country_code_field.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _passwordError;
  String? _confirmError;
  String? _emailError;
  String? _generalError;
  String _dialCode = '+92';
  String _verifyChannel = 'phone';

  void _validateAndSubmit() async {
    setState(() {
      _passwordError = null;
      _confirmError = null;
      _emailError = null;
      _generalError = null;
    });

    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final email = _emailController.text.trim();

    bool hasError = false;
    if (password.length < 8) {
      setState(() => _passwordError = 'Must include letter, number and a character');
      hasError = true;
    }
    if (confirm != password) {
      setState(() => _confirmError = 'Must match with above password');
      hasError = true;
    }
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) {
      setState(() => _generalError = 'Please fill in all fields');
      hasError = true;
    }
    if (_verifyChannel == 'email' && !email.contains('@')) {
      setState(() => _emailError = 'Enter a valid email address');
      hasError = true;
    }
    if (hasError) return;

    setState(() => _isLoading = true);

    final fullPhone = '$_dialCode${_phoneController.text.trim()}';
    final result = await ApiService.signup(
      name: _nameController.text.trim(),
      phone: fullPhone,
      password: password,
      verifyChannel: _verifyChannel,
      email: _verifyChannel == 'email' ? email : null,
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      if (!mounted) return;
      final data = result['data'];
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OtpVerifyScreen(
            channel: data['verify_channel'],
            destination: data['destination'],
            devCode: data['dev_code'],
          ),
        ),
      );
    } else {
      setState(() => _generalError = result['error']);
    }
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
              Text('Let\'s Get Started', style: AppTextStyles.heading1),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Sign up to start enjoying stress-free rides',
                style: AppTextStyles.subtitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),

              // Name field
              _buildLabel('Your Name'),
              _buildTextField(
                controller: _nameController,
                hint: 'Full name',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: AppSpacing.md),

              // Phone field
              _buildLabel('Phone Number'),
              Row(
                children: [
                  CountryCodeField(
                    onChanged: (country) => setState(() => _dialCode = country['phone_prefix'] as String),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _buildTextField(
                      controller: _phoneController,
                      hint: 'Phone Number',
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Verification channel
              _buildLabel('Verify via'),
              Row(
                children: [
                  Expanded(child: _buildChannelChip('Phone', 'phone')),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _buildChannelChip('Email', 'email')),
                ],
              ),

              if (_verifyChannel == 'email') ...[
                const SizedBox(height: AppSpacing.md),
                _buildLabel('Email'),
                _buildTextField(
                  controller: _emailController,
                  hint: 'you@example.com',
                  icon: Icons.email_outlined,
                  hasError: _emailError != null,
                  keyboardType: TextInputType.emailAddress,
                ),
                if (_emailError != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_emailError!, style: AppTextStyles.errorText),
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.md),

              // Password field
              _buildLabel('Password'),
              _buildTextField(
                controller: _passwordController,
                hint: 'Input Password',
                icon: Icons.lock_outline,
                obscure: _obscurePassword,
                hasError: _passwordError != null,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppColors.textSecondary),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              if (_passwordError != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_passwordError!, style: AppTextStyles.errorText),
                ),
              ] else ...[
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Must include letter, number and a character', style: AppTextStyles.helper),
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              // Confirm password
              _buildLabel('Confirm Password'),
              _buildTextField(
                controller: _confirmController,
                hint: 'Re-enter Password',
                icon: Icons.lock_outline,
                obscure: _obscureConfirm,
                hasError: _confirmError != null,
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppColors.textSecondary),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              if (_confirmError != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_confirmError!, style: AppTextStyles.errorText),
                ),
              ] else ...[
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Must match with above password', style: AppTextStyles.helper),
                ),
              ],

              if (_generalError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_generalError!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
              ],

              const SizedBox(height: AppSpacing.xl),

              // Get Started button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primaryLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _validateAndSubmit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Get Started', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? ', style: AppTextStyles.body),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                      );
                    },
                    child: const Text('Log In', style: AppTextStyles.link),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelChip(String label, String value) {
    final selected = _verifyChannel == value;
    return GestureDetector(
      onTap: () => setState(() => _verifyChannel = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: AppTextStyles.label),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    bool obscure = false,
    bool hasError = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: icon != null ? Icon(icon, color: AppColors.textSecondary, size: 20) : null,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? AppColors.error : AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? AppColors.error : AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? AppColors.error : AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}