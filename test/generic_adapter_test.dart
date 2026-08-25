import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/import/data/generic_adapter.dart';

void main() {
  test('传统表格按逻辑网格处理 rowspan 并保持星期列对齐', () async {
    final script = '''
      class Cell {
        constructor(text, attrs = {}) {
          this.innerText = text;
          this.textContent = text;
          this.innerHTML = text.replace(/\\n/g, '<br>');
          this.attrs = attrs;
        }
        getAttribute(name) { return this.attrs[name] || null; }
        querySelectorAll() { return []; }
      }
      class Row {
        constructor(cells) { this.cells = cells; }
        getAttribute() { return null; }
        querySelector() { return null; }
        querySelectorAll(selector) {
          return selector === 'td' || selector === 'td, th' ? this.cells : [];
        }
      }

      const header = new Row([
        new Cell('节次'), new Cell('周一'), new Cell('周二'),
        new Cell('周三'), new Cell('周四'), new Cell('周五'),
        new Cell('周六'), new Cell('周日')
      ]);
      const first = new Row([
        new Cell('1'),
        new Cell('高等数学\\n张老师\\n1-16周\\n东教101', {rowspan: '2'}),
        new Cell(''), new Cell(''), new Cell(''), new Cell(''),
        new Cell(''), new Cell('')
      ]);
      // 周一逻辑列由上一行的 rowspan 占据，因此本行只有其余六天的单元格。
      const second = new Row([
        new Cell('2'), new Cell(''), new Cell(''), new Cell(''),
        new Cell(''), new Cell(''), new Cell('')
      ]);
      const rows = [header, first, second];
      const table = {
        querySelector: function() { return null; },
        querySelectorAll: function(selector) {
          if (selector === 'tbody tr, tr' || selector === 'tr') return rows;
          return [];
        }
      };
      global.document = {
        querySelector: function(selector) {
          return selector === '#kbTable' ? table : null;
        },
        body: { innerText: '' }
      };

      const result = ${GenericAdapter.commonExtractJs};
      process.stdout.write(result);
    ''';

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'hormone_generic_${DateTime.now().microsecondsSinceEpoch}.js',
    );
    await file.writeAsString(script);
    try {
      final result = await Process.run(
        'node',
        [file.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: result.stderr as String?);
      final courses = jsonDecode(result.stdout as String) as List<dynamic>;
      expect(courses, hasLength(1));
      expect(courses.single, {
        'name': '高等数学',
        'teacher': '张老师',
        'location': '东教101',
        'dayOfWeek': 1,
        'startSection': 1,
        'endSection': 2,
        'weeks': List<int>.generate(16, (index) => index + 1),
      });
    } finally {
      if (await file.exists()) await file.delete();
    }
  });
}
