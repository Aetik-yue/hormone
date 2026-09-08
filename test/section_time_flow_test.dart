import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/features/notification/application/reminder_scheduler.dart';
import 'package:hormone/features/schedule/presentation/week_view.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';
import 'package:hormone/features/settings/presentation/section_time_editor.dart';
import 'package:hormone/features/settings/presentation/settings_screen.dart';

void main() {
  final semester = Semester(
    id: 'functional-test',
    name: '测试学期',
    startDate: DateTime(2026, 9, 7),
    totalWeeks: 18,
  );
  const course = Course(
    id: 'functional-test-course',
    semesterId: 'functional-test',
    name: '功能测试课',
    dayOfWeek: DateTime.monday,
    startSection: 2,
    endSection: 3,
    weeks: [1],
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Hormone',
      packageName: 'com.aetikyue.hormone',
      version: '1.2.4',
      buildNumber: '24',
      buildSignature: 'test',
    );
  });

  Future<(ProviderContainer, GoRouter)> openSettings(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        activeSemesterProvider.overrideWith((ref) async => semester),
        scheduleCoursesProvider.overrideWith((ref) => Stream.value([course])),
      ],
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => Scaffold(
                appBar: AppBar(
                  actions: [
                    IconButton(
                      onPressed: () => context.push('/settings'),
                      icon: const Icon(Icons.settings),
                    ),
                  ],
                ),
                body: const WeekView(selectedWeek: 1),
              ),
        ),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义节次时间'));
    await tester.pumpAndSettle();
    return (container, router);
  }

  Future<void> pickStart(
    WidgetTester tester,
    String hour,
    String minute,
  ) async {
    await tester.ensureVisible(find.byKey(const ValueKey('section-start-1')));
    await tester.tap(find.byKey(const ValueKey('section-start-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), hour);
    await tester.enterText(find.byType(TextField).at(1), minute);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('手机尺寸下从设置入口顺延后，返回课表及课程详情使用新时间', (tester) async {
    final (container, router) = await openSettings(tester);
    await pickStart(tester, '08', '30');
    expect(find.text('09:25'), findsOneWidget);
    final saved = container.read(sectionTimesProvider);
    expect(saved[5]?.startTime, '14:30');

    // 关闭真实底部弹层并退出设置页。
    Navigator.of(tester.element(find.byType(SectionTimeEditor))).pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('09:25'), findsOneWidget);
    expect(find.text('10:30'), findsOneWidget);
    await tester.tap(find.text('功能测试课'));
    await tester.pumpAndSettle();
    expect(find.textContaining('09:25'), findsWidgets);
    expect(find.text('周一 第2-3节 (09:25-11:15)'), findsOneWidget);

    final reminders = computeReminders(
      courses: [course],
      semester: semester,
      sectionTimes: saved,
      now: DateTime(2026, 9, 7, 7),
      leadMinutes: 10,
    );
    expect(reminders.single.trigger, DateTime(2026, 9, 7, 9, 15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('模板切换、顺延、重新打开及恢复默认形成完整可用流程', (tester) async {
    final (container, _) = await openSettings(tester);
    await tester.tap(find.text('模板'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90 分钟大节课制'));
    await tester.pumpAndSettle();
    await pickStart(tester, '08', '30');
    expect(container.read(sectionTimesProvider)[2]?.timeRange, '10:15-11:45');
    expect(container.read(sectionTimesProvider)[7]?.startTime, isEmpty);

    Navigator.of(tester.element(find.byType(SectionTimeEditor))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义节次时间'));
    await tester.pumpAndSettle();
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('10:15'), findsOneWidget);
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(find.text('08:00'), findsOneWidget);
    expect(container.read(sectionTimesProvider)[2]?.timeRange, '08:55-09:40');
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏和两倍字号下节次设置可以完整显示并滚动', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SectionTimeEditor())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('section-start-16')),
      300,
      scrollable: scrollable,
    );
    expect(find.text('第 16 节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
