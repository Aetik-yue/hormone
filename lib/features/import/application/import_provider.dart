import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:recess/core/models/course_platform.dart';
import 'package:recess/core/models/import_diagnostic.dart';
import 'package:recess/core/models/semester.dart';
import 'package:recess/data/providers/database_providers.dart';
import 'package:recess/features/import/domain/import_course.dart';
import 'package:recess/features/import/application/import_commit.dart';
import 'package:recess/features/import/data/ics_parser.dart';
import 'package:recess/features/import/data/json_importer.dart';

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

  /// 本次文件的逐条导入诊断：随预览、错误、提交失败与完成状态保留，
  /// 选择新文件时整体清理（见 [ImportNotifier.pickAndParse]）。
  final List<ImportDiagnostic> diagnostics;
  final ImportMode mode;

  /// JSON 文件里按课程名给出的课程平台，确认导入时写入目标学期。
  final CoursePlatformGroups platforms;

  const ImportState({
    this.status = ImportStatus.idle,
    this.courses = const [],
    this.errorMessage,
    this.importedCount = 0,
    this.diagnostics = const [],
    this.mode = ImportMode.replace,
    this.platforms = const {},
  });

  ImportState copyWith({
    ImportStatus? status,
    List<ImportCourse>? courses,
    String? errorMessage,
    int? importedCount,
    List<ImportDiagnostic>? diagnostics,
    ImportMode? mode,
    CoursePlatformGroups? platforms,
  }) =>
      ImportState(
        status: status ?? this.status,
        courses: courses ?? this.courses,
        errorMessage: errorMessage ?? this.errorMessage,
        importedCount: importedCount ?? this.importedCount,
        diagnostics: diagnostics ?? this.diagnostics,
        mode: mode ?? this.mode,
        platforms: platforms ?? this.platforms,
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
    // 防止重入：已在进行中时忽略后续调用。
    if (state.status != ImportStatus.idle &&
        state.status != ImportStatus.error &&
        state.status != ImportStatus.done) {
      return;
    }
    // 换文件：旧文件的课程、平台与诊断一并清理，避免跨文件串用。
    state = state.copyWith(
      status: ImportStatus.picking,
      errorMessage: null,
      courses: const [],
      diagnostics: const [],
      platforms: const {},
    );
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

      final (courses, platforms, diagnostics) =
          _parseByType(ext, content, semester);
      if (courses.isEmpty) {
        state = state.copyWith(
          status: ImportStatus.error,
          errorMessage: '未能从文件中解析出任何课程，请检查格式。',
          diagnostics: diagnostics,
        );
        return;
      }
      state = state.copyWith(
        status: ImportStatus.preview,
        courses: courses,
        diagnostics: diagnostics,
        platforms: platforms,
      );
    } catch (e) {
      state = state.copyWith(
        status: ImportStatus.error,
        errorMessage: '解析失败：${e.toString()}',
        diagnostics: const [],
      );
    }
  }

  void toggleSelected(int index) {
    if (index < 0 || index >= state.courses.length) return;
    final list = [...state.courses];
    list[index] = list[index].withSelected(!list[index].selected);
    state = state.copyWith(courses: list);
  }

  void setAllSelected(bool selected) {
    state = state.copyWith(
      courses: state.courses.map((c) => c.withSelected(selected)).toList(),
    );
  }

  /// 用勾选的课程替换当前学期课表（每条生成新 id）。
  void setMode(ImportMode mode) => state = state.copyWith(mode: mode);

  Future<ImportSubmission?> prepareImport() async {
    final snapshot = state;
    if (snapshot.selectedCount == 0 ||
        snapshot.status == ImportStatus.importing) {
      return null;
    }
    final semester = await _activeSemester();
    if (semester == null) return null;
    return ImportSubmission.file(
      semesterId: semester.id,
      mode: snapshot.mode,
      courses: snapshot.courses,
      platforms: snapshot.platforms,
    );
  }

  Future<void> confirmImport([ImportSubmission? submission]) async {
    if (state.status == ImportStatus.importing) return;
    submission ??= await prepareImport();
    if (submission == null || submission.courses.isEmpty) return;
    state = state.copyWith(status: ImportStatus.importing);
    try {
      final count = await _ref.read(importCommitProvider).commit(submission);
      state = state.copyWith(
        status: ImportStatus.done,
        importedCount: count,
        courses: const [],
      );
    } catch (e) {
      state = state.copyWith(
        status: ImportStatus.preview,
        errorMessage: '导入失败：$e',
      );
    }
  }

  void reset() => state = const ImportState();

  // ---- 内部工具 ----

  Future<Semester?> _activeSemester() async {
    final repo = _ref.read(semesterRepositoryProvider);
    return repo.getActiveSemester();
  }

  (List<ImportCourse>, CoursePlatformGroups, List<ImportDiagnostic>)
      _parseByType(
    String ext,
    String content,
    Semester semester,
  ) {
    switch (ext) {
      case 'json':
        final result = JsonCourseImporter.parse(
          content,
          totalWeeks: semester.totalWeeks,
        );
        return (result.courses, result.platforms, result.diagnostics);
      case 'ics':
        // ICS 不携带课程平台；无效事件的原因按源事件记入诊断。
        final diagnostics = <ImportDiagnostic>[];
        return (
          IcsCourseParser.parse(
            content,
            semesterStart: semester.startDate,
            totalWeeks: semester.totalWeeks,
            diagnostics: diagnostics,
          ),
          const {},
          diagnostics,
        );
      default:
        // 不支持的格式，返回空。
        return (
          const <ImportCourse>[],
          const {},
          const <ImportDiagnostic>[],
        );
    }
  }

  String _readContent(PlatformFile file) {
    if (file.bytes != null) {
      return utf8.decode(file.bytes as Uint8List, allowMalformed: true);
    }
    // withData:true 应始终提供字节；缺失视为错误。
    throw Exception('无法读取文件内容，请重试。');
  }
}
