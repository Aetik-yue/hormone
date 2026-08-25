import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:hormone/data/providers/database_providers.dart';

/// 数据导出服务：将全部学期 + 课程导出为 JSON，并通过系统分享面板交给用户保存。
class ExportService {
  final Ref _ref;
  ExportService(this._ref);

  /// 导出全部数据并弹出系统分享面板。返回分享的结果。
  Future<ShareResult> exportToJson() async {
    final semesterRepo = _ref.read(semesterRepositoryProvider);
    final courseRepo = _ref.read(courseRepositoryProvider);

    final semesters = await semesterRepo.getSemesters();
    final active = await semesterRepo.getActiveSemester();
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
                  'weeks': c.weeks,
                  'colorValue': c.colorValue,
                  'notes': c.notes,
                })
            .toList(),
      });
    }

    // 写到系统缓存目录，普通用户无法访问应用私有目录，必须交由系统分享面板
    // 转存（下载/云盘/微信等）。
    final dir = await getTemporaryDirectory();
    final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/hormone_backup_$dateStr.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );

    final xFile = XFile(file.path,
        mimeType: 'application/json', name: 'hormone_backup_$dateStr.json');
    return Share.shareXFiles([xFile]);
  }
}

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(ref);
});
