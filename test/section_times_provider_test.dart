import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/core/constants/app_constants.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';
import 'package:hormone/features/settings/domain/section_time_shift.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('启动后立即修改单节时长不会覆盖尚未加载的其他节次', () async {
    SharedPreferences.setMockInitialValues({
      'custom_section_times_v2': List.generate(
        AppConstants.maxSections,
        (i) => i == 0 ? '09:00,50' : '10:10,90',
      ),
    });
    final notifier = SectionTimesNotifier();
    addTearDown(notifier.dispose);

    await notifier.setSectionDuration(2, 60);
    await pumpEventQueue();

    expect(notifier.state[1]?.timeRange, '09:00-09:50');
    expect(notifier.state[2]?.timeRange, '10:10-11:10');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('custom_section_times_v2')?[0], '09:00,50');
    expect(prefs.getStringList('custom_section_times_v2')?[1], '10:10,60');
  });

  test('顺延保存期间恢复默认时按操作顺序保留默认时间表', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = SectionTimesNotifier();
    addTearDown(notifier.dispose);
    await pumpEventQueue();

    final shifting = notifier.shiftFromFirstStart('08:30');
    final resetting = notifier.resetToDefault();
    await Future.wait([shifting, resetting]);

    expect(notifier.state[1]?.startTime, '08:00');
    expect(notifier.state[2]?.startTime, '08:55');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('custom_section_times_v2'), isFalse);
  });

  test('顺延保存期间应用模板时最后选择的模板生效', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = SectionTimesNotifier();
    addTearDown(notifier.dispose);
    await pumpEventQueue();

    final shifting = notifier.shiftFromFirstStart('08:30');
    final applying = notifier.applyTemplate(sectionTimeTemplates[1]);
    await Future.wait([shifting, applying]);

    expect(notifier.state[1]?.timeRange, '08:00-09:30');
    expect(notifier.state[2]?.timeRange, '09:45-11:15');
    expect(notifier.state[7]?.startTime, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('custom_section_times_v2')?[1], '09:45,90');
  });

  test('连续顺延和单节编辑按调用顺序应用，不丢失最后一次编辑', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = SectionTimesNotifier();
    addTearDown(notifier.dispose);
    await pumpEventQueue();

    final shifting = notifier.shiftFromFirstStart('08:30');
    final editing = notifier.setSectionStart(2, '10:00');
    final duration = notifier.setSectionDuration(2, 60);
    await Future.wait([shifting, editing, duration]);

    expect(notifier.state[1]?.startTime, '08:30');
    expect(notifier.state[2]?.timeRange, '10:00-11:00');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('custom_section_times_v2')?[1], '10:00,60');
  });

  test('跨天拒绝后仍可继续成功顺延、应用模板并再次顺延', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = SectionTimesNotifier();
    addTearDown(notifier.dispose);

    await expectLater(
      notifier.shiftFromFirstStart('23:00'),
      throwsA(isA<SectionTimeShiftException>()),
    );
    await notifier.shiftFromFirstStart('08:30');
    expect(notifier.state[2]?.startTime, '09:25');

    for (final template in sectionTimeTemplates) {
      await notifier.applyTemplate(template);
      await notifier.shiftFromFirstStart('07:30');
      expect(notifier.state[1]?.startTime, '07:30');
      expect(notifier.state[1]?.durationMinutes, template.duration);
      expect(notifier.state[16]?.startTime, isEmpty);
    }

    final reopened = SectionTimesNotifier();
    addTearDown(reopened.dispose);
    await pumpEventQueue();
    expect(reopened.state[1]?.timeRange, '07:30-08:20');
    expect(reopened.state[2]?.timeRange, '08:25-09:15');
  });

  test('顺延等待已保存配置加载，整批持久化且重启后保留', () async {
    SharedPreferences.setMockInitialValues({
      'custom_section_times_v2': List.generate(
        AppConstants.maxSections,
        (i) => switch (i) {
          0 => '09:00,50',
          1 => '10:10,90',
          4 => '14:00,45',
          _ => ',45',
        },
      ),
    });
    final notifier = SectionTimesNotifier();
    // 不等待加载：应基于已保存的 09:00，而不是启动瞬间的默认 08:00。
    await notifier.shiftFromFirstStart('09:30');
    expect(notifier.state[1]?.timeRange, '09:30-10:20');
    expect(notifier.state[2]?.timeRange, '10:40-12:10');
    expect(notifier.state[5]?.startTime, '14:30');
    expect(notifier.state[13]?.startTime, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('custom_section_times_v2')!;
    expect(saved, hasLength(16));
    expect(saved[0], '09:30,50');
    expect(saved[1], '10:40,90');
    notifier.dispose();

    final reopened = SectionTimesNotifier();
    await pumpEventQueue();
    expect(reopened.state[2]?.timeRange, '10:40-12:10');
    expect(reopened.state[5]?.startTime, '14:30');
    reopened.dispose();
  });

  test('跨天失败不修改状态或覆盖已保存的时间表', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = SectionTimesNotifier();
    await pumpEventQueue();
    await notifier.shiftFromFirstStart('08:30');
    final before = notifier.state;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('custom_section_times_v2');

    await expectLater(
      notifier.shiftFromFirstStart('23:00'),
      throwsA(isA<SectionTimeShiftException>()),
    );
    expect(notifier.state, same(before));
    expect(prefs.getStringList('custom_section_times_v2'), saved);
    notifier.dispose();
  });

  test('已保存的 12 节新版配置升级后补齐到 16 节', () async {
    final stored = List.generate(12, (i) => '0${i % 9}:00,${45 + i}');
    SharedPreferences.setMockInitialValues({'custom_section_times_v2': stored});

    final notifier = SectionTimesNotifier();
    await pumpEventQueue();

    expect(AppConstants.maxSections, 16);
    expect(notifier.state, hasLength(16));
    expect(notifier.state[1]?.startTime, '00:00');
    expect(notifier.state[12]?.durationMinutes, 56);
    expect(notifier.state[13]?.startTime, isEmpty);
    expect(notifier.state[16]?.startTime, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('custom_section_times_v2'),
      hasLength(AppConstants.maxSections),
    );
    notifier.dispose();
  });

  test('仅保存开始时间的旧版 12 节配置也会保留', () async {
    final stored = List.generate(12, (i) => '${i + 7}:30');
    SharedPreferences.setMockInitialValues({'custom_section_times': stored});

    final notifier = SectionTimesNotifier();
    await pumpEventQueue();

    expect(notifier.state, hasLength(16));
    expect(notifier.state[1]?.startTime, '7:30');
    expect(notifier.state[12]?.startTime, '18:30');
    expect(notifier.state[12]?.durationMinutes, 45);
    expect(notifier.state[13]?.startTime, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('custom_section_times'), isFalse);
    expect(prefs.getStringList('custom_section_times_v2'), hasLength(16));
    notifier.dispose();
  });
}
