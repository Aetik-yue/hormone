import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'package:recess/core/constants/app_constants.dart';
import 'package:recess/core/utils/week_calculator.dart';
import 'package:recess/data/providers/database_providers.dart';
import 'package:recess/features/course/domain/course_clock.dart';
import 'package:recess/features/settings/application/section_times_provider.dart';

/// Android 桌面小组件的 Dart 桥接层。
///
/// 预先算出「从今天到学期结束」的全部课次，连同逐日教学周映射一起
/// 写给原生侧，由原生侧按当前本地时间挑选今天还没结束的课次。
/// 刷新由 main.dart 的 _AppEffects 集中触发。
///
/// 写入的键：
/// - `occurrences`：课次列表 JSON，按日期、开始时刻、开始节次排序。
/// - `semester_days`：`{date, week}` 逐日列表，`week` 为 0 表示不在教学周内。
/// - `widget_loaded`：是否曾成功写入过数据，供原生区分「从未加载」与
///   「已加载但没有课次」。
///
/// 旧键 `widget_title` / `courses` 不再写入。原生侧模板见仓库
/// `native_templates/`，整合步骤见 `WIDGET_SETUP.md`。
class WidgetService {
  static const _androidWidgetNames = [
    'CourseWidgetProvider',
    'CourseWidget3x2Provider',
    'CourseWidget2x3Provider',
    'CourseWidget4x2Provider',
    'CourseWidget4x4Provider',
  ];
  static const _keyOccurrences = 'occurrences';
  static const _keySemesterDays = 'semester_days';
  static const _keyLoaded = 'widget_loaded';

  final Ref _ref;

  /// 注入的「现在」。生产环境使用系统时间，测试注入固定时刻。
  final DateTime Function() _now;

  /// 防抖定时器：课表数据变更时会连发多次流事件，合并为一次刷新。
  Timer? _debounce;

  WidgetService(this._ref, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// 课表/节次/当前周变化后集中触发的刷新入口。
  ///
  /// 用短防抖合并一条打印链路上连续发射的多次流事件（切换学期、批量导入、
  /// 恢复备份都会同时波及多个 provider），避免对原生小组件反复写数据。
  /// 实际写数据时仍通过 [_now] 取时间，与直接调用 [updateWidget] 一致。
  void scheduleUpdate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      updateWidget();
    });
  }

  /// 计算并写入从今天到学期结束的课次与逐日教学周，然后刷新 UI。
  ///
  /// 失败时不抛出（小组件是加分项，不应影响主流程）。
  Future<void> updateWidget() async {
    try {
      final semesterRepo = _ref.read(semesterRepositoryProvider);
      final semester = await semesterRepo.getActiveSemester();
      if (semester == null) return;

      final courseRepo = _ref.read(courseRepositoryProvider);
      final all = await courseRepo.getCourses(semester.id);
      final sectionTimes = _ref.read(sectionTimesProvider);
      final now = _now();
      final today = DateTime(now.year, now.month, now.day);
      final normalized = normalizeSemesterWeeks(semester);
      final semesterEnd = lastSemesterDay(normalized);
      final courseClocks = {
        for (final course in all) course.id: CourseClock(course, sectionTimes),
      };

      // 课次按「该日期属于哪个教学周」生成：原生端只按日期查表，
      // 不重新实现周次规则；week 0 表示不在教学周内。手动当前周时，
      // 未来每个日期都属于同一周，因此该周的课程会出现在每个匹配日期上。
      final days = <Map<String, Object?>>[];
      final occurrences = <_Occurrence>[];
      for (
        var date = today;
        !date.isAfter(semesterEnd);
        date = DateTime(date.year, date.month, date.day + 1)
      ) {
        final week = teachingWeekOf(normalized, date);
        days.add({'date': _formatDate(date), 'week': week ?? 0});
        if (week == null) continue;

        for (final course in all) {
          if (course.dayOfWeek != date.weekday) continue;
          if (!course.weeks.contains(week)) continue;
          final clock = courseClocks[course.id]!;
          final start = clock.start;
          final end = clock.end;
          occurrences.add(
            _Occurrence(
              courseId: course.id,
              date: date,
              start:
                  start == null
                      ? null
                      : DateTime(
                        date.year,
                        date.month,
                        date.day,
                        start.$1,
                        start.$2,
                      ),
              end:
                  end == null
                      ? null
                      : DateTime(
                        date.year,
                        date.month,
                        date.day,
                        end.$1,
                        end.$2,
                      ),
              startSection: course.startSection,
              endSection: course.endSection,
              name: course.name,
              location: course.location ?? '',
              color: AppConstants.courseDisplayColor(course.colorValue),
              colorDark: AppConstants.courseDisplayColor(
                course.colorValue,
                dark: true,
              ),
            ),
          );
        }
      }
      occurrences.sort(_compareOccurrences);

      await HomeWidget.saveWidgetData(
        _keyOccurrences,
        jsonEncode([for (final occurrence in occurrences) occurrence.toJson()]),
      );
      await HomeWidget.saveWidgetData(_keySemesterDays, jsonEncode(days));
      await HomeWidget.saveWidgetData(_keyLoaded, true);
      for (final name in _androidWidgetNames) {
        try {
          await HomeWidget.updateWidget(androidName: name);
        } catch (_) {
          // 一个尺寸刷新失败时，继续通知其余尺寸。
        }
      }
    } catch (_) {
      // 忽略：小组件刷新失败不影响主 App。
    }
  }
}

