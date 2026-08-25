import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hormone/features/import/data/school_adapter.dart';
import 'package:hormone/features/import/domain/import_course.dart';

/// WebView 教务导入的阶段状态机（select -> login -> preview）。
enum WebviewPhase { select, login, preview }

/// WebView 导入页的不可变状态。
class WebviewImportState {
  final WebviewPhase phase;
  final bool loading;
  final bool extracting;
  final List<ImportCourse> courses;
  final int skippedCount;

  const WebviewImportState({
    this.phase = WebviewPhase.select,
    this.loading = true,
    this.extracting = false,
    this.courses = const [],
    this.skippedCount = 0,
  });

  WebviewImportState copyWith({
    WebviewPhase? phase,
    bool? loading,
    bool? extracting,
    List<ImportCourse>? courses,
    int? skippedCount,
  }) =>
      WebviewImportState(
        phase: phase ?? this.phase,
        loading: loading ?? this.loading,
        extracting: extracting ?? this.extracting,
        courses: courses ?? this.courses,
        skippedCount: skippedCount ?? this.skippedCount,
      );

  int get selectedCount =>
      courses.where((c) => c.selected).fold<int>(0, (n, c) => n + 1);
}

/// WebView 导入控制器：管理阶段、抓取中状态与课程勾选。
///
/// 平台相关操作（WebView 控制器、横竖屏切换、JS 注入、对话框）留在
/// Screen 里，这里只承载可单测的纯状态转换与抓取结果解析。
class WebviewImportNotifier extends StateNotifier<WebviewImportState> {
  /// 导航到课表页后的自动重试次数（frame 内导航不触发 onPageFinished）。
  int navRetry = 0;

  WebviewImportNotifier() : super(const WebviewImportState());

  void startLogin() => state = state.copyWith(phase: WebviewPhase.login);

  void setLoading(bool v) => state = state.copyWith(loading: v);

  void setExtracting(bool v) => state = state.copyWith(extracting: v);

  /// 解析结果进入预览：把 [courses] 全部设为勾选态。
  void showPreview(List<ImportCourse> courses, int skippedCount) {
    state = state.copyWith(
      phase: WebviewPhase.preview,
      courses: courses.map(_withSelected).toList(growable: false),
      skippedCount: skippedCount,
      extracting: false,
      loading: false,
    );
  }

  void toggle(int index) {
    if (index < 0 || index >= state.courses.length) return;
    final list = [...state.courses];
    list[index] = _withSelected(list[index], !list[index].selected);
    state = state.copyWith(courses: list);
  }

  /// 全选 ⇄ 取消全选（全部已选时清空，否则全选）。
  void toggleSelectAll() {
    final all = state.courses.length > 0 &&
        state.selectedCount == state.courses.length;
    state = state.copyWith(
      courses: state.courses.map((c) => _withSelected(c, !all)).toList(),
    );
  }

  void backToLogin() => state = state.copyWith(phase: WebviewPhase.login);
}

ImportCourse _withSelected(ImportCourse c, [bool selected = true]) =>
    ImportCourse(
      name: c.name,
      teacher: c.teacher,
      location: c.location,
      dayOfWeek: c.dayOfWeek,
      startSection: c.startSection,
      endSection: c.endSection,
      startTime: c.startTime,
      endTime: c.endTime,
      weeks: c.weeks,
      colorValue: c.colorValue,
      notes: c.notes,
      source: c.source,
      selected: selected,
    );

/// 解析 WebView 注入脚本返回的原始字符串结果。
///
/// WebView 可能返回双重编码的 JSON（字符串内再包一层字符串），这里展开到
/// 实际结构。返回 null 表示空、Map 携带 `__nav`/`__pending` 导航信号、List
/// 为课程列表。
dynamic decodeWebviewExtractResult(Object? result) {
  var jsonStr = result is String ? result : result.toString();
  dynamic decoded;
  try {
    decoded = jsonDecode(jsonStr);
  } catch (_) {
    // 空/非 JSON 输出按「无数据」处理，由调用方给出提示。
    return null;
  }
  if (decoded is String) decoded = jsonDecode(decoded);
  return decoded;
}

/// 从解码结果提取课程并统计跳过条数。
///
/// 单条记录解析失败（如星期/节次越界、字段缺失）按跳过计，不中断整批导入；
/// 过滤掉无法识别星期的课程（dayOfWeek 越界）。结果不是 List 时返回空列表
/// （由调用方提示格式异常）。
(List<ImportCourse>, int) importCoursesFromDecoded(dynamic decoded) {
  if (decoded is! List) return (const <ImportCourse>[], 0);
  final valid = <ExtractedCourse>[];
  var skipped = 0;
  for (final e in decoded) {
    if (e is! Map<String, dynamic>) {
      skipped++;
      continue;
    }
    final ExtractedCourse c;
    try {
      c = ExtractedCourse.fromJson(e);
    } catch (_) {
      // fromJson 对越界数据有 assert，debug 构建下会抛；当作无法识别跳过。
      skipped++;
      continue;
    }
    if (c.dayOfWeek >= 1 && c.dayOfWeek <= 7) {
      valid.add(c);
    } else {
      skipped++;
    }
  }
  return (valid.map(toImportCourse).toList(growable: false), skipped);
}

/// 把 WebView 抓取的 [ExtractedCourse] 转为统一的导入中间表示。
ImportCourse toImportCourse(ExtractedCourse c) => ImportCourse(
      name: c.name,
      teacher: c.teacher,
      location: c.location,
      dayOfWeek: c.dayOfWeek,
      startSection: c.startSection,
      endSection: c.endSection,
      weeks: c.weeks,
      source: 'webview',
    );

/// WebView 导入状态控制器（页面生命周期内自管理）。
final webviewImportProvider =
    StateNotifierProvider.autoDispose<WebviewImportNotifier, WebviewImportState>(
  (ref) => WebviewImportNotifier(),
);