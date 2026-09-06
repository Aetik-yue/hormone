import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/core/constants/app_constants.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';
import 'package:hormone/features/settings/domain/section_time_shift.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