/// 预先算好的一条课次。同一门课在不同周次会产生不同的 [_Occurrence]。
class _Occurrence {
  final String courseId;
  final DateTime date;
  final DateTime? start;
  final DateTime? end;
  final int startSection;
  final int endSection;
  final String name;
  final String location;
  final int color;
  final int colorDark;

  const _Occurrence({
    required this.courseId,
    required this.date,
    required this.start,
    required this.end,
    required this.startSection,
    required this.endSection,
    required this.name,
    required this.location,
    required this.color,
    required this.colorDark,
  });

  Map<String, Object> toJson() => {
    'date': _formatDate(date),
    'start': start == null ? '' : _formatDateTime(start!),
    'end': end == null ? '' : _formatDateTime(end!),
    'start_section': startSection,
    'end_section': endSection,
    'name': name,
    'location': location,
    'color': color,
    'color_dark': colorDark,
  };
}

/// 先按日期，再按开始时刻（缺失的开始时刻排在同一天最后），
/// 同一开始时刻按开始节次、结束节次和课程名排序，最后用课程 id 保证稳定。
int _compareOccurrences(_Occurrence a, _Occurrence b) {
  final byDate = a.date.compareTo(b.date);
  if (byDate != 0) return byDate;

  final aStart = a.start;
  final bStart = b.start;
  if (aStart != null && bStart != null) {
    final byStart = aStart.compareTo(bStart);
    if (byStart != 0) return byStart;
  } else if (aStart != null) {
    return -1;
  } else if (bStart != null) {
    return 1;
  }

  final bySection = a.startSection.compareTo(b.startSection);
  if (bySection != 0) return bySection;
  final byEndSection = a.endSection.compareTo(b.endSection);
  if (byEndSection != 0) return byEndSection;
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  return a.courseId.compareTo(b.courseId);
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _formatDateTime(DateTime dateTime) =>
    '${_formatDate(dateTime)}T'
    '${dateTime.hour.toString().padLeft(2, '0')}:'
    '${dateTime.minute.toString().padLeft(2, '0')}';

/// 全局单例 Provider，刷新由 main.dart 的 _AppEffects 集中触发。
final widgetServiceProvider = Provider<WidgetService>((ref) {
  return WidgetService(ref);
});
