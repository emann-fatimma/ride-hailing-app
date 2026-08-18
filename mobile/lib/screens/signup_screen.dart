import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/auth_state.dart';
import 'login_screen.dart';
import 'otp_verify_screen.dart';
import 'driver_home_screen.dart';
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
  final _licenseNumberController = TextEditingController();

  final _ec1NameController = TextEditingController();
  final _ec1PhoneController = TextEditingController();
  final _ec1RelationController = TextEditingController();
  final _ec2NameController = TextEditingController();
  final _ec2PhoneController = TextEditingController();
  final _ec2RelationController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _passwordError;
  String? _confirmError;
  String? _emailError;
  String? _licenseError;
  String? _emergencyContactsError;
  String? _generalError;
  String _dialCode = '+92';
  String _verifyChannel = 'phone';
  String _role = 'rider'; // 'rider' or 'driver'
  DateTime? _licenseExpiry;

  Future<void> _pickLicenseExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year + 1, now.month, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 15),
    );
    if (picked != null) setState(() => _licenseExpiry = picked);
  }

  void _validateAndSubmit() async {
    setState(() {
      _passwordError = null;
      _confirmError = null;
      _emailError = null;
      _licenseError = null;
      _emergencyContactsError = null;
      _generalError = null;
    });

    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final email = _emailController.text.trim();
    final isDriver = _role == 'driver';

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
    if ((isDriver || _verifyChannel == 'email') && !email.contains('@')) {
      setState(() => _emailError = 'Enter a valid email address');
      hasError = true;
    }
    if (isDriver) {
      if (_licenseNumberController.text.trim().isEmpty) {
        setState(() => _licenseError = 'License number is required');
        hasError = true;
      }
      if (_licenseExpiry == null) {
        setState(() => _licenseError = 'Select a license expiry date');
        hasError = true;
      }
    } else {
      if (_ec1NameController.text.trim().isEmpty ||
          _ec1PhoneController.text.trim().isEmpty ||
          _ec2NameController.text.trim().isEmpty ||
          _ec2PhoneController.text.trim().isEmpty) {
        setState(() => _emergencyContactsError = 'Both emergency contacts are required');
        hasError = true;
      }
    }
    if (hasError) return;

    setState(() => _isLoading = true);

    final fullPhone = '$_dialCode${_phoneController.text.trim()}';

    if (isDriver) {
      final expiry = _licenseExpiry!;
      final expiryStr = '${expiry.year.toString().padLeft(4, '0')}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}';
      final result = await ApiService.signupDriver(
        name: _nameController.text.trim(),
        phone: fullPhone,
        email: email,
        password: password,
        licenseNumber: _licenseNumberController.text.trim(),
        licenseExpiry: expiryStr,
      );

      if (!result['success']) {
        setState(() {
          _isLoading = false;
          _generalError = result['error'];
        });
        return;
      }

      final loginResult = await ApiService.login(phone: fullPhone, password: password);
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (loginResult['success']) {
        await AuthState.set(loginResult['data']['token'], loginResult['data']['user']);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const DriverHomeScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
      return;
    }

    final result = await ApiService.signup(
      name: _nameController.text.trim(),
      phone: fullPhone,
      password: password,
      verifyChannel: _verifyChannel,
      email: _verifyChannel == 'email' ? email : null,
      emergencyContacts: [
        {
          'name': _ec1NameController.text.trim(),
          'phone': _ec1PhoneController.text.trim(),
          'relation': _ec1RelationController.text.trim(),
        },
        {
          'name': _ec2NameController.text.trim(),
          'phone': _ec2PhoneController.text.trim(),
          'relation': _ec2RelationController.text.trim(),
        },
      ],
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
    final isDriver = _role == 'driver';

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
              const SizedBox(height: AppSpacing.lg),

              // Role toggle
              Row(
                children: [
                  Expanded(child: _buildRoleChip('I\'m a Rider', 'rider')),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _buildRoleChip('I\'m a Driver', 'driver')),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

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

              if (isDriver) ...[
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
                const SizedBox(height: AppSpacing.md),

                _buildLabel('License Number'),
                _buildTextField(
                  controller: _licenseNumberController,
                  hint: 'Driving license number',
                  icon: Icons.badge_outlined,
                  hasError: _licenseError != null,
                ),
                const SizedBox(height: AppSpacing.md),

                _buildLabel('License Expiry'),
                GestureDetector(
                  onTap: _pickLicenseExpiry,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: _licenseError != null ? AppColors.error : AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, color: AppColors.textSecondary, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          _licenseExpiry == null
                              ? 'Select date'
                              : '${_licenseExpiry!.year}-${_licenseExpiry!.month.toString().padLeft(2, '0')}-${_licenseExpiry!.day.toString().padLeft(2, '0')}',
                          style: _licenseExpiry == null
                              ? const TextStyle(color: AppColors.textSecondary)
                              : AppTextStyles.body,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_licenseError != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_licenseError!, style: AppTextStyles.errorText),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
              ] else ...[
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

                // Emergency contacts — required so the SOS button has someone to alert
                _buildLabel('Emergency Contacts'),
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    "We'll text these two people (and our safety team) if you ever press the SOS button during a ride.",
                    style: AppTextStyles.helper,
                  ),
                ),
                _buildEmergencyContactFields(
                  label: 'Contact 1',
                  nameController: _ec1NameController,
                  phoneController: _ec1PhoneController,
                  relationController: _ec1RelationController,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildEmergencyContactFields(
                  label: 'Contact 2',
                  nameController: _ec2NameController,
                  phoneController: _ec2PhoneController,
                  relationController: _ec2RelationController,
                ),
                if (_emergencyContactsError != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_emergencyContactsError!, style: AppTextStyles.errorText),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
              ],

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

              // Submit button
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
                      : Text(
                          isDriver ? 'Create Driver Account' : 'Get Started',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
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

  Widget _buildRoleChip(String label, String value) {
    final selected = _role == value;
    return GestureDetector(
      onTap: () => setState(() => _role = value),
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

  Widget _buildEmergencyContactFields({
    required String label,
    required TextEditingController nameController,
    required TextEditingController phoneController,
    required TextEditingController relationController,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: AppTextStyles.label),
          const SizedBox(height: AppSpacing.sm),
          _buildTextField(controller: nameController, hint: 'Name', icon: Icons.person_outline),
          const SizedBox(height: AppSpacing.sm),
          _buildTextField(
            controller: phoneController,
            hint: 'Phone Number',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildTextField(controller: relationController, hint: 'Relation (optional)', icon: Icons.people_outline),
        ],
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
