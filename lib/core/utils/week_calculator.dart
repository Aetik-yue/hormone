/// 周次与时间计算工具（纯函数，便于单测）。
///
/// 约定：dayOfWeek 1=周一 .. 7=周日，与 [DateTime.weekday] 一致。

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

/// 返回某学期第 [week] 周、星期 [weekday] 的日期。
DateTime dateForWeekday(DateTime semesterStart, int week, int weekday) {
  assert(week >= 1, 'week must be >= 1, got $week');
  assert(weekday >= 1 && weekday <= 7, 'weekday must be 1..7, got $weekday');
  // 开学第 1 周的周一
  final firstMonday =
      semesterStart.subtract(Duration(days: semesterStart.weekday - 1));
  return firstMonday.add(Duration(days: (week - 1) * 7 + (weekday - 1)));
}

/// 判断课程在指定周是否上课。
bool courseOnWeek(List<int> weeks, int week) => weeks.contains(week);
