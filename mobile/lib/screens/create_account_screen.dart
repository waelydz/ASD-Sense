import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
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
  bool _loading = false;

  Future<void> _createAccount({bool viaGoogle = false}) async {
    if (!viaGoogle && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your full name to continue.')),
      );
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _loading = false);

    AppData.instance.completeSignUp(
      name: viaGoogle ? 'Google Account' : _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
    );

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
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'Create account',
                loading: _loading,
                onPressed: () => _createAccount(),
              ),
              const SizedBox(height: 20),
              const OrDivider(),
              const SizedBox(height: 20),
              SecondaryButton(
                label: 'Sign up with Google',
                leading: const GoogleLogo(),
                onPressed: () => _createAccount(viaGoogle: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
