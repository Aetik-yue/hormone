import 'dart:convert';
import 'import_course.dart';
import 'webview_preview_context.dart';
export 'webview_preview_context.dart';

/// 解析单层或双层编码的课程列表，以及 adapter 的导航、等待信号。
dynamic decodeWebviewExtractResult(Object? result) {
  try {
    final decoded = jsonDecode(result is String ? result : result.toString());
    return decoded is String ? jsonDecode(decoded) : decoded;
  } catch (_) {
    return null;
  }
}

(List<ImportCourse>, Map<String, int>) _parseCourses(dynamic decoded) {
  final courses = <ImportCourse>[];
  final reasons = <String, int>{};
  if (decoded is! List) return (courses, reasons);
  for (final record in decoded) {
    try {
      if (record is! Map<String, dynamic>) {
        throw const FormatException('课程记录格式无效');
      }
      courses.add(_parseCourse(record));
    } on FormatException catch (e) {
      reasons.update(e.message, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return (courses, reasons);
}

/// 校验单条抓取记录并转换为共同导入表示。
ImportCourse _parseCourse(Map<String, dynamic> json) {
  final name = json['name'];
  if (name is! String || name.trim().isEmpty) {
    throw const FormatException('课程名为空或无效');
  }
  final dayOfWeek = json['dayOfWeek'];
  if (dayOfWeek is! int || dayOfWeek < 1 || dayOfWeek > 7) {
    throw const FormatException('星期缺失或无效');
  }
  final startSection = json['startSection'];
  final endSection = json['endSection'];
  if (startSection is! int || endSection is! int) {
    throw const FormatException('节次缺失或无效');
  }
  if (startSection < 1 ||
      startSection > 16 ||
      endSection < 1 ||
      endSection > 16) {
    throw const FormatException('节次超出第1–16节');
  }
  if (endSection < startSection) {
    throw const FormatException('结束节次早于开始节次');
  }
  final rawWeeks = json['weeks'];
  if (rawWeeks is! List ||
      rawWeeks.isEmpty ||
      rawWeeks.any((w) => w is! int || w < 1)) {
    throw const FormatException('周次缺失或无效');
  }
  final weeks = rawWeeks.cast<int>().toSet().toList()..sort();
  if ((json['teacher'] != null && json['teacher'] is! String) ||
      (json['location'] != null && json['location'] is! String)) {
    throw const FormatException('教师或教室格式无效');
  }
  return ImportCourse(
    name: name.trim(),
    teacher: json['teacher'] as String?,
    location: json['location'] as String?,
    dayOfWeek: dayOfWeek,
    startSection: startSection,
    endSection: endSection,
    weeks: List.unmodifiable(weeks),
    source: 'webview',
  );
}

/// 有效课程、逐条跳过诊断及学期冲突，共同组成一次预览。
class WebviewCoursePreview {
  final List<ImportCourse> courses;
  final Map<String, int> skippedReasons;
  final List<String> weekConflicts;
  final WebviewPreviewContext context;

  WebviewCoursePreview(
    List<ImportCourse> courses,
    Map<String, int> skippedReasons,
    List<String> weekConflicts,
    this.context,
  ) : courses = List.unmodifiable(courses),
      skippedReasons = Map.unmodifiable(skippedReasons),
      weekConflicts = List.unmodifiable(weekConflicts);

  int get skippedCount => skippedReasons.values.fold(0, (a, b) => a + b);
  bool get canSubmit => weekConflicts.isEmpty;
}

WebviewCoursePreview previewWebviewCourses(
  dynamic decoded,
  WebviewPreviewContext context,
) {
  final (courses, reasons) = _parseCourses(decoded);
  final conflicts = <String>[
    for (final course in courses)
      if (course.weeks.last > context.totalWeeks)
        '“${course.name}”明确包含第${course.weeks.last}周，超过本地${context.totalWeeks}周',
  ];
  return WebviewCoursePreview(courses, reasons, conflicts, context);
}
