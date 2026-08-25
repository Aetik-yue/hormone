import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/features/schedule/domain/schedule_helpers.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';

void main() {
  final sectionTimes = {
    1: const SectionTime('08:00', 45),
    2: const SectionTime('08:55', 45),
    3: const SectionTime('10:00', 45),
  };

  Course _c(String id, int day, int start, int end,
          {List<int> weeks = const [1]}) =>
      Course(
        id: id,
        semesterId: 's',
        name: '课$id',
        dayOfWeek: day,
        startSection: start,
        endSection: end,
        weeks: weeks,
      );

  test('只保留当天星期且命中当前周的课程，按起始节次排序', () {
    // now = 周一
    final courses = [
      _c('a', DateTime.monday, 3, 3),
      _c('b', DateTime.monday, 1, 2),
      _c('c', DateTime.tuesday, 1, 1),
      _c('d', DateTime.monday, 5, 5, weeks: const [2]), // 本周无课
    ];
    final slots = todayCourseSlots(
      courses: courses,
      currentWeek: 1,
      now: DateTime(2026, 8, 31, 12, 0),
      sectionTimes: sectionTimes,
    );
    expect(slots.map((s) => s.course.id), ['b', 'a']);
  });

  test('按当前钟点标注 未开始 / 进行中 / 已结束', () {
    final courses = [
      _c('early', DateTime.monday, 1, 1), // 08:00-08:45
      _c('now', DateTime.monday, 2, 2), // 08:55-09:40
      _c('later', DateTime.monday, 3, 3), // 10:00
    ];
    final slots = todayCourseSlots(
      courses: courses,
      currentWeek: 1,
      now: DateTime(2026, 8, 31, 9, 0), // 正在上第 2 节
      sectionTimes: sectionTimes,
    );
    expect(slots[0].status, CourseStatus.done);
    expect(slots[1].status, CourseStatus.ongoing);
    expect(slots[2].status, CourseStatus.upcoming);
  });

  test('课程自带 startTime/endTime 优先于节次时间表', () {
    final course = const Course(
      id: 'x',
      semesterId: 's',
      name: '自定时间',
      dayOfWeek: DateTime.monday,
      startSection: 1,
      endSection: 1,
      startTime: '08:30',
      endTime: '09:00',
      weeks: [1],
    );
    final slots = todayCourseSlots(
      courses: [course],
      currentWeek: 1,
      now: DateTime(2026, 8, 31, 8, 45), // 08:30-09:00 进行中
      sectionTimes: sectionTimes,
    );
    expect(slots.single.status, CourseStatus.ongoing);
  });

  test('无钟点信息的课程状态为未开始（不崩溃）', () {
    final course = const Course(
      id: 'y',
      semesterId: 's',
      name: '无钟点',
      dayOfWeek: DateTime.monday,
      startSection: 10,
      endSection: 10,
      weeks: [1],
    );
    final slots = todayCourseSlots(
      courses: [course],
      currentWeek: 1,
      now: DateTime(2026, 8, 31, 9, 0),
      sectionTimes: sectionTimes,
    );
    expect(slots.single.status, CourseStatus.upcoming);
  });

  test('filterCourses 按名称/教师/教室模糊匹配（不区分大小写）', () {
    final a = const Course(
      id: 'a', semesterId: 's', name: '高等数学', teacher: '张三',
      location: '教三 201', dayOfWeek: 1, startSection: 1, endSection: 1,
    );
    final b = const Course(
      id: 'b', semesterId: 's', name: '线性代数', teacher: '李四',
      location: '教二 105', dayOfWeek: 1, startSection: 1, endSection: 1,
    );
    final filtered = filterCourses([a, b], '代数');
    expect(filtered.map((c) => c.id), ['b']);

    expect(filterCourses([a, b], '教三'), [a]);
    expect(filterCourses([a, b], '三'), [a]); // 教师名匹配
    expect(filterCourses([a, b], ''), hasLength(2));
  });
}