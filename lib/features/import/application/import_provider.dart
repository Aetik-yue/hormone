import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:hormone/core/models/semester.dart';
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/features/import/domain/import_course.dart';
import 'package:hormone/features/import/data/ics_parser.dart';
import 'package:hormone/features/import/data/json_importer.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'package:hormone/features/widget/application/widget_service.dart';

/// 导入流程状态机。
enum ImportStatus {
  idle, // 尚未选择文件
  picking, // 系统文件选择器拉起中
  parsing, // 解析文件中
  preview, // 解析完成，等待用户勾选与确认
  importing, // 写入数据库
  done, // 导入完成
  error, // 失败（含错误信息）
}

/// 导入页的不可变状态。
class ImportState {
  final ImportStatus status;
  final List<ImportCourse> courses;
  final String? errorMessage;
  final int importedCount;
  final List<String> skipped;
  final int totalWeeks;

  const ImportState({
    this.status = ImportStatus.idle,
    this.courses = const [],
    this.errorMessage,
    this.importedCount = 0,
    this.skipped = const [],
    this.totalWeeks = 18,
  });

  ImportState copyWith({
    ImportStatus? status,
    List<ImportCourse>? courses,
    String? errorMessage,
    int? importedCount,
    List<String>? skipped,
    int? totalWeeks,
  }) =>
      ImportState(
        status: status ?? this.status,
        courses: courses ?? this.courses,
        errorMessage: errorMessage,
        importedCount: importedCount ?? this.importedCount,
        skipped: skipped ?? this.skipped,
        totalWeeks: totalWeeks ?? this.totalWeeks,
      );

  int get selectedCount => courses.where((c) => c.selected).length;
}

final importProvider =
    StateNotifierProvider<ImportNotifier, ImportState>((ref) {
  return ImportNotifier(ref);
});

class ImportNotifier extends StateNotifier<ImportState> {
  final Ref _ref;

  ImportNotifier(this._ref) : super(const ImportState());

  /// 拉起文件选择器 → 读取内容 → 按扩展名分派解析 → 进入预览。
  Future<void> pickAndParse() async {
    state = state.copyWith(status: ImportStatus.picking, errorMessage: null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ics', 'json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        // 用户取消，回到空闲。
        state = state.copyWith(status: ImportStatus.idle);
        return;
      }
      final file = result.files.single;
      final ext = (file.extension ?? '').toLowerCase();
      final content = _readContent(file);

      state = state.copyWith(status: ImportStatus.parsing);
      final semester = await _activeSemester();
      if (semester == null) {
        state = state.copyWith(
          status: ImportStatus.error,
          errorMessage: '未找到激活学期，请先到「学期」中创建。',
        );
        return;
      }

      final courses = _parseByType(ext, content, semester);
      if (courses.isEmpty) {
        state = state.copyWith(
          status: ImportStatus.error,
          errorMessage: '未能从文件中解析出任何课程，请检查格式。',
        );
        return;
      }
      state = state.copyWith(
        status: ImportStatus.preview,
        courses: courses,
        totalWeeks: semester.totalWeeks,
        skipped: const [],
      );
    } catch (e) {
      state = state.copyWith(
        status: ImportStatus.error,
        errorMessage: '解析失败：${e.toString()}',
      );
    }
  }

  void toggleSelected(int index) {
    if (index < 0 || index >= state.courses.length) return;
    final list = [...state.courses];
    list[index] = list[index]._copyWithSelected(!list[index].selected);
    state = state.copyWith(courses: list);
  }

  void setAllSelected(bool selected) {
    state = state.copyWith(
      courses: state.courses
          .map((c) => c._copyWithSelected(selected))
          .toList(),
    );
  }

  /// 将勾选的课程批量写入数据库（每条生成新 id）。
  Future<void> confirmImport() async {
    final toImport = state.courses.where((c) => c.selected).toList();
    if (toImport.isEmpty) return;

    final semester = await _activeSemester();
    if (semester == null) return;
    final repo = _ref.read(courseRepositoryProvider);

    state = state.copyWith(status: ImportStatus.importing);
    var count = 0;
    for (final c in toImport) {
      // 每条导入生成独立 id，避免 upsert 时主键碰撞（与课程表单逻辑一致）。
      final course = c.toCourse(semester.id).copyWith(id: const Uuid().v4());
      await repo.upsert(course);
      count++;
    }

    // 刷新依赖课程数据的上游 Provider。
    _ref.invalidate(scheduleCoursesProvider);
    _ref.invalidate(activeSemesterProvider);

    // 导入后同步桌面小组件（今日课程可能变化）。
    try {
      _ref.read(widgetServiceProvider).updateTodayWidget();
    } catch (_) {
      // 小组件刷新失败不应影响导入结果。
    }

    state = state.copyWith(
      status: ImportStatus.done,
      importedCount: count,
      courses: const [],
    );
  }

  void reset() => state = const ImportState();

  // ---- 内部工具 ----

  Future<Semester?> _activeSemester() async {
    final repo = _ref.read(semesterRepositoryProvider);
    return repo.getActiveSemester();
  }

  List<ImportCourse> _parseByType(
    String ext,
    String content,
    Semester semester,
  ) {
    switch (ext) {
      case 'json':
        return JsonCourseImporter.parse(
          content,
          totalWeeks: semester.totalWeeks,
        );
      case 'ics':
      default:
        return IcsCourseParser.parse(
          content,
          semesterStart: semester.startDate,
          totalWeeks: semester.totalWeeks,
        );
    }
  }

  String _readContent(PlatformFile file) {
    if (file.bytes != null) {
      return utf8.decode(file.bytes as Uint8List, allowMalformed: true);
    }
    // 极端情况下无字节（理论上 withData:true 总有），兜底为空。
    return '';
  }
}

/// [ImportCourse] 的私有便捷复制（仅翻转 selected），避免对外暴露可变字段。
extension _ImportCourseCopy on ImportCourse {
  ImportCourse _copyWithSelected(bool selected) =>
      ImportCourse(
        name: name,
        teacher: teacher,
        location: location,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        startTime: startTime,
        endTime: endTime,
        weeks: weeks,
        colorValue: colorValue,
        notes: notes,
        source: source,
        selected: selected,
      );
}
