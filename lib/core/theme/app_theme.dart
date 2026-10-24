import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const blue = Color(0xFF2563EB);
  static const ink = Color(0xFF0B0B10);
  static const muted = Color(0xFF8B93A7);
  static const hint = Color(0xFFC4C9D4);
  static const border = Color(0xFFE5E7EB);
  static const surface = Color(0xFFF8F9FB);
  static const disabledBg = Color(0xFFF3F4F6);
  static const disabledFg = Color(0xFFC5CAD3);
  static const error = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        primary: AppColors.blue,
        error: AppColors.error,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(),
      ),
    );
  }

  static const title = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.8,
    color: AppColors.ink,
  );

  static const subtitle = TextStyle(
    fontSize: 17,
    height: 1.45,
    color: AppColors.muted,
  );

  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.4,
    color: AppColors.muted,
  );
}
