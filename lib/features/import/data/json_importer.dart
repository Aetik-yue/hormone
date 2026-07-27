import 'dart:convert';

import 'package:hormone/core/constants/app_constants.dart';
import 'package:hormone/features/import/domain/import_course.dart';

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
///   ]
/// }
/// ```
///
/// 容错策略：单条记录字段非法时跳过该条并计入 [skipped]，其余照常导入。
class JsonCourseImporter {
  /// 返回导入课程与跳过的条目（用于 UI 提示）。
  static ({List<ImportCourse> courses, List<String> skipped}) parse(
    String jsonText, {
    int? totalWeeks,
  }) {
    final skipped = <String>[];
    final List<dynamic> rawList;

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map && decoded['courses'] is List) {
        rawList = decoded['courses'] as List;
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
        skipped.add('第${i + 1}条：非对象');
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final course = _parseOne(map, i, totalWeeks, skipped);
      if (course != null) result.add(course);
    }
    return (courses: result, skipped: skipped);
  }

  static ImportCourse? _parseOne(
    Map<String, dynamic> m,
    int index,
    int? totalWeeks,
    List<String> skipped,
  ) {
    final name = m['name']?.toString().trim();
    if (name == null || name.isEmpty) {
      skipped.add('第${index + 1}条：缺少 name');
      return null;
    }

    final dayOfWeek = _toInt(m['dayOfWeek']);
    if (dayOfWeek == null || dayOfWeek < 1 || dayOfWeek > 7) {
      skipped.add('第${index + 1}条：dayOfWeek 非法');
      return null;
    }
    final startSection = _toInt(m['startSection']) ?? 1;
    final endSection = _toInt(m['endSection']) ?? startSection;
    if (startSection < 1 ||
        endSection > AppConstants.maxSections ||
        endSection < startSection) {
      skipped.add('第${index + 1}条：节次非法');
      return null;
    }

    List<int> weeks;
    if (m['weeks'] is List) {
      weeks = (m['weeks'] as List)
          .map((w) => _toInt(w))
          .where((w) => w != null)
          .cast<int>()
          .where((w) => w >= 1 && (totalWeeks == null || w <= totalWeeks))
          .toList();
      if (weeks.isEmpty) {
        skipped.add('第${index + 1}条：周次为空');
        return null;
      }
    } else {
      skipped.add('第${index + 1}条：缺少周次');
      return null;
    }

    final colorValue = _parseColor(m['color']?.toString());

    return ImportCourse(
      name: name,
      teacher: _toStringOrNull(m['teacher']),
      location: _toStringOrNull(m['location']),
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      startTime: _toStringOrNull(m['startTime']),
      endTime: _toStringOrNull(m['endTime']),
      weeks: weeks,
      colorValue: colorValue,
      notes: _toStringOrNull(m['notes']),
      source: 'json',
    );
  }

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String? _toStringOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// 解析颜色：支持 "#RRGGBB" / "0xFFRRGGBB" / 纯 "RRGGBB"。失败回退默认蓝。
  static int _parseColor(String? s) {
    if (s == null) return 0xFF5B8DEF;
    var hex = s.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) return int.tryParse(hex, radix: 16) ?? 0xFF5B8DEF;
    return 0xFF5B8DEF;
  }
}
