import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/core/constants/app_constants.dart';

/// 单节课的时间配置：开始时间 + 时长（分钟）。
class SectionTime {
  final String startTime; // "HH:mm"
  final int durationMinutes;

  const SectionTime(this.startTime, this.durationMinutes);

  /// 计算结束时间字符串。
  String get endTime {
    final parts = startTime.split(':');
    if (parts.length != 2) return '';
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return '';
    final total = h * 60 + m + durationMinutes;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// 完整时间范围显示，如 "08:00-08:45"。
  String get timeRange => '$startTime-$endTime';
}

/// 节次时间自定义 Provider。
/// 持久化到 SharedPreferences，未自定义时使用默认值。
final sectionTimesProvider =
    StateNotifierProvider<SectionTimesNotifier, Map<int, SectionTime>>((ref) {
  return SectionTimesNotifier();
});

class SectionTimesNotifier extends StateNotifier<Map<int, SectionTime>> {
  static const _prefKey = 'custom_section_times_v2';
  static const _oldPrefKey = 'custom_section_times';

  SectionTimesNotifier() : super(_defaultMap()) {
    _init();
  }

  static Map<int, SectionTime> _defaultMap() => {
        for (var i = 1; i <= AppConstants.maxSections; i++)
          i: SectionTime(
              AppConstants.sectionStartTimes[i] ?? '', AppConstants.defaultSectionDuration),
      };

  Future<void> _init() async {
    await _migrateOldData();
    await _load();
  }

  /// 迁移旧版数据（仅开始时间，无时长）到新版格式。
  Future<void> _migrateOldData() async {
    final prefs = await SharedPreferences.getInstance();
    final oldData = prefs.getStringList(_oldPrefKey);
    if (oldData != null && oldData.length == AppConstants.maxSections) {
      final map = <int, SectionTime>{};
      for (var i = 0; i < oldData.length; i++) {
        map[i + 1] = SectionTime(oldData[i], AppConstants.defaultSectionDuration);
      }
      state = map;
      await _persist(map);
      await prefs.remove(_oldPrefKey);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefKey);
    if (stored != null && stored.length == AppConstants.maxSections) {
      try {
        final map = <int, SectionTime>{};
        for (var i = 0; i < stored.length; i++) {
          final parts = stored[i].split(',');
          final start = parts[0];
          final duration = parts.length == 2
              ? int.tryParse(parts[1]) ?? AppConstants.defaultSectionDuration
              : AppConstants.defaultSectionDuration;
          map[i + 1] = SectionTime(start, duration);
        }
        state = map;
      } catch (e) {
        // Parsing failed — keep default state
        debugPrint('Failed to parse saved section times: $e');
      }
    }
  }

  /// 更新某一节的开始时间。
  Future<void> setSectionStart(int section, String time) async {
    final updated = Map<int, SectionTime>.from(state);
    final current = updated[section] ?? SectionTime(time, AppConstants.defaultSectionDuration);
    updated[section] = SectionTime(time, current.durationMinutes);
    state = updated;
    await _persist(updated);
  }

  /// 更新某一节的时长。
  Future<void> setSectionDuration(int section, int minutes) async {
    final updated = Map<int, SectionTime>.from(state);
    final current = updated[section] ?? SectionTime('', minutes);
    updated[section] = SectionTime(current.startTime, minutes);
    state = updated;
    await _persist(updated);
  }

  /// 批量更新全部节次时间。
  Future<void> setAllTimes(Map<int, SectionTime> times) async {
    state = times;
    await _persist(times);
  }

  /// 恢复默认时间表。
  Future<void> resetToDefault() async {
    state = _defaultMap();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  Future<void> _persist(Map<int, SectionTime> times) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List.generate(
      AppConstants.maxSections,
      (i) {
        final t = times[i + 1];
        return t != null ? '${t.startTime},${t.durationMinutes}' : '';
      },
    );
    await prefs.setStringList(_prefKey, list);
  }
}
