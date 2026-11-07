/// 周次与时间计算工具（纯函数，便于单测）。
///
/// 约定：dayOfWeek 1=周一 .. 7=周日，与 [DateTime.weekday] 一致。
library;

import 'package:recess/core/models/semester.dart';

/// 沿用学期编辑范围，保留手动模式并将覆盖值调整到最近合法周。
Semester normalizeSemesterWeeks(Semester semester) {
  final totalWeeks = semester.totalWeeks.clamp(1, 30);
  return semester.copyWith(
    totalWeeks: totalWeeks,
    currentWeekOverride: semester.currentWeekOverride?.clamp(1, totalWeeks),
  );
}

/// 把周次钳制到 `1..totalWeeks`；[totalWeeks] 小于 1 时按 1 周处理。
int clampWeek(int week, int totalWeeks) {
  final lastWeek = totalWeeks < 1 ? 1 : totalWeeks;
  return week < 1 ? 1 : (week > lastWeek ? lastWeek : week);
}

/// 根据开学日期与今天推算当前周（1-based）。早于开学返回 0。
int computeCurrentWeek(DateTime startDate, DateTime today) {
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final t = DateTime(today.year, today.month, today.day);
  // Align to Monday-based weeks, consistent with dateForWeekday.
  final firstMonday = start.subtract(Duration(days: start.weekday - 1));
  final days = t.difference(firstMonday).inDays;
  if (days < 0) return 0;
  return (days ~/ 7) + 1;
}

/// 学期的当前周：手动覆盖调整到合法周，否则保留日期推算的原始周数。
/// 主页标题、今天高亮、初始查看周与「今日课程」都以它为准。
int currentWeekOf(Semester semester, DateTime today) =>
    normalizeSemesterWeeks(semester).currentWeekOverride ??
    computeCurrentWeek(semester.startDate, today);

/// 有效教学当前周；自动推算在学期外时没有当前教学周。
int? teachingWeekOf(Semester semester, DateTime today) {
  final week = currentWeekOf(semester, today);
  return week >= 1 && week <= semester.totalWeeks ? week : null;
}

/// 返回某学期第 [week] 周、星期 [weekday] 的日期。
DateTime dateForWeekday(DateTime semesterStart, int week, int weekday) {
  assert(week >= 1, 'week must be >= 1, got $week');
  assert(weekday >= 1 && weekday <= 7, 'weekday must be 1..7, got $weekday');
  // 开学第 1 周的周一
  final firstMonday =
      semesterStart.subtract(Duration(days: semesterStart.weekday - 1));
  return firstMonday.add(Duration(days: (week - 1) * 7 + (weekday - 1)));
}

/// 学期最后一个教学周的周日。
///
/// 与 [computeCurrentWeek] 一样把开学日所在周对齐到周一；随后按日历日
/// 向前推算，避免夏令时下 24 小时时长把日期挪到前一天。
DateTime lastSemesterDay(Semester semester) {
  final normalized = normalizeSemesterWeeks(semester);
  final start = normalized.startDate;
  final firstMonday = DateTime(
    start.year,
    start.month,
    start.day - (start.weekday - 1),
  );
  return DateTime(
    firstMonday.year,
    firstMonday.month,
    firstMonday.day + normalized.totalWeeks * 7 - 1,
  );
}

/// 判断课程在指定周是否上课。
bool courseOnWeek(List<int> weeks, int week) => weeks.contains(week);
