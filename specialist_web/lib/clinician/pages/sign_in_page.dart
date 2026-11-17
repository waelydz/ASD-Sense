import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../api_client.dart';
import '../clinic_data.dart';
import '../nav.dart';
import '../shell.dart';
import '../widgets.dart';

/// Clinician sign-in. No self sign-up or Google sign-in: clinician accounts
/// are issued by the clinic. See README.md for current limitations.
class SignInPage extends StatefulWidget {
  /// Shown above the form, e.g. after an automatic sign-out.
  final String? message;
  const SignInPage({super.key, this.message});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _email.text.trim();
    if (_loading) return;
    if (!email.contains('@') || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ClinicData.instance.signIn(email, _password.text);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
      return;
    }
    if (!mounted) return;
    Nav.instance.reset();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(pageBuilder: (_, __, ___) => const ClinicianShell(), transitionDuration: Duration.zero),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('ASD-Sense',
                      textAlign: TextAlign.center, style: AppText.heading(26, color: AppColors.primaryDark)),
                  const SizedBox(height: 4),
                  const Text('Clinician portal',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textGrey, fontSize: 14)),
                  const SizedBox(height: 28),
                  if (widget.message != null) ...[
                    Notice(widget.message!),
                    const SizedBox(height: 18),
                  ],
                  Field(label: 'Hospital email', hint: 'name@hospital.ae', controller: _email),
                  const SizedBox(height: 14),
                  Field(
                    label: 'Password',
                    hint: '••••••••',
                    controller: _password,
                    obscure: true,
                    onSubmitted: (_) => _signIn(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                  ],
                  const SizedBox(height: 22),
                  Btn('Sign in', onPressed: _signIn, loading: _loading, expand: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
