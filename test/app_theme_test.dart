import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('浅色模式使用日间调色板', () {
      final theme = AppTheme.light;

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, AppColors.backgroundLight);
      expect(theme.colorScheme.primary, AppColors.primaryLight);
      expect(theme.colorScheme.surface, AppColors.surfaceLight);
      expect(theme.colorScheme.onSurface, AppColors.textLight);
    });

    test('深色模式使用低眩光夜间调色板', () {
      final theme = AppTheme.dark;

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.backgroundDark);
      expect(theme.colorScheme.primary, AppColors.primaryDark);
      expect(theme.colorScheme.surface, AppColors.surfaceDark);
      expect(theme.colorScheme.onSurface, AppColors.textDark);
    });

    test('两种模式都提供统一的 Material 组件样式', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(theme.useMaterial3, isTrue);
        expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
        expect(theme.bottomSheetTheme.showDragHandle, isTrue);
        expect(theme.floatingActionButtonTheme.elevation, isNotNull);
        expect(theme.segmentedButtonTheme.style, isNotNull);
      }
    });

    test('主要文字和按钮颜色满足基础对比度', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final scheme = theme.colorScheme;
        expect(
          _contrastRatio(scheme.onSurface, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
  });
}

double _contrastRatio(Color foreground, Color background) {
  final light = foreground.computeLuminance();
  final dark = background.computeLuminance();
  final lighter = light > dark ? light : dark;
  final darker = light > dark ? dark : light;
  return (lighter + 0.05) / (darker + 0.05);
}
