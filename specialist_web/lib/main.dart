import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'clinician/api_client.dart';
import 'clinician/clinic_data.dart';
import 'clinician/nav.dart';
import 'clinician/pages/sign_in_page.dart';
import 'clinician/shell.dart';
import 'theme/app_theme.dart';

/// Entry point for the clinician web portal.
///
///   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
///   flutter build web --dart-define=API_BASE_URL=http://localhost:8000
///
/// The guardian mobile app is a separate project in ../asd_sense.
void main() {
  // Flutter must be initialised before the keyboard listener below.
  WidgetsFlutterBinding.ensureInitialized();
  // Any key press counts as activity for automatic sign-out.
  HardwareKeyboard.instance.addHandler((_) {
    ClinicData.instance.touch();
    return false;
  });
  runApp(ClinicScope(child: const ClinicianPortalApp()));
}

final _messengerKey = GlobalKey<ScaffoldMessengerState>();

class ClinicianPortalApp extends StatelessWidget {
  const ClinicianPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Changes saved in the background (e.g. an appointment status) report
    // failures here, whatever page is showing.
    ClinicData.instance.onError =
        (message) => _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
    return MaterialApp(
      title: 'ASD-Sense Clinician Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scaffoldMessengerKey: _messengerKey,
      // Mouse and touch input count as activity too, including inside dialogs.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => ClinicData.instance.touch(),
        onPointerHover: (_) => ClinicData.instance.touch(),
        onPointerSignal: (_) => ClinicData.instance.touch(),
        child: child,
      ),
      home: const _Startup(),
    );
  }
}

/// Reopening or reloading the portal keeps the clinician signed in while
/// their session is still valid; otherwise it shows the sign-in page.
class _Startup extends StatefulWidget {
  const _Startup();

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final data = ClinicData.instance;
    Widget next;
    try {
      if (await data.restoreSession()) {
        Nav.instance.reset();
        next = const ClinicianShell();
      } else {
        next = SignInPage(message: data.signedOutReason);
      }
    } on ApiException catch (e) {
      // Backend not reachable: the saved session is kept for the next reload.
      next = SignInPage(message: e.message);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(pageBuilder: (_, __, ___) => next, transitionDuration: Duration.zero),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}
