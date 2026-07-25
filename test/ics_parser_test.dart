import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/import/data/ics_parser.dart';

/// 学期：2024-09-02（周一）开学，18 周。
final _start = DateTime(2024, 9, 2);
const _totalWeeks = 18;

void main() {
  group('IcsCourseParser - 基础每周课程', () {
    const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:course-1
SUMMARY:高等数学
LOCATION:教三-201
DESCRIPTION:教师: 张三
DTSTART:20240902T080000
DTEND:20240902T094500
RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=18
END:VEVENT
END:VCALENDAR
''';

    final courses =
        IcsCourseParser.parse(ics, semesterStart: _start, totalWeeks: _totalWeeks);

    test('解析出一门课', () {
      expect(courses, hasLength(1));
    });

    test('星期、名称、教室正确', () {
      final c = courses.first;
      expect(c.name, '高等数学');
      expect(c.location, '教三-201');
      expect(c.dayOfWeek, 1); // 周一
    });

    test('教师从 DESCRIPTION 提取', () {
      expect(courses.first.teacher, '张三');
    });

    test('周次覆盖 1..18', () {
      expect(courses.first.weeks, List.generate(18, (i) => i + 1));
    });

    test('节次由时间反推（08:00->第1节, 09:45->第2节）', () {
      expect(courses.first.startSection, 1);
      expect(courses.first.endSection, 2);
    });
  });

  group('IcsCourseParser - 多 BYDAY', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:c2
SUMMARY:英语
DTSTART:20240902T100000
DTEND:20240902T105000
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=18
END:VEVENT
END:VCALENDAR
''';
    final courses =
        IcsCourseParser.parse(ics, semesterStart: _start, totalWeeks: _totalWeeks);

    test('MO/WE 各生成一条', () {
      expect(courses, hasLength(2));
      final days = courses.map((c) => c.dayOfWeek).toList()..sort();
      expect(days, [1, 3]);
    });
  });

  group('IcsCourseParser - 双周（INTERVAL=2）', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:c3
SUMMARY:双周课
DTSTART:20240903T100000
DTEND:20240903T105000
RRULE:FREQ=WEEKLY;BYDAY=TU;INTERVAL=2;COUNT=9
END:VEVENT
END:VCALENDAR
''';
    final courses =
        IcsCourseParser.parse(ics, semesterStart: _start, totalWeeks: _totalWeeks);

    test('生成 9 条且为奇数周', () {
      expect(courses, hasLength(1));
      expect(courses.first.dayOfWeek, 2); // 周二
      expect(courses.first.weeks,
          [1, 3, 5, 7, 9, 11, 13, 15, 17]);
    });
  });

  group('IcsCourseParser - 行折叠', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:c4
SUMMARY:长名称课程需要换行折叠处理的长文本描述测试
DTSTART:20240902T080000
DTEND:20240902T085000
RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=18
END:VEVENT
END:VCALENDAR
''';
    final courses =
        IcsCourseParser.parse(ics, semesterStart: _start, totalWeeks: _totalWeeks);

    test('折叠行被合并解析', () {
      expect(courses, hasLength(1));
      expect(courses.first.name, startsWith('长名称课程'));
    });
  });

  group('IcsCourseParser - 早于开学跳过', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:c5
SUMMARY:提前课
DTSTART:20240801T080000
DTEND:20240801T085000
RRULE:FREQ=WEEKLY;BYDAY=TH;COUNT=18
END:VEVENT
END:VCALENDAR
''';
    final courses =
        IcsCourseParser.parse(ics, semesterStart: _start, totalWeeks: _totalWeeks);

    test('开学前的课程被跳过', () {
      expect(courses, isEmpty);
    });
  });
}
