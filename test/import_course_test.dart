import 'package:flutter_test/flutter_test.dart';
import 'package:recess/core/constants/app_constants.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/course_platform.dart';
import 'package:recess/features/import/domain/import_course.dart';

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
  int colorValue = AppConstants.defaultCourseColor,
  String? notes,
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
      colorValue: colorValue,
      notes: notes,
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

  group('conflictsWithCourse', () {
    test('合并模式下与现有课程同时段重叠 => 冲突', () {
      final imp = _c(name: '新课', day: 1, start: 1, end: 2, weeks: const [1]);
      final existing = const Course(
        id: 'e1',
        semesterId: 's',
        name: '旧课',
        dayOfWeek: 1,
        startSection: 2,
        endSection: 3,
        weeks: [1],
      );
      expect(conflictsWithCourse(imp, existing), isTrue);
    });

    test('节次不重叠 => 不冲突', () {
      final imp = _c(name: '新课', day: 1, start: 1, end: 2, weeks: const [1]);
      final existing = const Course(
        id: 'e1',
        semesterId: 's',
        name: '旧课',
        dayOfWeek: 1,
        startSection: 3,
        endSection: 4,
        weeks: [1],
      );
      expect(conflictsWithCourse(imp, existing), isFalse);
    });
  });

  group('withSelected', () {
    test('返回勾选状态翻转的副本，原对象与其余字段不变', () {
      final c = _c(name: '高数', teacher: '王', location: '教二',
          weeks: const [1, 3], startTime: '08:00', endTime: '08:45',
          colorValue: 0xFF123456, notes: '带作业本');
      final copy = c.withSelected(false);
      expect(c.selected, isTrue);
      expect(copy.selected, isFalse);
      expect(copy.name, c.name);
      expect(copy.teacher, c.teacher);
      expect(copy.location, c.location);
      expect(copy.dayOfWeek, c.dayOfWeek);
      expect(copy.startSection, c.startSection);
      expect(copy.endSection, c.endSection);
      expect(copy.startTime, c.startTime);
      expect(copy.endTime, c.endTime);
      expect(copy.useExplicitTimes, c.useExplicitTimes);
      expect(copy.weeks, c.weeks);
      expect(copy.colorValue, c.colorValue);
      expect(copy.notes, c.notes);
      expect(copy.source, c.source);
    });
  });

  group('conflictNames', () {
    test('返回勾选课程之间的内部冲突名称', () {
      final a = _c(name: 'A', day: 1, start: 1, end: 2, weeks: const [1]);
      final b = _c(name: 'B', day: 1, start: 2, end: 3, weeks: const [1]);
      final c = _c(name: 'C', day: 2, start: 1, end: 2, weeks: const [1]);
      expect(conflictNames([a, b, c], const []), {'A', 'B'});
    });

    test('未勾选课程不参与内部冲突或与现有课表的冲突', () {
      final a = _c(name: 'A', day: 1, start: 1, end: 2, weeks: const [1]);
      final b = _c(name: 'B', day: 1, start: 1, end: 2, weeks: const [1])
        ..selected = false;
      const existing = Course(
        id: 'e1',
        semesterId: 's',
        name: '旧课',
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        weeks: [1],
      );
      expect(conflictNames([a, b], [existing]), {'A'});
    });

    test('与现有课程时间重叠的导入课程计入冲突', () {
      final imp = _c(name: '新课', day: 1, start: 1, end: 2, weeks: const [1]);
      const existing = Course(
        id: 'e1',
        semesterId: 's',
        name: '旧课',
        dayOfWeek: 1,
        startSection: 2,
        endSection: 3,
        weeks: [1],
      );
      expect(conflictNames([imp], [existing]), {'新课'});
    });

    test('无任何冲突时返回空集', () {
      final a = _c(name: 'A', day: 1, start: 1, end: 2, weeks: const [1]);
      final b = _c(name: 'B', day: 1, start: 3, end: 4, weeks: const [1]);
      expect(conflictNames([a, b], const []), isEmpty);
    });
  });

  group('ImportMode', () {
    test('默认为替换模式', () {
      expect(ImportMode.replace, isA<ImportMode>());
      expect(ImportMode.values, containsAll([ImportMode.replace, ImportMode.merge]));
    });
  });

  group('platformsForImportedCourses', () {
    const online = CoursePlatform(
      purpose: CoursePlatformPurpose.onlineCourse,
      name: '学习通',
    );
    const lab = CoursePlatform(purpose: CoursePlatformPurpose.lab, name: '头歌');

    test('只保留实际导入的课程名对应的平台', () {
      final result = platformsForImportedCourses(
        {
          '操作系统': [online],
          '取消勾选的课': [lab],
          '文件里没有的课': [lab],
        },
        [_c(name: '操作系统'), _c(name: '编译原理')],
      );
      expect(result, {
        '操作系统': [online],
      });
    });
  });
}
