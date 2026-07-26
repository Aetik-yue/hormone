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
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
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

  SectionTimesNotifier() : super(_defaultMap()) {
    _load();
  }

  static Map<int, SectionTime> _defaultMap() => {
        for (var i = 1; i <= AppConstants.maxSections; i++)
          i: SectionTime(
              AppConstants.sectionStartTimes[i] ?? '', AppConstants.defaultSectionDuration),
      };

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefKey);
    if (stored != null && stored.length == AppConstants.maxSections) {
      try {
        final map = <int, SectionTime>{};
        for (var i = 0; i < stored.length; i++) {
          final parts = stored[i].split(',');
          final start = parts[0];
          final duration = parts.length == 2 ? int.tryParse(parts[1]) ?? AppConstants.defaultSectionDuration : AppConstants.defaultSectionDuration;
          map[i + 1] = SectionTime(start, duration);
        }
        state = map;
      } catch (_) {
        // 解析失败时使用默认值
      }
    }
  }

  /// 更新某一节的开始时间。
  Future<void> setSectionStart(int section, String time) async {
    final current = state[section] ?? SectionTime(time, AppConstants.defaultSectionDuration);
    final updated = Map<int, SectionTime>.from(state);
    updated[section] = SectionTime(time, current.durationMinutes);
    state = updated;
    await _persist(updated);
  }

  /// 更新某一节的时长。
  Future<void> setSectionDuration(int section, int minutes) async {
    final current = state[section] ?? SectionTime('', minutes);
    final updated = Map<int, SectionTime>.from(state);
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
