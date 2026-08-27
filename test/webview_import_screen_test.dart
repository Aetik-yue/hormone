import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/core/theme/app_theme.dart';
import 'package:hormone/features/import/application/course_capture_orientation.dart';
import 'package:hormone/features/import/data/cqu_adapter.dart';
import 'package:hormone/features/import/presentation/webview_import_screen.dart';

void main() {
  test('WebView 仅将 ERR_CACHE_MISS 识别为可恢复缓存错误', () {
    expect(isWebViewCacheMiss('net::ERR_CACHE_MISS'), isTrue);
    expect(isWebViewCacheMiss('Net::Err_Cache_Miss'), isTrue);
    expect(isWebViewCacheMiss('net::ERR_NAME_NOT_RESOLVED'), isFalse);
  });

  testWidgets('学校 URL 与说明文字使用可读的正文弱化色', (tester) async {
    final orientationCalls = <List<DeviceOrientation>>[];
    final orientationController = CourseCaptureOrientationController(
      setPreferredOrientations: (orientations) async {
        orientationCalls.add(List.of(orientations));
      },
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
    expect(
      find.text('登录和浏览保持竖屏；点击抓取时会短暂切换横屏，保证七天课表列位置稳定。'),
      findsOneWidget,
    );
    expect(find.text('重点高校（39/39）'), findsOneWidget);
    expect(find.text('专用适配'), findsOneWidget);
    expect(orientationCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('可按学校名称筛选高校目录', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const WebviewImportScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('school-search-field')),
      '浙江大学',
    );
    await tester.pump();

    expect(find.text('重点高校（1/39）'), findsOneWidget);
    expect(find.text('浙江大学'), findsNWidgets(2));
    expect(find.text('重庆大学'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
