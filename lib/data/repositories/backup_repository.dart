import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/course_platform.dart';
import 'package:recess/core/models/semester.dart';
import 'package:recess/core/utils/json_parsing.dart';
import 'package:recess/data/app_database.dart' as db;
import 'package:recess/data/mappers.dart';
import 'package:recess/data/repositories/course_platform_repository.dart';
import 'package:recess/data/repositories/course_repository.dart';
import 'package:recess/data/repositories/semester_repository.dart';

/// 备份恢复的结果：恢复了多少学期、多少课程。
class RestoreResult {
  final int semesterCount;
  final int courseCount;
  const RestoreResult({required this.semesterCount, required this.courseCount});
}

/// 备份文件解析/校验：与 [BackupRepository.exportJson] 导出的 JSON 格式对应。
///
/// 顶层 `app` 接受 `'recess'` 和旧备份标识 `'hormone'`，`semesters` 为数组。校验不通过抛
/// [FormatException]（数据完全不改动，保证恢复失败不留半截状态）。
class BackupFile {
  final List<Semester> semesters;
  final Map<String, List<Course>> coursesBySemester;

  /// 学期 id → 课程名 → 课程平台。
  final Map<String, CoursePlatformGroups> platformsBySemester;
  final String? activeSemesterId;

  const BackupFile._({
    required this.semesters,
    required this.coursesBySemester,
    required this.platformsBySemester,
    this.activeSemesterId,
  });

  /// 严格按 UTF-8 读取文件；非法字节在覆盖确认之前拒绝。
  static BackupFile parseBytes(List<int> bytes) => parse(utf8.decode(bytes));

  static BackupFile parse(String jsonText) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (e) {
      throw FormatException('无法解析 JSON：$e');
    }
    if (decoded is! Map) {
      throw const FormatException('备份文件格式错误：顶层应为对象');
    }
    if (decoded['app'] != 'recess' && decoded['app'] != 'hormone') {
      throw const FormatException('这不是 Recess 的备份文件');
    }
    final rawSemesters = decoded['semesters'];
    if (rawSemesters is! List || rawSemesters.isEmpty) {
      throw const FormatException('备份文件中没有学期数据');
    }

    final semesters = <Semester>[];
    final coursesBySemester = <String, List<Course>>{};
    final platformsBySemester = <String, CoursePlatformGroups>{};
    final semesterIds = <String>{};
    String? activeSemesterId;

    for (final raw in rawSemesters) {
      if (raw is! Map) {
        throw const FormatException('备份文件格式错误：学期项不是对象');
      }
      final s = raw as Map<String, dynamic>;
      final id = s['id']?.toString() ?? '';
      if (id.isEmpty) throw const FormatException('备份中存在无 id 的学期');
      if (!semesterIds.add(id)) {
        throw FormatException('备份中存在重复的学期 id：$id');
      }
      final name = s['name']?.toString() ?? '';
      final startDateRaw = s['startDate']?.toString();
      final totalWeeks = toIntOrNull(s['totalWeeks']);
      if (startDateRaw == null || totalWeeks == null) {
        throw FormatException('学期「$name」缺少 startDate 或 totalWeeks');
      }
      final startDate = DateTime.tryParse(startDateRaw);
      if (startDate == null) {
        throw FormatException('学期「$name」的 startDate 非法');
      }
      final override = toIntOrNull(s['currentWeekOverride']);
      final sem = Semester(
        id: id,
        name: name,
        startDate: startDate,
        totalWeeks: totalWeeks,
        currentWeekOverride: override,
      );
      semesters.add(sem);
      if (s['isActive'] == true) activeSemesterId = id;

      final rawCourses = s['courses'];
      if (rawCourses is List) {
        final courses = <Course>[];
        for (final rc in rawCourses) {
          if (rc is! Map) continue;
          final map = rc as Map<String, dynamic>;
          if (map.containsKey('useExplicitTimes') &&
              map['useExplicitTimes'] is! bool) {
            throw const FormatException('备份中存在无法识别的课程钟点使用方式');
          }
          final cid = map['id']?.toString() ?? '';
          if (cid.isEmpty) continue; // 旧版导出无 id 的兜底：丢弃该条
          final cname = map['name']?.toString() ?? '';
          final day = toIntOrNull(map['dayOfWeek']);
          final start = toIntOrNull(map['startSection']);
          final end = toIntOrNull(map['endSection']);
          if (cname.isEmpty || day == null || start == null || end == null) {
            continue;
          }
          courses.add(Course(
            id: cid,
            semesterId: id,
            name: cname,
            teacher: toStringOrNull(map['teacher']),
            location: toStringOrNull(map['location']),
            dayOfWeek: day,
            startSection: start,
            endSection: end,
            startTime: map['startTime']?.toString(),
            endTime: map['endTime']?.toString(),
            useExplicitTimes: map['useExplicitTimes'] as bool? ?? false,
            weeks: _weeks(map['weeks']),
            colorValue: toIntOrNull(map['colorValue']) ??
                parseHexColor(map['color']?.toString(), fallback: 0xFF5B8DEF),
            notes: toStringOrNull(map['notes']),
          ));
        }
        coursesBySemester[id] = courses;
      }
      // 旧版备份没有 platforms 字段，解析为空即可。
      platformsBySemester[id] = parseCoursePlatformGroups(s['platforms']);
    }
    return BackupFile._(
      semesters: semesters,
      coursesBySemester: coursesBySemester,
      platformsBySemester: platformsBySemester,
      activeSemesterId: activeSemesterId,
    );
  }

  static List<int> _weeks(dynamic v) {
    if (v is! List) return const [];
    return v
        .map(toIntOrNull)
        .whereType<int>()
        .where((w) => w >= 1)
        .toSet()
        .toList()
      ..sort();
  }
}

