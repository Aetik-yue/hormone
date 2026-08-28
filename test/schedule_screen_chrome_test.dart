import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/data/app_database.dart' as db;
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/features/schedule/presentation/schedule_screen.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = db.AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpSchedule(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          appDatabaseProvider.overrideWithValue(database),
          activeSemesterProvider.overrideWith((ref) async => semester),
          scheduleCoursesProvider.overrideWith(
            (ref) => Stream.value(const [course]),
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('主页顶栏使用紧凑高度并将低频操作收进更多菜单', (tester) async {
    await pumpSchedule(tester);

    expect(tester.getSize(find.byType(AppBar)).height, 52);
    expect(
      tester.getSize(find.byKey(const Key('schedule-week-selector'))).height,
      40,
    );
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.today_outlined), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('今日课程'), findsOneWidget);
    expect(find.text('课程抓取说明'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
