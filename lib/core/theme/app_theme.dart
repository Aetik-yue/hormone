import 'package:flutter/material.dart';

/// Color palette inspired by WakeUp: soft white background + low-saturation accent, card-based, clean.
class AppColors {
  static const primary = Color(0xFF5B8DEF);
  static const backgroundLight = Color(0xFFF7F8FA);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const backgroundDark = Color(0xFF12131A);
  static const surfaceDark = Color(0xFF1C1E27);
  static const textLight = Color(0xFF1B1D23);
  static const textDark = Color(0xFFE8E9EE);
  // TODO: intended for secondary text, to be used in widget styling
  static const textMuted = Color(0xFF9AA0AB);
}

class AppTheme {
  static final light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surfaceLight,
    ),
    scaffoldBackgroundColor: AppColors.backgroundLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceLight,
      elevation: 0,
      scrolledUnderElevation: 2,
      foregroundColor: AppColors.textLight,
      iconTheme: IconThemeData(color: AppColors.primary, size: 24),
      actionsIconTheme: IconThemeData(color: AppColors.primary, size: 24),
      titleTextStyle: TextStyle(
        color: AppColors.textLight,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceLight,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      surface: AppColors.surfaceDark,
    ),
    scaffoldBackgroundColor: AppColors.backgroundDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceDark,
      elevation: 0,
      scrolledUnderElevation: 2,
      foregroundColor: AppColors.textDark,
      iconTheme: IconThemeData(color: AppColors.primary, size: 24),
      actionsIconTheme: IconThemeData(color: AppColors.primary, size: 24),
      titleTextStyle: TextStyle(
        color: AppColors.textDark,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
