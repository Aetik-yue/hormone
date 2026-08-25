import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/core/utils/week_calculator.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';

/// 一条待安排的课前提醒。
class PendingReminder {
  final int id;
  final DateTime trigger; // 本地时间，已扣除提前量
  final String title;
  final String body;

  const PendingReminder({
    required this.id,
    required this.trigger,
    required this.title,
    required this.body,
  });
}

/// 计算未来 [horizonDays] 天内需要安排的上课提醒（纯函数，可单测）。
///
/// 规则：
/// - 每门课的每一周次 × 对应星期生成一个触发时间 = 上课钟点 - leadMinutes。
/// - 上课钟点优先取 [Course.startTime]（WebView 导入已补全），缺省回退到
///   节次时间表 [sectionTimes]。
/// - 只保留触发时间在 [now, now + horizonDays] 之间的提醒。
/// - 结果按触发时间升序，id 由调用方分配（重排前会 cancelAll，无需跨批稳定）。
List<PendingReminder> computeReminders({
  required List<Course> courses,
  required Semester semester,
  required Map<int, SectionTime> sectionTimes,
  required DateTime now,
  required int leadMinutes,
  int horizonDays = 7,
}) {
  final horizonEnd = now.add(Duration(days: horizonDays));
  final reminders = <PendingReminder>[];
  var id = 0;

  for (final course in courses) {
    final clock = _courseStartClock(course, sectionTimes);
    if (clock == null) continue; // 无钟点信息的课（未填时间且节次未设置）不提醒
    final (hour, minute) = clock;

    for (final week in course.weeks) {
      final date = dateForWeekday(semester.startDate, week, course.dayOfWeek);
      final start = DateTime(date.year, date.month, date.day, hour, minute);
      final trigger = start.subtract(Duration(minutes: leadMinutes));
      if (trigger.isBefore(now) || trigger.isAfter(horizonEnd)) continue;

      reminders.add(PendingReminder(
        id: id++,
        trigger: trigger,
        title: course.name,
        body: _body(course),
      ));
    }
  }

  reminders.sort((a, b) => a.trigger.compareTo(b.trigger));
  return reminders;
}

/// 返回课程的开始钟点 (时, 分)；无钟点信息返回 null。
(int, int)? _courseStartClock(
  Course course,
  Map<int, SectionTime> sectionTimes,
) {
  final raw = course.startTime ??
      (course.startSection > 0 ? sectionTimes[course.startSection]?.startTime : null);
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return (h, m);
}

String _body(Course course) {
  final day = course.dayOfWeek >= 1 && course.dayOfWeek <= 7
      ? '周${_dayLabels[course.dayOfWeek - 1]}'
      : '';
  final withLocation =
      course.location != null && course.location!.isNotEmpty
          ? ' · ${course.location}'
          : '';
  return '$day 第${course.startSection}-${course.endSection}节$withLocation';
}

const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];