import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/data/app_database.dart' as db;
import 'package:hormone/data/repositories/backup_repository.dart';
import 'package:hormone/data/repositories/course_repository.dart';
import 'package:hormone/data/repositories/semester_repository.dart';

void main() {
  late db.AppDatabase database;
  late BackupRepository backup;
  late CourseRepository courses;
  late SemesterRepository semesters;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    backup = BackupRepository(database);
    courses = CourseRepository(database);
    semesters = SemesterRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  String exportFixture() {
    final data = {
      'app': 'hormone',
      'version': 1,
      'exportedAt': '2026-08-26T00:00:00.000',
      'semesters': [
        {
          'id': 's1',
          'name': '2026 秋',
          'startDate': DateTime(2026, 9, 1).toIso8601String(),
          'totalWeeks': 18,
          'currentWeekOverride': 3,
          'isActive': true,
          'courses': [
            {
              'id': 'c1',
              'name': '高等数学',
              'teacher': '张三',
              'location': '教三 201',
              'dayOfWeek': 1,
              'startSection': 1,
              'endSection': 2,
              'startTime': '08:00',
              'endTime': '09:35',
              'weeks': [1, 2, 3, 4, 5],
              'colorValue': 0xFF3FBFA8,
              'notes': '带课本',
            },
          ],
        },
        {
          'id': 's2',
          'name': '2025 春',
          'startDate': DateTime(2025, 3, 1).toIso8601String(),
          'totalWeeks': 16,
          'courses': [
            {
              'id': 'c2',
              'name': '线性代数',
              'dayOfWeek': 2,
              'startSection': 3,
              'endSection': 4,
              'weeks': [1, 2, 3],
            },
          ],
        },
      ],
    };
    return const JsonEncoder().convert(data);
  }

  test('恢复备份后数据与备份一致，激活学期与周次覆盖被保留', () async {
    // 先写入一些旧数据，确保被覆盖。
    await semesters.upsert(Semester(
      id: 'old-s',
      name: '旧学期',
      startDate: DateTime(2020),
      totalWeeks: 10,
    ));
    await courses.upsert(const Course(
      id: 'old-c',
      semesterId: 'old-s',
      name: '旧课程',
      dayOfWeek: 1,
      startSection: 1,
      endSection: 1,
    ));

    final result = await backup.restore(exportFixture());
    expect(result.semesterCount, 2);
    expect(result.courseCount, 2);

    final allSemesters = await semesters.getSemesters();
    expect(allSemesters, hasLength(2));
    final s1 = allSemesters.firstWhere((s) => s.id == 's1');
    expect(s1.name, '2026 秋');
    expect(s1.currentWeekOverride, 3);

    final active = await semesters.getActiveSemester();
    expect(active?.id, 's1');

    final c1 = await courses.getCourses('s1');
    expect(c1, hasLength(1));
    expect(c1.single.name, '高等数学');
    expect(c1.single.teacher, '张三');
    expect(c1.single.colorValue, 0xFF3FBFA8);
    expect(c1.single.weeks, [1, 2, 3, 4, 5]);
    expect(c1.single.startTime, '08:00');
    expect(c1.single.endTime, '09:35');

    final c2 = await courses.getCourses('s2');
    expect(c2.single.colorValue, 0xFF5B8DEF); // 无颜色时回退默认蓝
  });

  test('非备份文件（缺少 app 标识）抛出错误且不改动数据', () async {
    await semesters.upsert(Semester(
      id: 'old-s',
      name: '旧学期',
      startDate: DateTime(2020),
      totalWeeks: 10,
    ));

    await expectLater(
      backup.restore('{"foo": 1}'),
      throwsA(isA<FormatException>()),
    );

    // 数据未被改动。
    final allSemesters = await semesters.getSemesters();
    expect(allSemesters, hasLength(1));
    expect(allSemesters.single.id, 'old-s');
  });

  test('非法 JSON 抛出异常', () async {
    await expectLater(
      backup.restore('not json at all'),
      throwsA(isA<FormatException>()),
    );
  });

  test('含重复学期 id 的备份抛出异常', () async {
    final data = {
      'app': 'hormone',
      'semesters': [
        {'id': 'dup', 'name': 'A', 'startDate': '2026-01-01', 'totalWeeks': 18},
        {'id': 'dup', 'name': 'B', 'startDate': '2026-02-01', 'totalWeeks': 16},
      ],
    };
    await expectLater(
      backup.restore(const JsonEncoder().convert(data)),
      throwsA(isA<FormatException>()),
    );
  });
}
