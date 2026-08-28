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

  testWidgets('课表显示 16 节并可纵向滚动，星期栏保持固定', (tester) async {
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

    final scrollView = find.byKey(const Key('week-view-vertical-scroll'));
    final timeAxis = find.byKey(const Key('week-view-time-axis'));
    final section16 = find.byKey(const ValueKey('section-axis-16'));
    final mondayHeader = find.text('周一');
    expect(scrollView, findsOneWidget);
    expect(tester.getSize(timeAxis).width, 40);
    expect(section16, findsOneWidget);

    final headerY = tester.getTopLeft(mondayHeader).dy;
    final sectionY = tester.getTopLeft(section16).dy;
    await tester.drag(scrollView, const Offset(0, -320));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(section16).dy, lessThan(sectionY));
    expect(tester.getTopLeft(mondayHeader).dy, headerY);
    expect(tester.takeException(), isNull);
  });
}
