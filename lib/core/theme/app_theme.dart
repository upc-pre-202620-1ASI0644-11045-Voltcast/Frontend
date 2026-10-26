import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const blue = Color(0xFF2563EB);
  static const ink = Color(0xFF0B0B10);
  static const muted = Color(0xFF8B93A7);
  static const hint = Color(0xFFC4C9D4);
  static const border = Color(0xFFE5E7EB);
  static const surface = Color(0xFFF1F4F9);
  static const disabledBg = Color(0xFFF3F4F6);
  static const disabledFg = Color(0xFFC5CAD3);
  static const error = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);

  // One hue per kind of action so buttons can be told apart at a glance.
  static const teal = Color(0xFF0D9488); // create / confirm
  static const violet = Color(0xFF7C3AED); // codes / secondary flows
  static const orange = Color(0xFFEA580C); // swap / move
  static const tealSoft = Color(0xFFE6F7F5);
  static const violetSoft = Color(0xFFF3EEFF);
  static const orangeSoft = Color(0xFFFFF1E6);

  // Signed-in screens: blue header, lime call to action, navy bottom bar.
  static const headerTop = Color(0xFF2563EB);
  static const headerBottom = Color(0xFF3730A3);
  static const lime = Color(0xFFBEF264);
  static const navy = Color(0xFF0F172A);
  static const blueSoft = Color(0xFFE3ECFD);
  static const errorSoft = Color(0xFFFDE8E8);
  static const field = Color(0xFFEEF1F6);
  static const amber = Color(0xFFD97706);
}

/// Shared corner radii.
class AppRadius {
  AppRadius._();

  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 22.0;

  static final small = BorderRadius.circular(sm);
  static final medium = BorderRadius.circular(md);
  static final large = BorderRadius.circular(lg);
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
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.large),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        showDragHandle: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
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
