import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF397B76);
  static const Color primaryDark = Color(0xFF285D59);
  static const Color paper = Color(0xFFFBFAF7);
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xFF1D2932);
  static const Color textGrey = Color(0xFF66736F);
  static const Color textFaint = Color(0xFF9AA8A3);
  static const Color border = Color(0xFFE5E7E3);
  static const Color inputBorder = Color(0xFFCCD5D1);

  static const Color sage = Color(0xFF285D59);
  static const Color sageBg = Color(0xFFE7F1EF);

  static const Color success = Color(0xFF326851);
  static const Color successBg = Color(0xFFE9F4EF);

  static const Color sand = Color(0xFF84633A);
  static const Color sandBg = Color(0xFFF7EFE1);

  static const Color lavender = Color(0xFF5D5382);
  static const Color lavenderBg = Color(0xFFEEEAFA);

  static const Color danger = Color(0xFFA44F4A);
  static const Color dangerBg = Color(0xFFFFF4F2);
  static const Color dangerBorder = Color(0xFFE7C8C4);
}

class AppText {
  AppText._();

  static TextStyle heading(
    double size, {
    Color color = AppColors.textDark,
    FontWeight weight = FontWeight.w600,
  }) {
    return GoogleFonts.fraunces(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.18,
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final bodyFont = GoogleFonts.dmSans().fontFamily;
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
      ),
      fontFamily: bodyFont,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionHandleColor: AppColors.primary,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
