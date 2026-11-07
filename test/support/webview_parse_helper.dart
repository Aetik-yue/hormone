import 'package:recess/core/models/semester.dart';
import 'package:recess/features/import/domain/import_course.dart';
import 'package:recess/features/import/domain/webview_course_parser.dart';

/// 测试用：解析 WebView 提取记录，返回有效课程与跳过条数。
///
/// 与生产预览共用同一次运行时校验（[previewWebviewCourses]）；`totalWeeks`
/// 取足够大的值，周次不会因此产生冲突。
(List<ImportCourse>, int) parseWebviewCourses(dynamic decoded) {
  final preview = previewWebviewCourses(
    decoded,
    WebviewPreviewContext.fromSemester(
      Semester(
        id: 'fixture',
        name: 'fixture',
        startDate: DateTime(2026, 9, 7),
        totalWeeks: 1000,
      ),
    ),
  );
  return (preview.courses, preview.skippedCount);
}
