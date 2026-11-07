import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:recess/core/models/semester.dart';
import 'package:recess/data/app_database.dart' as db;
import 'package:recess/data/providers/database_providers.dart';
import 'package:recess/features/schedule/application/schedule_providers.dart';
import 'package:recess/features/schedule/presentation/schedule_screen.dart';
import 'package:recess/features/semester/application/semester_mutations.dart';
import 'package:recess/features/semester/application/semester_providers.dart';
import 'package:recess/features/semester/presentation/semester_screen.dart';

void main() {
  final today = DateTime(2026, 10, 22);
  late db.AppDatabase database;
  late ProviderContainer container;
  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = db.AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        selectedWeekProvider.overrideWith(
          (ref) => SelectedWeekNotifier(
            ref.watch(semesterRepositoryProvider),
            now: () => today,
          ),
        ),
      ],
    );
    await container
        .read(semesterRepositoryProvider)
        .upsert(
          Semester(
            id: 'old',
            name: '原学期',
            startDate: DateTime(2026, 9, 7),
            totalWeeks: 18,
            currentWeekOverride: 12,
          ),
          activate: true,
        );
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => ScheduleScreen(now: () => today),
        ),
        GoRoute(
          path: '/semester',
          builder: (_, __) => SemesterScreen(now: () => today),
        ),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    container.dispose();
    await database.close();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container.listen(activeSemesterProvider, (_, __) {});
    await container.read(activeSemesterProvider.future);
    container.listen(scheduleCoursesProvider, (_, __) {});
    await container.read(scheduleCoursesProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> viewNinthWeek(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('schedule-week-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳转到第几周'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('9')),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 9 周   当前为第 12 周'), findsOneWidget);
  }

  Future<void> openManagement(WidgetTester tester) async {
    router.go('/semester');
    await tester.pumpAndSettle();
    await container.read(semestersProvider.future);
    await tester.pumpAndSettle();
  }

  Future<void> waitForSheetClosed(WidgetTester tester) async {
    for (
      var i = 0;
      i < 100 && find.byType(SemesterEditSheet).evaluate().isNotEmpty;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(SemesterEditSheet), findsNothing);
  }

  Future<void> returnToSchedule(WidgetTester tester) async {
    await container.read(activeSemesterProvider.future);
    router.go('/');
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
  }

  Future<void> startNewSemester(WidgetTester tester, String name) async {
    await openManagement(tester);
    await tester.tap(find.byTooltip('添加学期'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();
  }

  Future<void> chooseSeptemberSeventh(WidgetTester tester) async {
    await tester.tap(find.text('2026-10-26'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '09/07/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('2026-09-07'), findsOneWidget);
  }

  testWidgets('切换到手动当前周学期后查看第5周', (tester) async {
    await tester.runAsync(() async {
      final target = Semester(
        id: 'manual',
        name: '手动当前周学期',
        startDate: DateTime(2026, 9, 7),
        totalWeeks: 18,
        currentWeekOverride: 5,
      );
      await container.read(semesterRepositoryProvider).upsert(target);
      await mount(tester);
      await viewNinthWeek(tester);
      await openManagement(tester);
      await container
          .read(semesterMutationsProvider)
          .save(target, activate: true);
      await returnToSchedule(tester);
      expect(find.text('第 5 周'), findsOneWidget);
      final active =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      expect(active!.id, 'manual');
      expect(active.currentWeekOverride, 5);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('切到已结束的四周学期查看周限制为第4周', (tester) async {
    await tester.runAsync(() async {
      final target = Semester(
        id: 'ended',
        name: '已结束学期',
        startDate: DateTime(2026, 9, 7),
        totalWeeks: 4,
      );
      await container.read(semesterRepositoryProvider).upsert(target);
      await mount(tester);
      await viewNinthWeek(tester);
      await openManagement(tester);
      await container
          .read(semesterMutationsProvider)
          .save(target, activate: true);
      await returnToSchedule(tester);
      expect(find.text('第 4 周'), findsOneWidget);
      final active =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      expect(active!.id, 'ended');
      expect(active.totalWeeks, 4);
      expect(tester.takeException(), isNull);
    });
  });

  for (final editCurrent in [false, true]) {
    testWidgets('保存${editCurrent ? '当前' : '非当前'}学期不打断查看第9周', (tester) async {
      await tester.runAsync(() async {
        if (!editCurrent) {
          await container
              .read(semesterRepositoryProvider)
              .upsert(
                Semester(
                  id: 'other',
                  name: '其他学期',
                  startDate: DateTime(2027, 2, 22),
                  totalWeeks: 18,
                ),
              );
        }
        await mount(tester);
        await viewNinthWeek(tester);
        await openManagement(tester);
        await tester.tap(find.text(editCurrent ? '原学期' : '其他学期'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '只改名称');
        await tester.pump();
        await tester.tap(find.text('保存'));
        await waitForSheetClosed(tester);
        await returnToSchedule(tester);
        expect(find.text('第 9 周   当前为第 12 周'), findsOneWidget);
        final semesters =
            await container.read(semesterRepositoryProvider).getSemesters();
        expect(
          semesters
              .singleWhere((s) => s.id == (editCurrent ? 'old' : 'other'))
              .name,
          '只改名称',
        );
        expect(
          (await container
                  .read(semesterRepositoryProvider)
                  .getActiveSemester())!
              .id,
          'old',
        );
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('再次设同一学期为当前不打断查看第9周', (tester) async {
    await tester.runAsync(() async {
      await mount(tester);
      await viewNinthWeek(tester);
      await openManagement(tester);
      final active =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      await container
          .read(semesterMutationsProvider)
          .save(active!, activate: true);
      await returnToSchedule(tester);
      expect(find.text('第 9 周   当前为第 12 周'), findsOneWidget);
      expect(
        (await container.read(semesterRepositoryProvider).getActiveSemester())!
            .id,
        'old',
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('新建并设为当前失败保留原学期和查看第9周', (tester) async {
    await tester.runAsync(() async {
      await mount(tester);
      await viewNinthWeek(tester);
      await startNewSemester(tester, '失败学期');
      await database.customStatement('''
        CREATE TRIGGER fail_activation BEFORE UPDATE OF is_active ON semesters
        WHEN NEW.is_active = 1
        BEGIN SELECT RAISE(ABORT, 'forced activation failure'); END;
      ''');
      await tester.tap(find.text('创建'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      expect(find.byType(SemesterEditSheet), findsOneWidget);
      expect(find.textContaining('保存失败'), findsOneWidget);
      final semesters =
          await container.read(semesterRepositoryProvider).getSemesters();
      expect(semesters.single.id, 'old');
      expect(
        (await container.read(semesterRepositoryProvider).getActiveSemester())!
            .id,
        'old',
      );
      Navigator.of(tester.element(find.byType(SemesterEditSheet))).pop();
      await tester.pumpAndSettle();
      await returnToSchedule(tester);
      expect(find.text('第 9 周   当前为第 12 周'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('删除当前学期后回退学期的查看周同步', (tester) async {
    await tester.runAsync(() async {
      await container
          .read(semesterRepositoryProvider)
          .upsert(
            Semester(
              id: 'fallback',
              name: '保留学期',
              startDate: DateTime(2026, 9, 7),
              totalWeeks: 18,
              currentWeekOverride: 5,
            ),
          );
      await mount(tester);
      await viewNinthWeek(tester);
      await openManagement(tester);
      await tester.tap(find.text('原学期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除学期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await waitForSheetClosed(tester);
      await returnToSchedule(tester);
      expect(find.text('第 5 周'), findsOneWidget);
      final active =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      expect(active!.id, 'fallback');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('新建已开学学期设为当前后查看推算第7周', (tester) async {
    await tester.runAsync(() async {
      await mount(tester);
      await viewNinthWeek(tester);
      await startNewSemester(tester, '已开学学期');
      await chooseSeptemberSeventh(tester);
      await tester.tap(find.text('创建'));
      await waitForSheetClosed(tester);
      await returnToSchedule(tester);
      expect(find.textContaining('第 7 周'), findsOneWidget);
      final active =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      expect(active!.name, '已开学学期');
      expect(active.startDate, DateTime(2026, 9, 7));
      expect(active.currentWeekOverride, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('课表仍挂载时新建已开学学期也同步查看第7周', (tester) async {
    await tester.runAsync(() async {
      await mount(tester);
      await viewNinthWeek(tester);
      router.push('/semester');
      await tester.pumpAndSettle();
      await container.read(semestersProvider.future);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加学期'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '已开学学期');
      await tester.pump();
      await chooseSeptemberSeventh(tester);
      await tester.tap(find.text('创建'));
      await waitForSheetClosed(tester);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.textContaining('第 7 周'), findsOneWidget);
      final active =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      expect(active!.name, '已开学学期');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('新建未开学学期设为当前后查看第1周', (tester) async {
    await tester.runAsync(() async {
      await mount(tester);
      await viewNinthWeek(tester);
      await openManagement(tester);
      await tester.tap(find.byTooltip('添加学期'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '未开学学期');
      await tester.pump();
      await tester.tap(find.text('创建'));
      await waitForSheetClosed(tester);
      await returnToSchedule(tester);
      expect(find.text('第 1 周'), findsOneWidget);
      final active =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      expect(active!.name, '未开学学期');
      expect(tester.takeException(), isNull);
    });
  });
}
