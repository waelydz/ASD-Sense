import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Password reset with a 6-digit code sent by email (POST /api/auth/forgot,
/// then POST /api/auth/reset). Pops with `true` once the password is changed.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.message : 'Could not reach the server. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter the email address you signed up with.');
      return;
    }
    await _run(() async {
      await AppData.instance.requestPasswordReset(email);
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _reset() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    if (_password.text.length < 12) {
      setState(() => _error = 'The new password must be at least 12 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    await _run(() async {
      await AppData.instance.resetPassword(email: _email.text, code: code, newPassword: _password.text);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, elevation: 0, foregroundColor: AppColors.textDark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reset your password', style: AppText.heading(26)),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? 'If ${_email.text.trim()} has an account, we sent it a 6-digit code. '
                        'It works for 15 minutes.'
                    : 'Enter the email you signed up with and we will send you a code.',
                style: const TextStyle(fontSize: 14.5, color: AppColors.textGrey, height: 1.4),
              ),
              const SizedBox(height: 24),
              if (!_codeSent) ...[
                LabelledTextField(
                  label: 'Email',
                  hint: 'you@example.com',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                if (_error != null) _ErrorText(_error!),
                PrimaryButton(label: 'Send code', loading: _loading, onPressed: _sendCode),
              ] else ...[
                LabelledTextField(
                  label: 'Code',
                  hint: '6 digits',
                  controller: _code,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 14),
                LabelledTextField(
                  label: 'New password',
                  hint: 'At least 12 characters',
                  controller: _password,
                  isPassword: true,
                ),
                const SizedBox(height: 14),
                LabelledTextField(
                  label: 'Confirm new password',
                  hint: 'Type it again',
                  controller: _confirm,
                  isPassword: true,
                ),
                const SizedBox(height: 16),
                if (_error != null) _ErrorText(_error!),
                PrimaryButton(label: 'Set new password', loading: _loading, onPressed: _reset),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : _sendCode,
                  style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
                  child: const Text('Send a new code'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: const TextStyle(color: AppColors.danger, fontSize: 13.5)),
      );
}
