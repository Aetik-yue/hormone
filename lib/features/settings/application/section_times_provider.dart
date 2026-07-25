import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/core/constants/app_constants.dart';

/// 节次时间自定义 Provider。
/// 持久化到 SharedPreferences，未自定义时使用 [AppConstants.sectionStartTimes] 默认值。
final sectionTimesProvider =
    StateNotifierProvider<SectionTimesNotifier, Map<int, String>>((ref) {
  return SectionTimesNotifier();
});

class SectionTimesNotifier extends StateNotifier<Map<int, String>> {
  static const _prefKey = 'custom_section_times';

  SectionTimesNotifier() : super(AppConstants.sectionStartTimes) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefKey);
    if (stored != null && stored.length == AppConstants.maxSections) {
      final map = <int, String>{};
      for (var i = 0; i < stored.length; i++) {
        map[i + 1] = stored[i];
      }
      state = map;
    }
  }

  /// 更新某一节的开始时间。
  Future<void> setSectionTime(int section, String time) async {
    final updated = Map<int, String>.from(state);
    updated[section] = time;
    state = updated;
    await _persist(updated);
  }

  /// 批量更新全部节次时间。
  Future<void> setAllTimes(Map<int, String> times) async {
    state = times;
    await _persist(times);
  }

  /// 恢复默认时间表。
  Future<void> resetToDefault() async {
    state = AppConstants.sectionStartTimes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  Future<void> _persist(Map<int, String> times) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List.generate(
      AppConstants.maxSections,
      (i) => times[i + 1] ?? '',
    );
    await prefs.setStringList(_prefKey, list);
  }
}
