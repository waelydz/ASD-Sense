import 'package:flutter/material.dart';
import 'screens/sign_in_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const AsdSenseApp());
}

class AsdSenseApp extends StatelessWidget {
  const AsdSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ASD-Sense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SignInScreen(),
    );
  }
}
