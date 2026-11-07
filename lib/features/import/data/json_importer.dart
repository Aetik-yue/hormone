import 'dart:convert';

import 'package:recess/core/constants/app_constants.dart';
import 'package:recess/core/models/course_platform.dart';
import 'package:recess/core/models/import_diagnostic.dart';
import 'package:recess/core/utils/json_parsing.dart';
import 'package:recess/features/import/domain/import_course.dart';

/// JSON 课程导入器。采用「显式领域模板」——字段与 App 内部模型一一对应，
/// 便于手动编写或从其他工具导出。示例：
///
/// ```json
/// {
///   "courses": [
///     {
///       "name": "高等数学",
///       "teacher": "张三",
///       "location": "教三 301",
///       "dayOfWeek": 1,
///       "startSection": 1,
///       "endSection": 2,
///       "weeks": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18],
///       "color": "#5B8DEF",
///       "notes": ""
///     }
///   ],
///   "platforms": {
///     "高等数学": [
///       {"purpose": "online_course", "name": "学习通", "url": "https://..."}
///     ]
///   }
/// }
/// ```
///
/// `platforms` 可选，按课程名给出课程平台，`purpose` 取
/// `online_course` / `lab` / `homework` / `group` / `other`。
///
/// 容错策略：单条记录字段非法时跳过该条并计入诊断（整条未导入）；
/// 记录保留但部分信息无效时（如部分周次越界、平台链接协议不允许）
/// 保留记录并记为「部分忽略」，不改变原有容错行为。
class JsonCourseImporter {
  /// 返回导入课程、按课程名分组的课程平台与逐条诊断（用于 UI 提示）。
  static ({
    List<ImportCourse> courses,
    CoursePlatformGroups platforms,
    List<ImportDiagnostic> diagnostics,
  }) parse(
    String jsonText, {
    int? totalWeeks,
  }) {
    final diagnostics = <ImportDiagnostic>[];
    final List<dynamic> rawList;
    Object? rawPlatforms;
    var isBackup = false;

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map &&
          (decoded['app'] == 'recess' || decoded['app'] == 'hormone')) {
        isBackup = true;
        if (decoded['semesters'] is List) {
          throw const FormatException('Recess 备份请通过设置中的“从备份恢复”导入');
        }
      }
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map && decoded['courses'] is List) {
        rawList = decoded['courses'] as List;
        rawPlatforms = decoded['platforms'];
      } else {
        throw const FormatException('JSON 顶层应为数组或 {"courses": [...]}');
      }
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('无法解析 JSON: $e');
    }

    final result = <ImportCourse>[];
    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map) {
        diagnostics.add(ImportDiagnostic(
          kind: ImportDiagnosticKind.skipped,
          record: '第${i + 1}条',
          reason: '非对象',
        ));
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final course = _parseOne(map, i, totalWeeks, diagnostics, isBackup);
      if (course != null) result.add(course);
    }
    final platforms =
        parseCoursePlatformGroups(rawPlatforms, diagnostics: diagnostics);
    return (courses: result, platforms: platforms, diagnostics: diagnostics);
  }

  static ImportCourse? _parseOne(
    Map<String, dynamic> m,
    int index,
    int? totalWeeks,
    List<ImportDiagnostic> diagnostics,
    bool isBackup,
  ) {
    final hasTimeSemantics = m.containsKey('useExplicitTimes');
    if (hasTimeSemantics && m['useExplicitTimes'] is! bool) {
      throw const FormatException('文件中存在无法识别的课程钟点使用方式');
    }
    final record = '第${index + 1}条';
    void skip(String reason) => diagnostics.add(ImportDiagnostic(
          kind: ImportDiagnosticKind.skipped,
          record: record,
          reason: reason,
        ));
    final name = m['name']?.toString().trim();
    if (name == null || name.isEmpty) {
      skip('缺少 name');
      return null;
    }

    final dayOfWeek = toIntOrNull(m['dayOfWeek']);
    if (dayOfWeek == null || dayOfWeek < 1 || dayOfWeek > 7) {
      skip('dayOfWeek 非法');
      return null;
    }
    final startSection = toIntOrNull(m['startSection']) ?? 1;
    final endSection = toIntOrNull(m['endSection']) ?? startSection;
    if (startSection < 1 ||
        endSection > AppConstants.maxSections ||
        endSection < startSection) {
      skip('节次非法');
      return null;
    }

    List<int> weeks;
    if (m['weeks'] is List) {
      final rawWeeks = (m['weeks'] as List).map(toIntOrNull).toList();
      final inRange = rawWeeks
          .where((w) =>
              w != null && w >= 1 && (totalWeeks == null || w <= totalWeeks))
          .cast<int>()
          .toList();
      final outOfRange = rawWeeks
          .where((w) =>
              w != null && (w < 1 || (totalWeeks != null && w > totalWeeks)))
          .length;
      if (inRange.isEmpty) {
        skip('周次为空');
        return null;
      }
      if (outOfRange > 0) {
        diagnostics.add(ImportDiagnostic(
          kind: ImportDiagnosticKind.partial,
          record: record,
          reason: '$outOfRange 个周次超出学期范围，已忽略',
        ));
      }
      weeks = inRange;
    } else {
      skip('缺少周次');
      return null;
    }

    final colorValue = parseHexColor(
      m['color']?.toString(),
      fallback: AppConstants.defaultCourseColor,
    );

    return ImportCourse(
      name: name,
      teacher: toStringOrNull(m['teacher']),
      location: toStringOrNull(m['location']),
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      startTime: hasTimeSemantics
          ? m['startTime']?.toString()
          : toStringOrNull(m['startTime']),
      endTime: hasTimeSemantics
          ? m['endTime']?.toString()
          : toStringOrNull(m['endTime']),
      useExplicitTimes: m['useExplicitTimes'] as bool? ??
          (isBackup ? false : null),
      weeks: weeks,
      colorValue: colorValue,
      notes: toStringOrNull(m['notes']),
      source: 'json',
    );
  }
}
