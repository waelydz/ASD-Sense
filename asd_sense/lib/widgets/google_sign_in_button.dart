import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../screens/main_shell.dart';
import '../services/api_service.dart';
import '../services/clerk_google_sign_in.dart';
import 'common_widgets.dart';

/// "Continue with Google" for guardians (mobile app only), via Clerk.
/// Works for both sign-in and sign-up: a first-time Google user gets a new
/// guardian account; an existing guardian with the same email is linked.
class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({super.key});

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _busy = false;

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _continue() async {
    if (_busy) return;
    if (!isGoogleSignInConfigured) {
      _show('Google sign-in is not set up in this build of the app.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await signInWithGoogleViaClerk(context);
      if (!mounted) return;
      final token = result.sessionToken;
      if (token == null) {
        if (result.error != null) {
          debugPrint('Clerk Google sign-in failed: ${result.error}');
          _show('Google sign-in did not complete. Please try again.');
        }
        return; // Closed by the guardian: nothing to report.
      }
      await AppData.instance.signInWithGoogle(token);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _show(e is ApiException
          ? e.message
          : 'Unable to sign in with Google. Check backend connectivity.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecondaryButton(
      label: _busy ? 'Signing in…' : 'Continue with Google',
      leading: _busy
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const GoogleLogo(),
      onPressed: _busy ? null : _continue,
    );
  }
}
