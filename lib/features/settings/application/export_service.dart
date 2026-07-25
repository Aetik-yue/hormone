import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import 'package:hormone/data/providers/database_providers.dart';

/// 数据导出服务：将全部学期 + 课程导出为 JSON 文件。
class ExportService {
  final Ref _ref;
  ExportService(this._ref);

  /// 导出全部数据为 JSON 文件，返回文件路径。
  Future<String> exportToJson() async {
    final semesterRepo = _ref.read(semesterRepositoryProvider);
    final courseRepo = _ref.read(courseRepositoryProvider);

    final semesters = await semesterRepo.getSemesters();
    final data = <String, dynamic>{
      'app': 'hormone',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'semesters': <Map<String, dynamic>>[],
    };

    for (final semester in semesters) {
      final courses = await courseRepo.getCourses(semester.id);
      (data['semesters'] as List).add({
        'id': semester.id,
        'name': semester.name,
        'startDate': semester.startDate.toIso8601String(),
        'totalWeeks': semester.totalWeeks,
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
                  'weeks': c.weeks,
                  'colorValue': c.colorValue,
                  'notes': c.notes,
                })
            .toList(),
      });
    }

    final dir = await getApplicationDocumentsDirectory();
    final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/hormone_backup_$dateStr.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    return file.path;
  }
}

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(ref);
});
