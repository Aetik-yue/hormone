import 'package:drift/drift.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/data/app_database.dart' as db;

/// drift 实体 <-> 领域模型 的映射。
/// 领域层（core/models）保持与持久化无关，便于 UI 与单元测试复用。
///
/// 注意：drift 表 `Courses`/`Semesters` 生成的数据类也叫 `Course`/`Semester`，
/// 与领域模型同名，因此这里把 `app_database` 以 `db` 前缀导入，用 `db.Course`
/// 指代持久化实体、`Course` 指代领域模型，避免歧义。

extension CourseEntityMapper on db.Course {
  Course toDomain() => Course(
        id: id,
        semesterId: semesterId,
        name: name,
        teacher: teacher,
        location: location,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        startTime: startTime,
        endTime: endTime,
        weeks: weeks.isEmpty
            ? const []
            : weeks
                .split(',')
                .where((e) => e.isNotEmpty)
                .map((e) => int.tryParse(e.trim()))
                .whereType<int>()
                .toList(),
        colorValue: colorValue,
        notes: notes,
      );
}

extension CourseDomainMapper on Course {
  db.CoursesCompanion toCompanion() => db.CoursesCompanion(
        id: Value(id),
        semesterId: Value(semesterId),
        name: Value(name),
        teacher: Value(teacher),
        location: Value(location),
        dayOfWeek: Value(dayOfWeek),
        startSection: Value(startSection),
        endSection: Value(endSection),
        startTime: Value(startTime),
        endTime: Value(endTime),
        weeks: Value(weeks.isEmpty ? '' : weeks.join(',')),
        colorValue: Value(colorValue),
        notes: Value(notes),
      );
}

extension SemesterEntityMapper on db.Semester {
  Semester toDomain() => Semester(
        id: id,
        name: name,
        startDate: startDate,
        totalWeeks: totalWeeks,
        currentWeekOverride: currentWeekOverride,
      );
}

extension SemesterDomainMapper on Semester {
  db.SemestersCompanion toCompanion() =>
      db.SemestersCompanion(
        id: Value(id),
        name: Value(name),
        startDate: Value(startDate),
        totalWeeks: Value(totalWeeks),
        currentWeekOverride: Value(currentWeekOverride),
      );
}
