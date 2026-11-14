import 'package:flutter/material.dart';
import 'data/app_data.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AsdSenseApp());
}

class AsdSenseApp extends StatefulWidget {
  const AsdSenseApp({super.key});

  @override
  State<AsdSenseApp> createState() => _AsdSenseAppState();
}

class _AsdSenseAppState extends State<AsdSenseApp> {
  late final Future<bool> _startup = AppData.instance.restoreSession();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ASD-Sense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: FutureBuilder<bool>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.data == true ? const MainShell() : const LoginScreen();
        },
      ),
    );
  }
}
