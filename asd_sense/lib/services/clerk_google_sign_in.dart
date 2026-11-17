import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Clerk publishable key of the project's shared ASD-Sense Clerk app. It is
/// public by design (it only names the Clerk app), so it is committed; the
/// secret key lives only in the backend's environment. Override per build with
///   flutter run --dart-define=CLERK_PUBLISHABLE_KEY=pk_...
const clerkPublishableKey = String.fromEnvironment(
  'CLERK_PUBLISHABLE_KEY',
  defaultValue: 'pk_test_Z2VudGxlLXdhc3AtODA2LmNsZXJrLmFjY291bnRzLmRldiQ',
);

bool get isGoogleSignInConfigured => clerkPublishableKey.isNotEmpty;

/// Outcome of the Clerk Google flow: a Clerk session token, an error, or neither
/// (the guardian closed the Google page).
class ClerkGoogleResult {
  final String? sessionToken;
  final String? error;
  const ClerkGoogleResult({this.sessionToken, this.error});
}

/// Signs the guardian in with Google through Clerk and returns a short-lived Clerk
/// session token for the backend to exchange (POST /api/auth/clerk).
///
/// Clerk is only mounted on this route, so the rest of the app (and email login)
/// never waits on Clerk. The Clerk session is ended as soon as the token is read:
/// the app's own backend session is what keeps the guardian signed in.
Future<ClerkGoogleResult> signInWithGoogleViaClerk(BuildContext context) async {
  final result = await Navigator.of(context).push<ClerkGoogleResult>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _ClerkGoogleRoute()),
  );
  return result ?? const ClerkGoogleResult();
}

class _ClerkGoogleRoute extends StatefulWidget {
  const _ClerkGoogleRoute();

  @override
  State<_ClerkGoogleRoute> createState() => _ClerkGoogleRouteState();
}

class _ClerkGoogleRouteState extends State<_ClerkGoogleRoute> {
  final _config = ClerkAuthConfig(
    publishableKey: clerkPublishableKey,
    loading: const Center(child: CircularProgressIndicator()),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('Continue with Google')),
      body: ClerkAuth(config: _config, child: const _GoogleFlow()),
    );
  }
}

class _GoogleFlow extends StatefulWidget {
  const _GoogleFlow();

  @override
  State<_GoogleFlow> createState() => _GoogleFlowState();
}

class _GoogleFlowState extends State<_GoogleFlow> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  Future<void> _run() async {
    final auth = ClerkAuth.of(context, listen: false);
    String? error;
    try {
      // A leftover Clerk session (e.g. the app was killed mid-flow) would skip
      // the Google account picker, so always start from signed-out.
      if (auth.isSignedIn) await auth.signOut();
      if (!mounted) return;
      await auth.ssoSignIn(context, clerk.Strategy.oauthGoogle,
          onError: (e) => error ??= e.toString());
      if (!mounted) return;
      if (!auth.isSignedIn) {
        Navigator.of(context).pop(ClerkGoogleResult(error: error));
        return;
      }
      final token = await auth.sessionToken();
      // The backend verifies the token's signature and expiry, not the live
      // Clerk session, so it stays valid for the exchange after this sign-out.
      await auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pop(ClerkGoogleResult(sessionToken: token.jwt));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(ClerkGoogleResult(error: error ?? e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
