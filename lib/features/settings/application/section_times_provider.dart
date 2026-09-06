import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/core/constants/app_constants.dart';
import '../domain/section_time.dart';
import '../domain/section_time_shift.dart';

// 保持现有调用方的模型导入路径兼容。
export '../domain/section_time.dart';

/// 节次时间预设模板。
class SectionTimeTemplate {
  final String name;
  final int duration;
  final Map<int, String> startTimes;

  const SectionTimeTemplate({
    required this.name,
    required this.duration,
    required this.startTimes,
  });
}

/// 常用节次时间模板。
const List<SectionTimeTemplate> sectionTimeTemplates = [
  SectionTimeTemplate(
    name: '标准 45 分钟制',
    duration: 45,
    startTimes: {
      1: '08:00',
      2: '08:55',
      3: '10:00',
      4: '10:55',
      5: '14:00',
      6: '14:55',
      7: '16:00',
      8: '16:55',
      9: '19:00',
      10: '19:55',
      11: '20:50',
      12: '21:45',
    },
  ),
  SectionTimeTemplate(
    name: '90 分钟大节课制',
    duration: 90,
    startTimes: {
      1: '08:00',
      2: '09:45',
      3: '14:00',
      4: '15:45',
      5: '19:00',
      6: '20:45',
    },
  ),
  SectionTimeTemplate(
    name: '50 分钟制',
    duration: 50,
    startTimes: {
      1: '08:00',
      2: '08:55',
      3: '10:00',
      4: '10:55',
      5: '14:00',
      6: '14:55',
      7: '16:00',
      8: '16:55',
      9: '19:00',
      10: '19:55',
    },
  ),
];

/// 节次时间自定义 Provider。
/// 持久化到 SharedPreferences，未自定义时使用默认值。
final sectionTimesProvider =
    StateNotifierProvider<SectionTimesNotifier, Map<int, SectionTime>>((ref) {
      return SectionTimesNotifier();
    });

class SectionTimesNotifier extends StateNotifier<Map<int, SectionTime>> {
  static const _prefKey = 'custom_section_times_v2';
  static const _oldPrefKey = 'custom_section_times';
  late final Future<void> _ready;

  SectionTimesNotifier() : super(_defaultMap()) {
    _ready = _init();
  }

  static Map<int, SectionTime> _defaultMap() => {
    for (var i = 1; i <= AppConstants.maxSections; i++)
      i: SectionTime(
        AppConstants.sectionStartTimes[i] ?? '',
        AppConstants.defaultSectionDuration,
      ),
  };

  /// 把任意历史长度的配置补齐到当前节次上限，升级时保留用户已有设置。
  static Map<int, SectionTime> _normalizedMap(List<String> stored) {
    final map = _defaultMap();
    final count = stored.length.clamp(0, AppConstants.maxSections);
    for (var i = 0; i < count; i++) {
      final parts = stored[i].split(',');
      final start = parts.first;
      final duration =
          parts.length == 2
              ? int.tryParse(parts[1]) ?? AppConstants.defaultSectionDuration
              : AppConstants.defaultSectionDuration;
      map[i + 1] = SectionTime(start, duration);
    }
    return map;
  }

  Future<void> _init() async {
    await _migrateOldData();
    await _load();
  }

  /// 迁移旧版数据（仅开始时间，无时长）到新版格式。
  Future<void> _migrateOldData() async {
    final prefs = await SharedPreferences.getInstance();
    final oldData = prefs.getStringList(_oldPrefKey);
    if (oldData != null && oldData.isNotEmpty) {
      final map = _normalizedMap(oldData);
      state = map;
      await _persist(map);
      await prefs.remove(_oldPrefKey);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        final map = _normalizedMap(stored);
        state = map;
        if (stored.length != AppConstants.maxSections) {
          await _persist(map);
        }
      } catch (e) {
        // Parsing failed — keep default state
        debugPrint('Failed to parse saved section times: $e');
      }
    }
  }

  /// 更新某一节的开始时间。
  Future<void> setSectionStart(int section, String time) async {
    final updated = Map<int, SectionTime>.from(state);
    final current =
        updated[section] ??
        SectionTime(time, AppConstants.defaultSectionDuration);
    updated[section] = SectionTime(time, current.durationMinutes);
    state = updated;
    await _persist(updated);
  }

  /// 修改第一节开始时间，并一次性保存全部已设置节次的平移结果。
  Future<void> shiftFromFirstStart(String time) async {
    // 等待历史配置读取完成，确保按用户保存的间隔顺延。
    await _ready;
    final updated = shiftSectionTimes(state, time);
    await _persist(updated);
    if (mounted) state = updated;
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

  /// 应用预设模板。
  Future<void> applyTemplate(SectionTimeTemplate template) async {
    final map = <int, SectionTime>{};
    for (var i = 1; i <= AppConstants.maxSections; i++) {
      final start = template.startTimes[i];
      if (start != null) {
        map[i] = SectionTime(start, template.duration);
      } else {
        map[i] = SectionTime('', template.duration);
      }
    }
    state = map;
    await _persist(map);
  }

  /// 恢复默认时间表。
  Future<void> resetToDefault() async {
    state = _defaultMap();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  Future<void> _persist(Map<int, SectionTime> times) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List.generate(AppConstants.maxSections, (i) {
      final t = times[i + 1];
      return t != null ? '${t.startTime},${t.durationMinutes}' : '';
    });
    await prefs.setStringList(_prefKey, list);
  }
}
