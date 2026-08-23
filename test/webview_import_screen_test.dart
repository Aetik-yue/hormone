import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/core/theme/app_theme.dart';
import 'package:hormone/features/import/application/course_capture_orientation.dart';
import 'package:hormone/features/import/data/cqu_adapter.dart';
import 'package:hormone/features/import/presentation/webview_import_screen.dart';

void main() {
  testWidgets('学校 URL 与说明文字使用可读的正文弱化色', (tester) async {
    final orientationController = CourseCaptureOrientationController(
      setPreferredOrientations: (_) async {},
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: WebviewImportScreen(
            orientationController: orientationController,
          ),
        ),
      ),
    );

    final expectedColor = AppTheme.light.colorScheme.onSurfaceVariant;
    final urlText = tester.widget<Text>(find.text(CquAdapter().loginUrl));
    final customDescription = tester.widget<Text>(
      find.text('适用于未列出的学校。输入教务系统网址，登录后点击「抓取课表」。'),
    );

    expect(urlText.style?.color, expectedColor);
    expect(urlText.style?.fontWeight, FontWeight.w500);
    expect(customDescription.style?.color, expectedColor);
    expect(tester.takeException(), isNull);
  });
}