/// 备份恢复数据访问：把导出的 JSON 全量替换当前数据库。
class BackupRepository {
  final db.AppDatabase _db;

  BackupRepository(this._db);

  /// 导出供文件 adapter 直接写入的 UTF-8 内容。
  Future<List<int>> exportBytes() async => utf8.encode(await exportJson());

  /// 把全部学期、课程与课程平台导出为备份 JSON（格式与 [BackupFile] 对应）。
  Future<String> exportJson() async {
    final semesterRepo = SemesterRepository(_db);
    final courseRepo = CourseRepository(_db);
    final platformRepo = CoursePlatformRepository(_db);

    final active = await semesterRepo.getActiveSemester();
    final semesters = await semesterRepo.getSemesters();
    final data = <String, dynamic>{
      'app': 'recess',
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'semesters': <Map<String, dynamic>>[],
    };

    for (final semester in semesters) {
      final courses = await courseRepo.getCourses(semester.id);
      final platforms = await platformRepo.getPlatformsBySemester(semester.id);
      (data['semesters'] as List).add({
        'id': semester.id,
        'name': semester.name,
        'startDate': semester.startDate.toIso8601String(),
        'totalWeeks': semester.totalWeeks,
        'currentWeekOverride': semester.currentWeekOverride,
        'isActive': active?.id == semester.id,
        'courses': courses
            .map((c) => {
                  'id': c.id,
                  'name': c.name,
                  'teacher': c.teacher,
                  'location': c.location,
                  'dayOfWeek': c.dayOfWeek,
                  'startSection': c.startSection,
                  'endSection': c.endSection,
                  'startTime': c.startTime,
                  'endTime': c.endTime,
                  'useExplicitTimes': c.useExplicitTimes,
                  'weeks': c.weeks,
                  'colorValue': c.colorValue,
                  'notes': c.notes,
                })
            .toList(),
        'platforms': {
          for (final entry in platforms.entries)
            entry.key: entry.value.map((p) => p.toJson()).toList(),
        },
      });
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 解析并恢复备份。成功返回恢复统计；失败抛异常且数据库保持原样
  /// （全部写入在单个事务内，任一步失败即回滚）。
  Future<RestoreResult> restore(String jsonText) async {
    return restoreBackup(BackupFile.parse(jsonText));
  }

  /// 恢复覆盖确认时已经校验的同一份备份内容。
  Future<RestoreResult> restoreBackup(BackupFile backup) async {
    var courseCount = 0;
    await _db.transaction(() async {
      // 1. 清空现有数据
      await _db.delete(_db.courses).go();
      await _db.delete(_db.semesters).go();
      await _db.delete(_db.coursePlatforms).go();

      // 2. 批量写入学期、课程与课程平台
      await _db.batch((batch) {
        batch.insertAll(
          _db.semesters,
          backup.semesters.map((s) => s.toCompanion()).toList(),
        );
        for (final entry in backup.coursesBySemester.entries) {
          batch.insertAll(
            _db.courses,
            entry.value.map((c) => c.toCompanion()).toList(),
          );
          courseCount += entry.value.length;
        }
        for (final semester in backup.platformsBySemester.entries) {
          for (final group in semester.value.entries) {
            batch.insertAll(
              _db.coursePlatforms,
              group.value.toCompanions(
                semesterId: semester.key,
                courseName: group.key,
              ),
            );
          }
        }
      });

      // 3. 恢复激活学期（若备份标记了，且仍存在）
      if (backup.activeSemesterId != null) {
        await _db.batch((batch) {
          batch.update(
            _db.semesters,
            const db.SemestersCompanion(isActive: Value(false)),
          );
          batch.update(
            _db.semesters,
            const db.SemestersCompanion(isActive: Value(true)),
            where: (s) => s.id.equals(backup.activeSemesterId!),
          );
        });
      } else {
        // 无激活标记：将第一个学期设为激活，避免零激活态。
        await _db.batch((batch) {
          batch.update(
            _db.semesters,
            const db.SemestersCompanion(isActive: Value(true)),
            where: (s) => s.id.equals(backup.semesters.first.id),
          );
        });
      }
    });
    return RestoreResult(
      semesterCount: backup.semesters.length,
      courseCount: courseCount,
    );
  }
}
