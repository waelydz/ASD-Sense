import 'package:flutter/material.dart';

/// Central place for all colors, gradients and shared text styles so the
/// whole app stays visually consistent with the Figma prototypes.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF3B6FF6);
  static const Color primaryDark = Color(0xFF1E4FE0);
  static const Color background = Color(0xFFF4F6FB);
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xFF1A1F36);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color textFaint = Color(0xFF9CA3AF);
  static const Color border = Color(0xFFE3E7EF);

  static const Color success = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color infoBlueBg = Color(0xFFDCE8FF);
  static const Color greenBg = Color(0xFFD9F5E4);
  static const Color purpleBg = Color(0xFFEBE0FB);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color orangeBg = Color(0xFFFCE6D0);
  static const Color orange = Color(0xFFEA580C);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4A7BFA), Color(0xFF1E4FE0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.textDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionHandleColor: AppColors.primary,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    );
  }
}
