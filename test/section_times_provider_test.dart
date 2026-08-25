import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/core/constants/app_constants.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('已保存的 12 节新版配置升级后补齐到 16 节', () async {
    final stored = List.generate(12, (i) => '0${i % 9}:00,${45 + i}');
    SharedPreferences.setMockInitialValues({
      'custom_section_times_v2': stored,
    });

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
    SharedPreferences.setMockInitialValues({
      'custom_section_times': stored,
    });

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
