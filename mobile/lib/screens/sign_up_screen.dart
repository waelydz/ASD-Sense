import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'main_shell.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;

  Future<void> _createAccount() async {
    if (_passwordController.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Create Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabelledTextField(
                label: 'Full Name',
                hint: 'Enter your full name',
                controller: _nameController,
              ),
              const SizedBox(height: 18),
              LabelledTextField(
                label: 'Email Address',
                hint: 'Enter your email',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 18),
              LabelledTextField(
                label: 'Phone Number',
                hint: 'Enter your phone number',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 18),
              LabelledTextField(
                label: 'Password',
                hint: 'Create a password',
                controller: _passwordController,
                isPassword: true,
              ),
              const SizedBox(height: 18),
              LabelledTextField(
                label: 'Confirm Password',
                hint: 'Confirm your password',
                controller: _confirmController,
                isPassword: true,
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Create Account',
                loading: _loading,
                onPressed: _createAccount,
              ),
              const SizedBox(height: 20),
              const OrDivider(),
              const SizedBox(height: 20),
              OutlineButtonWidget(
                label: 'Sign up with Google',
                leading: const GoogleLogo(),
                onPressed: _createAccount,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
