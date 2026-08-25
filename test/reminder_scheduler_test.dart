import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/features/notification/application/reminder_scheduler.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';

void main() {
  // 开学日为 2026-09-01（周二），第 1 周为 8-31(一) ~ 9-6(日)。
  final semester = Semester(
    id: 's',
    name: '2026 秋',
    startDate: _sep1,
    totalWeeks: 18,
  );

  final sectionTimes = {
    1: const SectionTime('08:00', 45),
    2: const SectionTime('08:55', 45),
    3: const SectionTime('10:00', 45),
    4: const SectionTime('10:55', 45),
  };

  // 周一 1-2 节，全学期：对应第 1 周周一 = 2026-08-31 08:00。
  Course makeM1() => const Course(
        id: 'c1',
        semesterId: 's',
        name: '高等数学',
        dayOfWeek: DateTime.monday,
        startSection: 1,
        endSection: 2,
        weeks: [1, 2, 3],
      );

  test('跨天计算触发时间并扣除提前量', () {
    final now = DateTime(2026, 8, 30); // 开课前一天
    final reminders = computeReminders(
      courses: [makeM1()],
      semester: semester,
      sectionTimes: sectionTimes,
      now: now,
      leadMinutes: 10,
      horizonDays: 20, // 覆盖第 1/2/3 周的全部三次上课
    );

    // 第 1 周周一 08:00 - 10 分钟 = 2026-08-31 07:50
    expect(reminders, hasLength(3));
    expect(reminders.first.trigger, DateTime(2026, 8, 31, 7, 50));
    expect(reminders.first.title, '高等数学');
    expect(reminders.first.body, contains('周一'));
  });

  test('已过期的触发时间被过滤', () {
    final now = DateTime(2026, 8, 31, 8, 0); // 第 1 周周一已开课
    final reminders = computeReminders(
      courses: [makeM1()],
      semester: semester,
      sectionTimes: sectionTimes,
      now: now,
      leadMinutes: 10,
      horizonDays: 20,
    );
    // 第 1 周触发时间是 07:50，已在 now 之前 → 只剩第 2、3 周。
    expect(reminders, hasLength(2));
    expect(reminders.first.trigger, DateTime(2026, 9, 7, 7, 50));
  });

  test('超过 horizon 的提醒被截断', () {
    final now = DateTime(2026, 8, 30);
    final reminders = computeReminders(
      courses: [makeM1()],
      semester: semester,
      sectionTimes: sectionTimes,
      now: now,
      leadMinutes: 10,
      horizonDays: 2, // 只到 09-01
    );
    // 第 1 周周一 08-31 在 horizon 内，第 2 周周一 09-07 超出。
    expect(reminders, hasLength(1));
  });

  test('优先使用课程自带 startTime，缺省回退节次时间表', () {
    final withTime = const Course(
      id: 'c2',
      semesterId: 's',
      name: '线性代数',
      dayOfWeek: DateTime.tuesday,
      startSection: 3,
      endSection: 4,
      startTime: '09:30',
      weeks: [1],
    );
    final now = DateTime(2026, 8, 30);
    final reminders = computeReminders(
      courses: [withTime],
      semester: semester,
      sectionTimes: sectionTimes,
      now: now,
      leadMinutes: 5,
      horizonDays: 7,
    );
    // 第 1 周周二 09:30 - 5 分钟；节次表第 3 节是 10:00，不能影响它。
    expect(reminders.single.trigger, DateTime(2026, 9, 1, 9, 25));
  });

  test('钟点信息缺失的课程不安排提醒', () {
    final noTime = const Course(
      id: 'c3',
      semesterId: 's',
      name: '无时间课',
      dayOfWeek: DateTime.friday,
      startSection: 10, // 节次表没有第 10 节
      endSection: 10,
      weeks: [1],
    );
    final reminders = computeReminders(
      courses: [noTime],
      semester: semester,
      sectionTimes: sectionTimes,
      now: DateTime(2026, 8, 30),
      leadMinutes: 10,
      horizonDays: 7,
    );
    expect(reminders, isEmpty);
  });

  test('结果按触发时间升序', () {
    // 两门不同星期的课 + 同一课程多周次，验证整体排序。
    final mon = makeM1();
    final tue = const Course(
      id: 'c4',
      semesterId: 's',
      name: '周二课',
      dayOfWeek: DateTime.tuesday,
      startSection: 1,
      endSection: 1,
      weeks: [1],
    );
    final reminders = computeReminders(
      courses: [tue, mon],
      semester: semester,
      sectionTimes: sectionTimes,
      now: DateTime(2026, 8, 30),
      leadMinutes: 0,
      horizonDays: 7,
    );
    for (var i = 1; i < reminders.length; i++) {
      expect(
        reminders[i].trigger.isAfter(reminders[i - 1].trigger),
        isTrue,
      );
    }
  });
}

final DateTime _sep1 = DateTime(2026, 9, 1);
