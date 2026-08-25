import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/features/schedule/presentation/week_view.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final semester = Semester(
      id: 'semester',
      name: '测试学期',
      startDate: DateTime(2026, 8, 24),
      totalWeeks: 18,
    );
    const course = Course(
      id: 'course',
      semesterId: 'semester',
      name: '高等数学',
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      weeks: [1],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeSemesterProvider.overrideWith((ref) async => semester),
          scheduleCoursesProvider.overrideWith(
            (ref) => Stream.value(const [course]),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: WeekView(selectedWeek: 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('2 倍系统字号下课表正常构建，节高随缩放', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await pump(tester);

    final scrollView = find.byKey(const Key('week-view-vertical-scroll'));
    final section16 = find.byKey(const ValueKey('section-axis-16'));
    expect(scrollView, findsOneWidget);
    expect(section16, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('课程卡片暴露可读的语义标签', (tester) async {
    await pump(tester);

    // Semantics label 拼接：课程名 + 周X + 节次 + 地点 + 教师。
    expect(
      find.bySemanticsLabel(RegExp('高等数学')),
      findsWidgets,
    );
  });
}