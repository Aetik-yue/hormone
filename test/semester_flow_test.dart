import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:recess/core/models/semester.dart';
import 'package:recess/data/app_database.dart' as db;
import 'package:recess/data/providers/database_providers.dart';
import 'package:recess/features/semester/application/semester_providers.dart';
import 'package:recess/features/semester/presentation/semester_screen.dart';

void main() {
  late db.AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = db.AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    await container
        .read(semesterRepositoryProvider)
        .upsert(
          Semester(
            id: 'old',
            name: '旧学期',
            startDate: DateTime(2026, 9, 7),
            totalWeeks: 18,
          ),
          activate: true,
        );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> openSemesters(
    WidgetTester tester, {
    DateTime Function()? now,
  }) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: SemesterScreen(now: now)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Map> snapshot() async =>
      (jsonDecode(await container.read(backupRepositoryProvider).exportJson())
            as Map)
        ..remove('exportedAt');

  Future<void> waitForSheetClosed(WidgetTester tester) async {
    for (
      var attempt = 0;
      attempt < 100 && find.byType(SemesterEditSheet).evaluate().isNotEmpty;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> waitForFailure(WidgetTester tester, String message) async {
    for (var i = 0;
        i < 100 && find.textContaining(message).evaluate().isEmpty;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('新建学期默认设为当前学期且总周数为18', (tester) async {
    await tester.runAsync(() async {
      await openSemesters(tester);
      await tester.tap(find.byTooltip('添加学期'));
      await tester.pumpAndSettle();
      final activate = find.widgetWithText(SwitchListTile, '保存后设为当前学期');
      expect(tester.widget<SwitchListTile>(activate).value, isTrue);
      await tester.enterText(find.byType(TextField), '新学期');
      await tester.pump();
      await tester.tap(find.text('创建'));
      await waitForSheetClosed(tester);
      expect(find.byType(SemesterEditSheet), findsNothing);
      final current =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      expect(current!.name, '新学期');
      expect(current.totalWeeks, 18);
      expect(find.text('当前'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  for (final today in [DateTime(2026, 10, 22), DateTime(2026, 10, 26)]) {
    testWidgets('今天为${today.day}日时新建日期默认为10月26日周一', (tester) async {
      await tester.runAsync(() async {
        await openSemesters(tester, now: () => today);
        await tester.tap(find.byTooltip('添加学期'));
        await tester.pumpAndSettle();
        expect(find.text('2026-10-26'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '新学期');
        await tester.pump();
        await tester.tap(find.text('创建'));
        await waitForSheetClosed(tester);
        final current =
            await container
                .read(semesterRepositoryProvider)
                .getActiveSemester();
        expect(current!.startDate, DateTime(2026, 10, 26));
        expect(current.totalWeeks, 18);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('关闭设为当前开关后创建保留原当前学期', (tester) async {
    await tester.runAsync(() async {
      await openSemesters(tester);
      await tester.tap(find.byTooltip('添加学期'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '提前建好的下学期');
      await tester.tap(find.text('保存后设为当前学期'));
      await tester.pump();
      await tester.tap(find.text('创建'));
      await waitForSheetClosed(tester);
      expect(find.byType(SemesterEditSheet), findsNothing);
      expect(find.text('提前建好的下学期'), findsOneWidget);
      final current =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      expect(current!.id, 'old');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('新建名称为空或空白不能创建有效名称去除首尾空白后保存', (tester) async {
    await tester.runAsync(() async {
      await openSemesters(tester);
      await tester.tap(find.byTooltip('添加学期'));
      await tester.pumpAndSettle();
      final create = find.widgetWithText(FilledButton, '创建');
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      expect(
        (await container.read(semesterRepositoryProvider).getSemesters())
            .length,
        1,
      );
      await tester.enterText(find.byType(TextField), '  新学期  ');
      await tester.pump();
      expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
      await tester.tap(create);
      await waitForSheetClosed(tester);
      expect(find.byType(SemesterEditSheet), findsNothing);
      final current =
          await container.read(semesterRepositoryProvider).getActiveSemester();
      expect(current!.name, '新学期');
      expect(find.text('新学期'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  for (final initialName in ['旧学期', '']) {
    testWidgets('编辑${initialName.isEmpty ? '旧空名称' : '已有'}学期保留日期且名称必填', (
      tester,
    ) async {
      await tester.runAsync(() async {
        if (initialName.isEmpty) {
          await database.customStatement(
            'UPDATE semesters SET name = ? WHERE id = ?',
            ['', 'old'],
          );
        }
        await openSemesters(tester, now: () => DateTime(2026, 10, 22));
        await tester.tap(
          find.text(initialName.isEmpty ? '未命名学期' : initialName),
        );
        await tester.pumpAndSettle();
        expect(find.text('2026-09-07'), findsOneWidget);
        expect(find.text('保存后设为当前学期'), findsNothing);
        final save = find.widgetWithText(FilledButton, '保存');
        if (initialName.isEmpty) {
          expect(tester.widget<FilledButton>(save).onPressed, isNull);
        }
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        await tester.enterText(find.byType(TextField), '   ');
        await tester.pump();
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        final unchanged =
            await container
                .read(semesterRepositoryProvider)
                .getActiveSemester();
        expect(unchanged!.name, initialName);
        await tester.enterText(find.byType(TextField), '  补全名称  ');
        await tester.pump();
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        await tester.tap(save);
        await waitForSheetClosed(tester);
        expect(find.byType(SemesterEditSheet), findsNothing);
        expect(find.text('补全名称'), findsOneWidget);
        final saved =
            await container
                .read(semesterRepositoryProvider)
                .getActiveSemester();
        expect(saved!.name, '补全名称');
        expect(saved.startDate, DateTime(2026, 9, 7));
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('编辑非当前学期保存后仍保留原当前学期', (tester) async {
    await tester.runAsync(() async {
      await container.read(semesterRepositoryProvider).upsert(
            Semester(
              id: 'next',
              name: '下学期',
              startDate: DateTime(2027, 2, 22),
              totalWeeks: 18,
            ),
          );
      await openSemesters(tester);
      await tester.tap(find.text('下学期'));
      await tester.pumpAndSettle();
      expect(find.text('保存后设为当前学期'), findsNothing);
      await tester.enterText(find.byType(TextField), '修改后的下学期');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await waitForSheetClosed(tester);
      expect(find.byType(SemesterEditSheet), findsNothing);
      expect(find.text('修改后的下学期'), findsOneWidget);
      final current = await container
          .read(semesterRepositoryProvider)
          .getActiveSemester();
      expect(current!.id, 'old');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('创建并激活失败保留编辑页和旧学期并显示失败', (tester) async {
    await tester.runAsync(() async {
      await openSemesters(tester);
      final before = await snapshot();
      await database.customStatement('''
        CREATE TRIGGER fail_activation BEFORE UPDATE OF is_active ON semesters
        WHEN NEW.is_active = 1
        BEGIN SELECT RAISE(ABORT, 'forced activation failure'); END;
      ''');
      await tester.tap(find.byTooltip('添加学期'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '新学期');
      await tester.pump();
      await tester.tap(find.text('创建'));
      await waitForFailure(tester, '保存失败');
      expect(tester.takeException(), isNull);
      expect(find.byType(SemesterEditSheet), findsOneWidget);
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(await snapshot(), before);
      expect((await container.read(activeSemesterProvider.future))?.id, 'old');
    });
  });

  testWidgets('删除失败保留编辑页与数据并显示失败', (tester) async {
    await tester.runAsync(() async {
      await openSemesters(tester);
      final before = await snapshot();
      await database.customStatement('''
        CREATE TRIGGER fail_delete BEFORE DELETE ON semesters
        BEGIN SELECT RAISE(ABORT, 'forced delete failure'); END;
      ''');
      await tester.tap(find.text('旧学期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除学期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await waitForFailure(tester, '删除失败');
      expect(tester.takeException(), isNull);
      expect(find.byType(SemesterEditSheet), findsOneWidget);
      expect(find.textContaining('删除失败'), findsOneWidget);
      expect(await snapshot(), before);
    });
  });

  // 非周一开学时结束日期 = 开学日所在周的周一 + 18*7-1 天。
  // 周二这一例在 UTC 下能卡住旧公式（startDate + 18*7-1 天），但在有夏令时
  // 的时区里 125*24 小时会把日期挪回前一天，旧实现也会显示 2027-01-03；
  // 周四这一例在旧公式下任何时区都至少多出 2 天（本机 PST 下为 2027-01-05），
  // 因此它是唯一与时区无关的回归判别。
  for (final (start, expectedRange) in [
    (DateTime(2026, 9, 1), '2026-09-01 ~ 2027-01-03'),
    (DateTime(2026, 9, 3), '2026-09-03 ~ 2027-01-03'),
  ]) {
    testWidgets(
      '非周一开学（${start.month}月${start.day}日）时卡片按最后一周的周日显示结束日期',
      (tester) async {
        await tester.runAsync(() async {
          await container.read(semesterRepositoryProvider).upsert(
                Semester(
                  id: 'non-monday',
                  name: '非周一开学学期',
                  startDate: start,
                  totalWeeks: 18,
                ),
              );
          await openSemesters(tester);
          expect(find.text(expectedRange), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      },
    );
  }

  testWidgets('保存学期后列表显示新名称删除最后学期后立即显示默认学期', (tester) async {
    await tester.runAsync(() async {
      await openSemesters(tester);
      await tester.tap(find.text('旧学期'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '改名后学期');
      await tester.tap(find.text('保存'));
      await waitForSheetClosed(tester);
      expect(find.byType(SemesterEditSheet), findsNothing);
      expect(find.text('改名后学期'), findsOneWidget);
      expect(find.text('旧学期'), findsNothing);
      await tester.tap(find.text('改名后学期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除学期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await waitForSheetClosed(tester);
      expect(find.byType(SemesterEditSheet), findsNothing);
      expect(find.text('改名后学期'), findsNothing);
      expect(find.text('我的学期'), findsOneWidget);
      expect(find.text('当前'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
