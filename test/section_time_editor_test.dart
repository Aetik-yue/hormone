import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/features/settings/application/section_times_provider.dart';
import 'package:hormone/features/settings/presentation/section_time_editor.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> openEditor(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SectionTimeEditor())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> pickStart(
    WidgetTester tester,
    int section,
    String hour,
    String minute,
  ) async {
    await tester.tap(find.byKey(ValueKey('section-start-$section')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), hour);
    await tester.enterText(fields.at(1), minute);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('默认开启同步，修改第一节立即更新后续节次和结束时间', (tester) async {
    final container = await openEditor(tester);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );

    await pickStart(tester, 1, '08', '30');

    final times = container.read(sectionTimesProvider);
    expect(times[1]?.startTime, '08:30');
    expect(times[2]?.startTime, '09:25');
    expect(times[5]?.startTime, '14:30');
    expect(times[13]?.startTime, isEmpty);
    expect(find.text('09:25'), findsOneWidget);
    expect(find.text('→ 10:10'), findsOneWidget);
  });

  testWidgets('关闭同步后只修改第一节，再开启时保留当前间隔', (tester) async {
    final container = await openEditor(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await pickStart(tester, 1, '08', '10');
    expect(container.read(sectionTimesProvider)[2]?.startTime, '08:55');

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await pickStart(tester, 1, '08', '30');
    expect(container.read(sectionTimesProvider)[2]?.startTime, '09:15');
  });

  testWidgets('同步开关不影响其他节次的单独编辑', (tester) async {
    final container = await openEditor(tester);
    await pickStart(tester, 2, '09', '10');

    final times = container.read(sectionTimesProvider);
    expect(times[1]?.startTime, '08:00');
    expect(times[2]?.startTime, '09:10');
    expect(times[3]?.startTime, '10:00');
  });

  testWidgets('取消时间选择不改变课表', (tester) async {
    final container = await openEditor(tester);
    final before = container.read(sectionTimesProvider);
    await tester.tap(find.byKey(const ValueKey('section-start-1')));
    await tester.pumpAndSettle();
    expect(find.text('调整第一节并同步顺延'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(sectionTimesProvider), same(before));
  });

  testWidgets('跨天时显示原因并保留整张时间表', (tester) async {
    final container = await openEditor(tester);
    final before = container.read(sectionTimesProvider);
    await pickStart(tester, 1, '23', '00');

    expect(find.text('无法同步顺延'), findsOneWidget);
    expect(find.textContaining('超出当天'), findsOneWidget);
    expect(container.read(sectionTimesProvider), same(before));
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('08:00'), findsOneWidget);
  });
}
