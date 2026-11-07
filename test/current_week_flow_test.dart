import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/semester.dart';
import 'package:recess/data/app_database.dart' as db;
import 'package:recess/data/providers/database_providers.dart';
import 'package:recess/features/schedule/application/schedule_providers.dart';
import 'package:recess/features/schedule/presentation/schedule_screen.dart';
import 'package:recess/features/semester/application/semester_providers.dart';
import 'package:recess/features/semester/presentation/semester_screen.dart';
import 'package:recess/features/widget/application/widget_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late db.AppDatabase database;
  late ProviderContainer container;
  late GoRouter router;
  late Map<String, Object?> widgetData;
  final now = DateTime.now();
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  const dayLabels = ['一', '二', '三', '四', '五', '六', '日'];
  const channel = MethodChannel('home_widget');
  const updates = MethodChannel('home_widget/updates');

  Semester semester({
    int? currentWeek = 12,
    int totalWeeks = 18,
    DateTime? start,
  }) => Semester(
    id: 's',
    name: '测试学期',
    startDate: start ?? monday,
    totalWeeks: totalWeeks,
    currentWeekOverride: currentWeek,
  );

  Course course(int week) => Course(
    id: 'c$week',
    semesterId: 's',
    name: '第$week周课程',
    dayOfWeek: now.weekday,
    startSection: 1,
    endSection: 2,
    weeks: [week],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    widgetData = {};
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map;
        widgetData[args['id'] as String] = args['data'];
      }
      return true;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      updates,
      (call) async => null,
    );
    database = db.AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    await container
        .read(semesterRepositoryProvider)
        .upsert(semester(), activate: true);
    for (final week in [1, 8, 9, 12]) {
      await container.read(courseRepositoryProvider).upsert(course(week));
    }
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const ScheduleScreen()),
        GoRoute(path: '/semester', builder: (_, __) => const SemesterScreen()),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    container.dispose();
    await database.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(updates, null);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container.listen(activeSemesterProvider, (_, __) {});
    await tester.runAsync(() async {
      await container.read(activeSemesterProvider.future);
      container.listen(scheduleCoursesProvider, (_, __) {});
      await container.read(scheduleCoursesProvider.future);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openToday(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日课程'));
    await tester.pumpAndSettle();
  }

  Finder todayText(String text) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> widgetOccurrences() =>
      (jsonDecode(widgetData['occurrences'] as String) as List)
          .cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> widgetDays() =>
      (jsonDecode(widgetData['semester_days'] as String) as List)
          .cast<Map<String, dynamic>>();

  int? widgetWeekOn(DateTime date) {
    final key = dateKey(date);
    for (final day in widgetDays()) {
      if (day['date'] == key) return day['week'] as int;
    }
    return null;
  }

  Map<String, dynamic>? widgetOccurrenceOn(DateTime date) {
    final key = dateKey(date);
    final items =
        widgetOccurrences().where((item) => item['date'] == key).toList();
    return items.isEmpty ? null : items.first;
  }

  Future<void> openEdit(WidgetTester tester, String name) async {
    router.push('/semester');
    await tester.pumpAndSettle();
    await tester.runAsync(() => container.read(semestersProvider.future));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  Future<void> shrinkToEight(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
    }
    expect(
      find.descendant(
        of: find.byType(SemesterEditSheet),
        matching: find.text('8'),
      ),
      findsNWidgets(2),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  }

  Future<void> saveAndWait(WidgetTester tester) async {
    await tester.tap(find.text('保存'));
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 100 && find.byType(SemesterEditSheet).evaluate().isNotEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(SemesterEditSheet), findsNothing);
  }

  testWidgets('缩短同一学期保存返回后查看周合法且标题今日高亮与小组件一致', (tester) async {
    await mount(tester);
    container.read(selectedWeekProvider.notifier).goTo(16, totalWeeks: 18);
    await tester.pumpAndSettle();
    expect(find.text('第 16 周   当前为第 12 周'), findsOneWidget);
    final controller =
        tester.widget<PageView>(find.byType(PageView)).controller;
    await openEdit(tester, '测试学期');
    await shrinkToEight(tester);
    await saveAndWait(tester);
    router.pop();
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(
      () => container.read(semesterRepositoryProvider).getActiveSemester(),
    );
    expect(saved!.currentWeekOverride, 8);
    expect(saved.totalWeeks, 8);
    expect(container.read(selectedWeekProvider), 8);
    expect(find.text('第 8 周'), findsOneWidget);
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller,
      same(controller),
    );
    expect(controller!.page, 7);
    final day = find.descendant(
      of: find.byKey(const ValueKey(8)),
      matching: find.text('周${dayLabels[now.weekday - 1]}'),
    );
    expect(tester.widget<Text>(day).style!.fontWeight, FontWeight.bold);
    await openToday(tester);
    expect(todayText('第8周课程'), findsOneWidget);
    expect(todayText('第12周课程'), findsNothing);
    expect(find.textContaining('第 8 周 · 周'), findsOneWidget);
    await tester.runAsync(
      () => container.read(widgetServiceProvider).updateWidget(),
    );
    expect(widgetData.containsKey('widget_title'), isFalse);
    expect(widgetData.containsKey('courses'), isFalse);
    expect(widgetData['widget_loaded'], isTrue);
    expect(widgetWeekOn(now), 8);
    expect(widgetOccurrenceOn(now)!['name'], '第8周课程');
    expect(tester.takeException(), isNull);
  });

  testWidgets('学期管理卡片的当前周与课表手动当前周一致', (tester) async {
    await mount(tester);
    router.push('/semester');
    await tester.pumpAndSettle();
    await tester.runAsync(() => container.read(semestersProvider.future));
    await tester.pumpAndSettle();
    expect(find.text('共 18 周 · 第 12 周'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换查看周不写当前周，今日与小组件仍使用手动当前周', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const Key('schedule-week-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳转到第几周'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('5')),
    );
    await tester.pumpAndSettle();
    expect(container.read(selectedWeekProvider), 5);
    expect(find.text('第 5 周   当前为第 12 周'), findsOneWidget);
    final saved = await tester.runAsync(
      () => container.read(semesterRepositoryProvider).getActiveSemester(),
    );
    expect(saved!.currentWeekOverride, 12);
    await openToday(tester);
    expect(todayText('第12周课程'), findsOneWidget);
    await tester.runAsync(
      () => container.read(widgetServiceProvider).updateWidget(),
    );
    expect(widgetWeekOn(now), 12);
    expect(widgetOccurrenceOn(now)!['name'], '第12周课程');
    expect(tester.takeException(), isNull);
  });

  testWidgets('缩短非激活学期不改变激活学期当前周或查看周', (tester) async {
    await tester.runAsync(
      () => container
          .read(semesterRepositoryProvider)
          .upsert(semester().copyWith(id: 'other', name: '其他学期')),
    );
    await mount(tester);
    container.read(selectedWeekProvider.notifier).goTo(16, totalWeeks: 18);
    await tester.pumpAndSettle();
    await openEdit(tester, '其他学期');
    await shrinkToEight(tester);
    await saveAndWait(tester);
    router.pop();
    await tester.pumpAndSettle();
    expect(container.read(selectedWeekProvider), 16);
    expect(find.text('第 16 周   当前为第 12 周'), findsOneWidget);
    final semesters =
        (await tester.runAsync(
          () => container.read(semesterRepositoryProvider).getSemesters(),
        ))!;
    expect(
      semesters.singleWhere((s) => s.id == 'other').currentWeekOverride,
      8,
    );
    expect(semesters.singleWhere((s) => s.id == 's').currentWeekOverride, 12);
    await tester.runAsync(
      () => container.read(widgetServiceProvider).updateWidget(),
    );
    expect(widgetWeekOn(now), 12);
    expect(widgetOccurrenceOn(now)!['name'], '第12周课程');
    expect(tester.takeException(), isNull);
  });

  testWidgets('缩短学期保存失败保留表单和原持久化课表周数，不报告成功', (tester) async {
    await mount(tester);
    container.read(selectedWeekProvider.notifier).goTo(16, totalWeeks: 18);
    await tester.pumpAndSettle();
    await openEdit(tester, '测试学期');
    await shrinkToEight(tester);
    await tester.runAsync(
      () => database.customStatement('''
      CREATE TRIGGER fail_week_save BEFORE UPDATE ON semesters
      BEGIN SELECT RAISE(ABORT, 'forced week save failure'); END;
    '''),
    );
    await tester.tap(find.text('保存'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SemesterEditSheet), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
    final persisted = await tester.runAsync(
      () => container.read(semesterRepositoryProvider).getActiveSemester(),
    );
    expect(persisted!.totalWeeks, 18);
    expect(persisted.currentWeekOverride, 12);
    expect(
      container.read(activeSemesterProvider).value!.currentWeekOverride,
      12,
    );
    Navigator.of(tester.element(find.byType(SemesterEditSheet))).pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(container.read(selectedWeekProvider), 16);
    expect(find.text('第 16 周   当前为第 12 周'), findsOneWidget);
    await tester.runAsync(
      () => container.read(widgetServiceProvider).updateWidget(),
    );
    expect(widgetWeekOn(now), 12);
    expect(widgetOccurrenceOn(now)!['name'], '第12周课程');
    expect(tester.takeException(), isNull);
  });

  for (final sample in [(raw: 12, valid: 8), (raw: 0, valid: 1)]) {
    testWidgets('旧手动${sample.raw}读取时标题今日高亮和小组件一致，纯读取不修库', (tester) async {
      await tester.runAsync(() async {
        await container
            .read(semesterRepositoryProvider)
            .upsert(semester(currentWeek: 1, totalWeeks: 8));
        await database.customStatement(
          'UPDATE semesters SET current_week_override = ? WHERE id = ?',
          [sample.raw, 's'],
        );
      });
      await mount(tester);
      container
          .read(selectedWeekProvider.notifier)
          .goTo(sample.valid, totalWeeks: 8);
      await tester.pumpAndSettle();
      expect(find.text('第 ${sample.valid} 周'), findsOneWidget);
      final day = find.descendant(
        of: find.byKey(ValueKey(sample.valid)),
        matching: find.text('周${dayLabels[now.weekday - 1]}'),
      );
      expect(tester.widget<Text>(day).style!.fontWeight, FontWeight.bold);
      await openToday(tester);
      expect(todayText('第${sample.valid}周课程'), findsOneWidget);
      expect(find.textContaining('第 ${sample.valid} 周 · 周'), findsOneWidget);
      await tester.runAsync(
        () => container.read(widgetServiceProvider).updateWidget(),
      );
      expect(widgetWeekOn(now), sample.valid);
      expect(widgetOccurrenceOn(now)!['name'], '第${sample.valid}周课程');
      final persisted = await tester.runAsync(
        () => container.read(semesterRepositoryProvider).getActiveSemester(),
      );
      expect(persisted!.currentWeekOverride, sample.raw);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('第1教学周周一之前不显示第一周今日课程或小组件课程', (tester) async {
    await tester.runAsync(
      () => container
          .read(semesterRepositoryProvider)
          .upsert(
            semester(
              currentWeek: null,
              totalWeeks: 8,
              start: monday.add(const Duration(days: 9)),
            ),
          ),
    );
    await mount(tester);
    expect(find.text('第 1 周'), findsOneWidget);
    final day = find.descendant(
      of: find.byKey(const ValueKey(1)),
      matching: find.text('周${dayLabels[now.weekday - 1]}'),
    );
    expect(tester.widget<Text>(day).style!.fontWeight, FontWeight.normal);
    await openToday(tester);
    expect(todayText('尚未开学'), findsOneWidget);
    expect(todayText('第1周课程'), findsNothing);
    await tester.runAsync(
      () => container.read(widgetServiceProvider).updateWidget(),
    );
    expect(widgetWeekOn(now), 0);
    expect(widgetOccurrenceOn(now), isNull);
    final futureOccurrences = widgetOccurrences();
    expect(futureOccurrences, isNotEmpty);
    expect(
      futureOccurrences.every(
        (item) => (item['date'] as String).compareTo(dateKey(now)) > 0,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('非周一开学仍在同周周一进入第1教学周', (tester) async {
    await tester.runAsync(
      () => container
          .read(semesterRepositoryProvider)
          .upsert(
            semester(
              currentWeek: null,
              totalWeeks: 8,
              start: monday.add(const Duration(days: 2)),
            ),
          ),
    );
    await mount(tester);
    expect(find.text('第 1 周'), findsOneWidget);
    await openToday(tester);
    expect(todayText('第1周课程'), findsOneWidget);
    expect(find.textContaining('第 1 周 · 周'), findsOneWidget);
    await tester.runAsync(
      () => container.read(widgetServiceProvider).updateWidget(),
    );
    expect(widgetWeekOn(now), 1);
    expect(widgetOccurrenceOn(now)!['name'], '第1周课程');
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动学期结束后标题今日和小组件不把范围外周次作为教学周', (tester) async {
    await tester.runAsync(
      () => container
          .read(semesterRepositoryProvider)
          .upsert(
            semester(
              currentWeek: null,
              totalWeeks: 8,
              start: monday.subtract(const Duration(days: 56)),
            ),
          ),
    );
    await mount(tester);
    expect(find.text('第 8 周'), findsOneWidget);
    expect(find.textContaining('当前为第'), findsNothing);
    final day = find.descendant(
      of: find.byKey(const ValueKey(8)),
      matching: find.text('周${dayLabels[now.weekday - 1]}'),
    );
    expect(tester.widget<Text>(day).style!.fontWeight, FontWeight.normal);
    await openToday(tester);
    expect(todayText('学期已结束'), findsOneWidget);
    expect(todayText('第9周课程'), findsNothing);
    expect(todayText('第8周课程'), findsNothing);
    await tester.runAsync(
      () => container.read(widgetServiceProvider).updateWidget(),
    );
    expect(widgetData['widget_loaded'], isTrue);
    expect(widgetDays(), isEmpty);
    expect(widgetOccurrences(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
