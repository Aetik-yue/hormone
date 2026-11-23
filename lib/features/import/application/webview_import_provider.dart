import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:recess/features/import/domain/import_course.dart';
import 'package:recess/features/import/domain/webview_course_parser.dart';

export 'package:recess/features/import/domain/webview_course_parser.dart';

/// WebView 教务导入的阶段状态机（select -> login -> preview）。
enum WebviewPhase { select, login, preview }

/// WebView 导入页的不可变状态。
class WebviewImportState {
  final WebviewPhase phase;
  final bool loading;
  final bool extracting;
  final List<ImportCourse> courses;
  final int skippedCount;
  final ImportMode mode;
  final WebviewCoursePreview? preview;

  const WebviewImportState({
    this.phase = WebviewPhase.select,
    this.loading = true,
    this.extracting = false,
    this.courses = const [],
    this.skippedCount = 0,
    this.mode = ImportMode.replace,
    this.preview,
  });

  WebviewImportState copyWith({
    WebviewPhase? phase,
    bool? loading,
    bool? extracting,
    List<ImportCourse>? courses,
    int? skippedCount,
    ImportMode? mode,
    WebviewCoursePreview? preview,
  }) => WebviewImportState(
    phase: phase ?? this.phase,
    loading: loading ?? this.loading,
    extracting: extracting ?? this.extracting,
    courses: courses ?? this.courses,
    skippedCount: skippedCount ?? this.skippedCount,
    mode: mode ?? this.mode,
    preview: preview ?? this.preview,
  );

  int get selectedCount =>
      courses.where((c) => c.selected).fold<int>(0, (n, c) => n + 1);
}

/// WebView 导入控制器：管理阶段、抓取中状态与课程勾选。
///
/// 平台相关操作（WebView 控制器、横竖屏切换、JS 注入、对话框）留在
/// Screen 里，这里只承载可单测的纯状态转换与抓取结果解析。
class WebviewImportNotifier extends StateNotifier<WebviewImportState> {
  WebviewImportNotifier() : super(const WebviewImportState());

  void startLogin() => state = state.copyWith(phase: WebviewPhase.login);

  void setLoading(bool v) => state = state.copyWith(loading: v);

  void setExtracting(bool v) => state = state.copyWith(extracting: v);

  void setMode(ImportMode mode) => state = state.copyWith(mode: mode);

  /// 解析结果进入预览：把 [courses] 全部设为勾选态。
  void showPreview(List<ImportCourse> courses, int skippedCount) {
    state = state.copyWith(
      phase: WebviewPhase.preview,
      courses: courses.map((c) => c.withSelected(true)).toList(growable: false),
      skippedCount: skippedCount,
      extracting: false,
      loading: false,
    );
  }

  void showValidatedPreview(WebviewCoursePreview preview) {
    showPreview(preview.courses, preview.skippedCount);
    state = state.copyWith(preview: preview);
  }

  void toggle(int index) {
    if (index < 0 || index >= state.courses.length) return;
    final list = [...state.courses];
    list[index] = list[index].withSelected(!list[index].selected);
    state = state.copyWith(courses: list);
  }

  /// 全选 ⇄ 取消全选（全部已选时清空，否则全选）。
  void toggleSelectAll() {
    final all = state.courses.length > 0 &&
        state.selectedCount == state.courses.length;
    state = state.copyWith(
      courses: state.courses.map((c) => c.withSelected(!all)).toList(),
    );
  }

  void backToLogin() => state = state.copyWith(phase: WebviewPhase.login);
}

/// WebView 导入状态控制器（页面生命周期内自管理）。
final webviewImportProvider =
    StateNotifierProvider.autoDispose<WebviewImportNotifier, WebviewImportState>(
  (ref) => WebviewImportNotifier(),
);
