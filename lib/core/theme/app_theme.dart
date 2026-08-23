import 'package:flutter/material.dart';

/// Hormone 的配色令牌。
///
/// 浅色模式取意于晨间课表与纸张，深色模式取意于夜间校园；两套配色共享
/// 同一套蓝色识别色，并针对各自背景单独校准对比度。
class AppColors {
  static const primaryLight = Color(0xFF3568D4);
  static const primaryDark = Color(0xFF8AAEFF);

  static const backgroundLight = Color(0xFFF3F6FB);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceMutedLight = Color(0xFFEAF0F8);
  static const outlineLight = Color(0xFFD6DFEC);
  static const textLight = Color(0xFF182033);
  static const textMutedLight = Color(0xFF69758A);

  static const backgroundDark = Color(0xFF0B101A);
  static const surfaceDark = Color(0xFF141B27);
  static const surfaceMutedDark = Color(0xFF1C2635);
  static const outlineDark = Color(0xFF324055);
  static const textDark = Color(0xFFEDF2FC);
  static const textMutedDark = Color(0xFFA8B4C7);

  static const success = Color(0xFF34B37E);

  /// 兼容已有课程默认色引用。
  static const primary = primaryLight;
}

class AppTheme {
  static final light = _build(
    brightness: Brightness.light,
    primary: AppColors.primaryLight,
    background: AppColors.backgroundLight,
    surface: AppColors.surfaceLight,
    surfaceMuted: AppColors.surfaceMutedLight,
    outline: AppColors.outlineLight,
    text: AppColors.textLight,
    textMuted: AppColors.textMutedLight,
  );

  static final dark = _build(
    brightness: Brightness.dark,
    primary: AppColors.primaryDark,
    background: AppColors.backgroundDark,
    surface: AppColors.surfaceDark,
    surfaceMuted: AppColors.surfaceMutedDark,
    outline: AppColors.outlineDark,
    text: AppColors.textDark,
    textMuted: AppColors.textMutedDark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color background,
    required Color surface,
    required Color surfaceMuted,
    required Color outline,
    required Color text,
    required Color textMuted,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      surface: surface,
    ).copyWith(
      primary: primary,
      onPrimary: isDark ? const Color(0xFF082656) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF17345F) : const Color(0xFFDCE7FF),
      onPrimaryContainer:
          isDark ? const Color(0xFFD8E5FF) : const Color(0xFF17345F),
      secondary: isDark ? const Color(0xFFB2C4E2) : const Color(0xFF526989),
      onSecondary: isDark ? const Color(0xFF203148) : Colors.white,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: textMuted,
      outline: outline,
      outlineVariant: outline.withAlpha(isDark ? 150 : 180),
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      dividerColor: outline.withAlpha(isDark ? 120 : 160),
      disabledColor: textMuted.withAlpha(100),
      visualDensity: VisualDensity.standard,
    );

    final textTheme = base.textTheme
        .apply(
          bodyColor: text,
          displayColor: text,
        )
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            color: text,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            color: text,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            color: text,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            color: text,
            height: 1.35,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            color: textMuted,
            height: 1.35,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            color: textMuted,
            fontWeight: FontWeight.w600,
          ),
        );

    final roundedRectangle = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return base.copyWith(
      textTheme: textTheme,
      iconTheme: IconThemeData(color: textMuted, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: text,
        iconTheme: IconThemeData(color: primary, size: 24),
        actionsIconTheme: IconThemeData(color: primary, size: 24),
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 18),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: roundedRectangle.copyWith(
          side: BorderSide(color: outline.withAlpha(isDark ? 90 : 105)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: roundedRectangle,
      ),
      dividerTheme: DividerThemeData(
        color: outline.withAlpha(isDark ? 105 : 135),
        thickness: 0.8,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        textColor: text,
        subtitleTextStyle: textTheme.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted.withAlpha(isDark ? 205 : 190),
        hintStyle: TextStyle(color: textMuted),
        labelStyle: TextStyle(color: textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline.withAlpha(180)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        elevation: isDark ? 2 : 1,
        focusElevation: 3,
        hoverElevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 46),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 46),
          side: BorderSide(color: outline),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : textMuted,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : surface,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceMuted,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: outline.withAlpha(140)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w500),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isDark ? const Color(0xFFE5ECF8) : const Color(0xFF202A3A),
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFF152033) : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(primary.withAlpha(125)),
        radius: const Radius.circular(999),
        thickness: const WidgetStatePropertyAll(3),
      ),
    );
  }
}
