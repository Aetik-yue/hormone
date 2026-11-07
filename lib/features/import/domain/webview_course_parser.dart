import 'dart:convert';
import 'package:recess/features/import/data/school_adapter.dart';
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
      courses.add(toImportCourse(ExtractedCourse.fromJson(record)));
    } on FormatException catch (e) {
      reasons.update(e.message, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return (courses, reasons);
}

/// 把已校验的抓取记录转换成共同导入表示。
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
