import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'main_shell.dart';
import 'sign_up_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _loading = false;

  Future<void> _login() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF3FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 90),
              const Text(
                'ASD-Sense',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Early screening for better care',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: AppColors.textGrey),
              ),
              const SizedBox(height: 40),
              LabelledTextField(
                label: 'Email',
                hint: 'Enter your email',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              LabelledTextField(
                label: 'Password',
                hint: 'Enter your password',
                controller: _passwordController,
                isPassword: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    height: 22,
                    width: 22,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: AppColors.primary,
                      onChanged: (v) =>
                          setState(() => _rememberMe = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Remember me',
                      style: TextStyle(color: AppColors.textDark)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Password reset link sent (demo)')),
                      );
                    },
                    child: const Text('Forgot Password?'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PrimaryButton(
                label: 'Log In',
                loading: _loading,
                onPressed: _login,
              ),
              const SizedBox(height: 20),
              const OrDivider(),
              const SizedBox(height: 20),
              OutlineButtonWidget(
                label: 'Continue with Google',
                leading: const GoogleLogo(),
                onPressed: _login,
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ",
                      style: TextStyle(color: AppColors.textDark)),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SignUpScreen()),
                      );
                    },
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
