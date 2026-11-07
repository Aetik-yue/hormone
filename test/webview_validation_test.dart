import 'package:recess/core/models/semester.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/webview_parse_helper.dart';
import 'package:recess/features/import/application/webview_import_provider.dart';

void main() {
  test('预览分别报告跳过原因和明确周次冲突且不裁剪', () {
    final context = WebviewPreviewContext.fromSemester(
      Semester(
        id: 's1',
        name: '学期',
        startDate: DateTime(2026, 9, 7),
        totalWeeks: 18,
      ),
    );
    Map<String, dynamic> course(Map<String, dynamic> change) => {
      'name': '高数',
      'dayOfWeek': 1,
      'startSection': 1,
      'endSection': 2,
      'weeks': [1],
      ...change,
    };
    final preview = previewWebviewCourses([
      course({
        'weeks': [19, 1],
      }),
      course({'name': '  '}),
      course({'name': ''}),
      course({'weeks': []}),
      course({'dayOfWeek': 0}),
      42,
    ], context);
    expect(preview.courses.single.weeks, [1, 19]);
    expect(preview.skippedCount, 5);
    expect(preview.skippedReasons, {
      '课程名为空或无效': 2,
      '周次缺失或无效': 1,
      '星期缺失或无效': 1,
      '课程记录格式无效': 1,
    });
    expect(preview.weekConflicts.single, contains('19'));
    expect(preview.canSubmit, isFalse);
    final corrected = previewWebviewCourses(
      [
        course({
          'weeks': [19, 1],
        }),
      ],
      WebviewPreviewContext.fromSemester(
        Semester(
          id: 's1',
          name: '学期',
          startDate: DateTime(2026, 9, 7),
          totalWeeks: 20,
        ),
      ),
    );
    expect(corrected.canSubmit, isTrue);
    expect(corrected.courses.single.weeks, [1, 19]);
  });
  test('教务预览在运行时隔离坏记录并规范化合法课程', () {
    Map<String, dynamic> course(Map<String, dynamic> changes) => {
      'name': '  高 数  ',
      'dayOfWeek': 1,
      'startSection': 1,
      'endSection': 16,
      'weeks': [3, 1, 3, 2],
      ...changes,
    };
    final (courses, skipped) = parseWebviewCourses([
      course({}),
      course({'startSection': 17, 'endSection': 17}),
      course({'endSection': 17}),
      course({'startSection': 4, 'endSection': 3}),
      course({'name': '  '}),
      course({'weeks': []}),
      course({
        'weeks': [1, 2.5],
      }),
      course({'dayOfWeek': 8}),
      course({})..remove('dayOfWeek'),
      course({})..remove('startSection'),
      course({})..remove('endSection'),
      course({
        'weeks': [0, 1],
      }),
    ]);
    expect(courses, hasLength(1));
    expect(courses.single.name, '高 数');
    expect(courses.single.weeks, [1, 2, 3]);
    expect(skipped, 11);
  });
}
