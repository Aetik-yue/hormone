import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/import/domain/import_course.dart';

ImportCourse _c({
  String name = 'X',
  String? teacher,
  String? location,
  int day = 1,
  int start = 1,
  int end = 2,
  List<int> weeks = const [1, 2, 3],
  String? startTime,
  String? endTime,
}) =>
    ImportCourse(
      name: name,
      teacher: teacher,
      location: location,
      dayOfWeek: day,
      startSection: start,
      endSection: end,
      weeks: weeks,
      startTime: startTime,
      endTime: endTime,
      source: 'json',
    );

void main() {
  group('sectionLabel', () {
    test('含星期/节次/时间', () {
      final c = _c(name: '高数', start: 1, end: 2,
          weeks: const [1, 2, 3],
          startTime: '08:00', endTime: '08:45');
      expect(c.sectionLabel, contains('周一'));
      expect(c.sectionLabel, contains('第1-2节'));
      expect(c.sectionLabel, contains('08:00-08:45'));
    });
  });

  group('weekLabel', () {
    test('连续周显示为区间', () {
      expect(_c(weeks: const [1, 2, 3, 4]).weekLabel, '1-4周');
    });
    test('单周', () {
      expect(_c(weeks: const [5]).weekLabel, '第5周');
    });
    test('非连续周列出全部', () {
      expect(_c(weeks: const [1, 3, 5]).weekLabel, '1,3,5周');
    });
    test('空周次', () {
      expect(_c(weeks: const []).weekLabel, '未排周次');
    });
  });

  group('coursesConflict', () {
    test('同日同时段且周次重叠 => 冲突', () {
      final a = _c(day: 1, start: 1, end: 2, weeks: const [1, 3, 5]);
      final b = _c(day: 1, start: 2, end: 3, weeks: const [3, 5, 7]);
      expect(coursesConflict(a, b), isTrue);
    });

    test('不同星期 => 不冲突', () {
      final a = _c(day: 1, start: 1, end: 2, weeks: const [1, 2]);
      final b = _c(day: 2, start: 1, end: 2, weeks: const [1, 2]);
      expect(coursesConflict(a, b), isFalse);
    });

    test('节次不重叠 => 不冲突', () {
      final a = _c(day: 1, start: 1, end: 2, weeks: const [1, 2]);
      final b = _c(day: 1, start: 3, end: 4, weeks: const [1, 2]);
      expect(coursesConflict(a, b), isFalse);
    });

    test('周次无交集 => 不冲突', () {
      final a = _c(day: 1, start: 1, end: 2, weeks: const [1, 3, 5]);
      final b = _c(day: 1, start: 1, end: 2, weeks: const [2, 4, 6]);
      expect(coursesConflict(a, b), isFalse);
    });
  });

  group('toCourse', () {
    test('生成领域模型且归属指定学期、id 为空待写入', () {
      final c = _c(name: '物理', location: '教二', teacher: '王');
      final course = c.toCourse('sem-1');
      expect(course.semesterId, 'sem-1');
      expect(course.id, isEmpty);
      expect(course.name, '物理');
      expect(course.location, '教二');
    });
  });
}
