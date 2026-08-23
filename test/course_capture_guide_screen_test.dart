import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/core/theme/app_theme.dart';
import 'package:hormone/features/import/presentation/course_capture_guide_screen.dart';

void main() {
  Future<void> pumpGuide(
    WidgetTester tester, {
    required ThemeData theme,
    VoidCallback? onStartCapture,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: CourseCaptureGuideScreen(onStartCapture: onStartCapture),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('展示完整的四步抓取说明并可开始抓取', (tester) async {
    var started = false;
    await pumpGuide(
      tester,
      theme: AppTheme.light,
      onStartCapture: () => started = true,
    );

    expect(find.text('课程抓取使用说明'), findsOneWidget);
    expect(find.text('选择学校'), findsOneWidget);
    expect(find.text('登录教务系统'), findsOneWidget);
    expect(find.text('打开个人课表'), findsOneWidget);
    expect(find.text('抓取、核对并导入'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('没有抓取到课程？'), findsOneWidget);

    final startButton = find.byKey(const Key('start-course-capture'));
    await tester.ensureVisible(startButton);
    await tester.pumpAndSettle();
    await tester.tap(startButton);

    expect(started, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色模式下保持可滚动且无布局异常', (tester) async {
    await pumpGuide(tester, theme: AppTheme.dark);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final context = tester.element(find.byWidget(scaffold));
    expect(Theme.of(context).brightness, Brightness.dark);

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.text('开始抓取课程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
