import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/features/import/application/webview_import_provider.dart';
import 'package:hormone/features/import/domain/import_course.dart';

void main() {
  group('decodeWebviewExtractResult', () {
    test('单层编码的课程列表正常解码', () {
      final decoded = decodeWebviewExtractResult(
        '[{"name": "高等数学", "dayOfWeek": 1, "startSection": 1, '
        '"endSection": 2, "weeks": [1,2]}]',
      );
      expect(decoded, isA<List>());
      expect((decoded as List).single['name'], '高等数学');
    });

    test('双重编码（字符串内再包一层字符串）被展开', () {
      const inner = '[{"name": "线性代数"}]';
      // 真实 WebView 双重编码：外层字符串经过 JSON 转义（引号被转义）。
      final doubleEncoded = jsonEncode(inner);
      final decoded = decodeWebviewExtractResult(doubleEncoded);
      expect(decoded, isA<List>());
    });

    test('__nav 导航信号被识别', () {
      final decoded =
          decodeWebviewExtractResult('{"__nav": true, "url": "..."}');
      expect(decoded, isA<Map>());
      expect((decoded as Map)['__nav'], true);
    });

    test('__pending 等待信号被识别', () {
      final decoded = decodeWebviewExtractResult('{"__pending": true}');
      expect((decoded as Map)['__pending'], true);
    });

    test('空字符串/非 JSON 返回 null 而不抛出', () {
      expect(decodeWebviewExtractResult(''), isNull);
      expect(decodeWebviewExtractResult('[oops]'), isNull);
    });
  });

  group('importCoursesFromDecoded', () {
    test('过滤无法识别星期的课程并统计跳过数', () {
      final decoded = [
        {'name': 'A', 'dayOfWeek': 1, 'startSection': 1, 'endSection': 1, 'weeks': [1]},
        {'name': 'B', 'dayOfWeek': 0, 'startSection': 1, 'endSection': 1, 'weeks': [1]},
        {'name': 'C', 'dayOfWeek': 7, 'startSection': 2, 'endSection': 2, 'weeks': [2]},
      ];
      final (courses, skipped) = importCoursesFromDecoded(decoded);
      expect(courses, hasLength(2));
      expect(courses.map((c) => c.name), unorderedEquals(['A', 'C']));
      expect(skipped, 1);
    });

    test('非 List 返回空且不算跳过', () {
      final (courses, skipped) = importCoursesFromDecoded('not a list');
      expect(courses, isEmpty);
      expect(skipped, 0);
    });

    test('转换结果保留原始字段', () {
      final (courses, _) = importCoursesFromDecoded([
        {
          'name': '高数',
          'teacher': '张三',
          'location': '教三',
          'dayOfWeek': 2,
          'startSection': 3,
          'endSection': 4,
          'weeks': [1, 2, 3],
        },
      ]);
      final c = courses.single;
      expect(c.name, '高数');
      expect(c.teacher, '张三');
      expect(c.location, '教三');
      expect(c.dayOfWeek, 2);
      expect(c.startSection, 3);
      expect(c.endSection, 4);
      expect(c.weeks, [1, 2, 3]);
      expect(c.source, 'webview');
    });
  });

  group('WebviewImportNotifier', () {
    late WebviewImportNotifier notifier;

    setUp(() => notifier = WebviewImportNotifier());

    tearDown(() => notifier.dispose());

    test('初始为选择阶段且不选中任何课程', () {
      expect(notifier.state.phase, WebviewPhase.select);
      expect(notifier.state.selectedCount, 0);
    });

    test('startLogin 进入登录阶段', () {
      notifier.startLogin();
      expect(notifier.state.phase, WebviewPhase.login);
    });

    test('showPreview 进入预览并将全部课程置为勾选', () {
      notifier.showPreview(_courses(3), 1);
      expect(notifier.state.phase, WebviewPhase.preview);
      expect(notifier.state.courses, hasLength(3));
      expect(notifier.state.selectedCount, 3);
      expect(notifier.state.skippedCount, 1);
    });

    test('toggle 翻转单门课程的勾选', () {
      notifier.showPreview(_courses(2), 0);
      notifier.toggle(0);
      expect(notifier.state.selectedCount, 1);
      notifier.toggle(0);
      expect(notifier.state.selectedCount, 2);
    });

    test('toggleSelectAll 全选⇄取消全选', () {
      notifier.showPreview(_courses(2), 0);
      notifier.toggleSelectAll(); // 全部已选 → 取消全选
      expect(notifier.state.selectedCount, 0);
      notifier.toggleSelectAll(); // 全不选 → 全选
      expect(notifier.state.selectedCount, 2);
    });

    test('backToLogin 从预览回到登录', () {
      notifier.showPreview(_courses(1), 0);
      notifier.backToLogin();
      expect(notifier.state.phase, WebviewPhase.login);
    });
  });
}

List<ImportCourse> _courses(int n) => [
      for (var i = 0; i < n; i++)
        ImportCourse(
          name: '课程$i',
          dayOfWeek: (i % 7) + 1,
          startSection: 1,
          endSection: 2,
          weeks: const [1, 2, 3],
          source: 'webview',
        ),
    ];