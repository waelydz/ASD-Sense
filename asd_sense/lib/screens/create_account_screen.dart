import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/google_sign_in_button.dart';
import 'main_shell.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;

  bool get _showConfirm => _passwordController.text.isNotEmpty;
  bool get _mismatch =>
      _confirmController.text.isNotEmpty &&
      _confirmController.text != _passwordController.text;

  Future<void> _createAccount() async {
    if (_loading) return;
    if (_nameController.text.trim().isEmpty || _emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name and email address.')),
      );
      return;
    }
    if (_passwordController.text.length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 12 characters.')),
      );
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await AppData.instance.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException
            ? e.message : 'Unable to create account. Check backend connectivity.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: AppIconButton(
                  icon: Icons.arrow_back,
                  semanticLabel: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 22),
              Text('Create your account', style: AppText.heading(27)),
              const SizedBox(height: 6),
              const Text(
                'Set up your ASD-Sense account to get started.',
                style: TextStyle(color: AppColors.textGrey, fontSize: 15),
              ),
              const SizedBox(height: 24),
              LabelledTextField(
                label: 'Full name',
                hint: 'Enter your full name',
                controller: _nameController,
              ),
              const SizedBox(height: 16),
              LabelledTextField(
                label: 'Email address',
                hint: 'name@example.com',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              LabelledTextField(
                label: 'Phone number',
                hint: 'Enter your phone number',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              LabelledTextField(
                label: 'Password',
                hint: 'Create a password',
                controller: _passwordController,
                isPassword: true,
                onChanged: (_) => setState(() {}),
              ),
              if (_showConfirm) ...[
                const SizedBox(height: 16),
                LabelledTextField(
                  label: 'Confirm password',
                  hint: 'Re-enter your password',
                  controller: _confirmController,
                  isPassword: true,
                  onChanged: (_) => setState(() {}),
                  errorText: _mismatch ? 'Passwords do not match' : null,
                ),
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'Create account',
                loading: _loading,
                onPressed: _createAccount,
              ),
              const SizedBox(height: 20),
              const OrDivider(),
              const SizedBox(height: 20),
              const GoogleSignInButton(),
            ],
          ),
        ),
      ),
    );
  }
}
