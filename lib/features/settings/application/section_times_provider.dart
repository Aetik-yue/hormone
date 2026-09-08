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
  late Future<void> _pendingChange;

  SectionTimesNotifier() : super(_defaultMap()) {
    _pendingChange = _init();
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
      if (mounted) state = map;
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
        if (mounted) state = map;
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
  Future<void> setSectionStart(int section, String time) {
    return _enqueueChange(() async {
      final updated = Map<int, SectionTime>.from(state);
      final current =
          updated[section] ??
          SectionTime(time, AppConstants.defaultSectionDuration);
      updated[section] = SectionTime(time, current.durationMinutes);
      await _persist(updated);
      if (mounted) state = updated;
    });
  }

  /// 修改第一节开始时间，并一次性保存全部已设置节次的平移结果。
  Future<void> shiftFromFirstStart(String time) {
    return _enqueueChange(() async {
      final updated = shiftSectionTimes(state, time);
      await _persist(updated);
      if (mounted) state = updated;
    });
  }

  /// 更新某一节的时长。
  Future<void> setSectionDuration(int section, int minutes) {
    return _enqueueChange(() async {
      final updated = Map<int, SectionTime>.from(state);
      final current = updated[section] ?? SectionTime('', minutes);
      updated[section] = SectionTime(current.startTime, minutes);
      await _persist(updated);
      if (mounted) state = updated;
    });
  }

  /// 批量更新全部节次时间。
  Future<void> setAllTimes(Map<int, SectionTime> times) {
    final updated = Map<int, SectionTime>.from(times);
    return _enqueueChange(() async {
      await _persist(updated);
      if (mounted) state = updated;
    });
  }

  /// 应用预设模板。
  Future<void> applyTemplate(SectionTimeTemplate template) {
    return _enqueueChange(() async {
      final map = <int, SectionTime>{};
      for (var i = 1; i <= AppConstants.maxSections; i++) {
        final start = template.startTimes[i];
        if (start != null) {
          map[i] = SectionTime(start, template.duration);
        } else {
          map[i] = SectionTime('', template.duration);
        }
      }
      await _persist(map);
      if (mounted) state = map;
    });
  }

  /// 恢复默认时间表。
  Future<void> resetToDefault() {
    return _enqueueChange(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
      if (mounted) state = _defaultMap();
    });
  }

  /// 等待历史配置加载，并按调用顺序保存，避免慢写入覆盖后续编辑。
  Future<void> _enqueueChange(Future<void> Function() change) {
    final operation = _pendingChange.then((_) async {
      if (mounted) await change();
    });
    // 错误仍由本次调用返回，但不能阻塞之后的合法修改。
    _pendingChange = operation.catchError((Object _) {});
    return operation;
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
