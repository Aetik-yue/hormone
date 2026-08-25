import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/data/app_database.dart' as db;
import 'package:hormone/data/mappers.dart';

/// 备份恢复的结果：恢复了多少学期、多少课程。
class RestoreResult {
  final int semesterCount;
  final int courseCount;
  const RestoreResult({required this.semesterCount, required this.courseCount});
}

/// 备份文件解析/校验：与 [export_service.dart] 导出的 JSON 格式对应。
///
/// 顶层含 `app == 'hormone'` 校验，`semesters` 为数组。校验不通过抛
/// [FormatException]（数据完全不改动，保证恢复失败不留半截状态）。
class BackupFile {
  final List<Semester> semesters;
  final Map<String, List<Course>> coursesBySemester;
  final String? activeSemesterId;

  const BackupFile._({
    required this.semesters,
    required this.coursesBySemester,
    this.activeSemesterId,
  });

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
    if (decoded['app'] != 'hormone') {
      throw const FormatException('这不是 Hormone 的备份文件');
    }
    final rawSemesters = decoded['semesters'];
    if (rawSemesters is! List || rawSemesters.isEmpty) {
      throw const FormatException('备份文件中没有学期数据');
    }

    final semesters = <Semester>[];
    final coursesBySemester = <String, List<Course>>{};
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
      final totalWeeks = _toInt(s['totalWeeks']);
      if (startDateRaw == null || totalWeeks == null) {
        throw FormatException('学期「$name」缺少 startDate 或 totalWeeks');
      }
      final startDate = DateTime.tryParse(startDateRaw);
      if (startDate == null) {
        throw FormatException('学期「$name」的 startDate 非法');
      }
      final override = _toInt(s['currentWeekOverride']);
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
          final cid = map['id']?.toString() ?? '';
          if (cid.isEmpty) continue; // 旧版导出无 id 的兜底：丢弃该条
          final cname = map['name']?.toString() ?? '';
          final day = _toInt(map['dayOfWeek']);
          final start = _toInt(map['startSection']);
          final end = _toInt(map['endSection']);
          if (cname.isEmpty || day == null || start == null || end == null) {
            continue;
          }
          courses.add(Course(
            id: cid,
            semesterId: id,
            name: cname,
            teacher: _optString(map['teacher']),
            location: _optString(map['location']),
            dayOfWeek: day,
            startSection: start,
            endSection: end,
            startTime: _optString(map['startTime']),
            endTime: _optString(map['endTime']),
            weeks: _weeks(map['weeks']),
            colorValue: _toInt(map['colorValue']) ??
                _parseColor(map['color']?.toString()),
            notes: _optString(map['notes']),
          ));
        }
        coursesBySemester[id] = courses;
      }
    }
    return BackupFile._(
      semesters: semesters,
      coursesBySemester: coursesBySemester,
      activeSemesterId: activeSemesterId,
    );
  }

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String? _optString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static List<int> _weeks(dynamic v) {
    if (v is! List) return const [];
    return v
        .map((w) => _toInt(w))
        .whereType<int>()
        .where((w) => w >= 1)
        .toSet()
        .toList()
      ..sort();
  }

  static int _parseColor(String? s) {
    if (s == null) return 0xFF5B8DEF;
    var hex = s.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) return int.tryParse(hex, radix: 16) ?? 0xFF5B8DEF;
    return 0xFF5B8DEF;
  }
}

/// 备份恢复数据访问：把导出的 JSON 全量替换当前数据库。
class BackupRepository {
  final db.AppDatabase _db;

  BackupRepository(this._db);

  /// 解析并恢复备份。成功返回恢复统计；失败抛异常且数据库保持原样
  /// （全部写入在单个事务内，任一步失败即回滚）。
  Future<RestoreResult> restore(String jsonText) async {
    final backup = BackupFile.parse(jsonText);

    var courseCount = 0;
    await _db.transaction(() async {
      // 1. 清空现有数据
      await _db.delete(_db.courses).go();
      await _db.delete(_db.semesters).go();

      // 2. 批量写入学期
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
      });
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
    return RestoreResult(
      semesterCount: backup.semesters.length,
      courseCount: courseCount,
    );
  }
}
