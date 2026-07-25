import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/import/data/json_importer.dart';

void main() {
  group('JsonCourseImporter - 合法模板', () {
    final json = jsonEncode({
      'courses': [
        {
          'name': '高等数学',
          'teacher': '张三',
          'location': '教三-201',
          'dayOfWeek': 2,
          'startSection': 3,
          'endSection': 4,
          'weeks': [1, 2, 3, 4, 5],
          'color': '#5B8DEF',
          'notes': '带书',
        }
      ]
    });

    final courses = JsonCourseImporter.parse(json, totalWeeks: 18);

    test('解析出 1 门', () {
      expect(courses, hasLength(1));
    });
    test('字段映射正确', () {
      final c = courses.first;
      expect(c.name, '高等数学');
      expect(c.teacher, '张三');
      expect(c.dayOfWeek, 2);
      expect(c.startSection, 3);
      expect(c.endSection, 4);
      expect(c.weeks, [1, 2, 3, 4, 5]);
    });
    test('颜色解析为 ARGB', () {
      // #5B8DEF -> 0xFF5B8DEF
      expect(courses.first.colorValue, 0xFF5B8DEF);
    });
  });

  group('JsonCourseImporter - 容错', () {
    test('非法 dayOfWeek 被跳过并计入 skipped', () {
      final json = jsonEncode({
        'courses': [
          {'name': '有效', 'dayOfWeek': 1, 'startSection': 1, 'endSection': 2},
          {'name': '非法星期', 'dayOfWeek': 9, 'startSection': 1, 'endSection': 2},
        ]
      });
      final courses = JsonCourseImporter.parse(json, totalWeeks: 18);
      expect(courses, hasLength(1));
    });

    test('缺少 name 被跳过', () {
      final json = jsonEncode({
        'courses': [
          {'dayOfWeek': 1, 'startSection': 1, 'endSection': 2},
        ]
      });
      final courses = JsonCourseImporter.parse(json, totalWeeks: 18);
      expect(courses, isEmpty);
    });

    test('超过总周数的周次被过滤', () {
      final json = jsonEncode({
        'courses': [
          {
            'name': '越界周',
            'dayOfWeek': 1,
            'startSection': 1,
            'endSection': 2,
            'weeks': [1, 2, 30],
          }
        ]
      });
      final courses = JsonCourseImporter.parse(json, totalWeeks: 18);
      expect(courses.first.weeks, [1, 2]);
    });
  });

  group('JsonCourseImporter - 顶层为数组', () {
    test('直接数组也可解析', () {
      final json = jsonEncode([
        {'name': 'A', 'dayOfWeek': 1, 'startSection': 1, 'endSection': 2}
      ]);
      final courses = JsonCourseImporter.parse(json, totalWeeks: 18);
      expect(courses, hasLength(1));
      expect(courses.first.name, 'A');
    });
  });
}
