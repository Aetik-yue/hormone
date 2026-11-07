import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'support/node_extractor.dart';
import 'support/webview_parse_helper.dart';
import 'package:recess/features/import/data/generic_adapter.dart';
import 'package:recess/features/import/data/configured_school_adapter.dart';
import 'package:recess/features/import/data/ncu_adapter.dart';
import 'package:recess/features/import/data/school_adapter.dart';

void main() {
  for (final adapter in <SchoolAdapter>[
    GenericAdapter(url: 'https://example.edu'),
    const ConfiguredSchoolAdapter(
      schoolName: '正方', loginUrl: 'https://example.edu',
      system: AcademicSystemType.zhengfang,
    ),
    NcuAdapter(),
  ]) {
    test('${adapter.schoolName} 单行逗号字段与周次列表均完整保留', () async {
      for (final separator in [',', '，']) {
        for (final entry in {
          '1-8周': [1, 2, 3, 4, 5, 6, 7, 8],
          '1-4,9-12周(单)': [1, 3, 9, 11],
          '1-4，9-12周，单周': [1, 3, 9, 11],
          '1,3,5周': [1, 3, 5],
          '1-4, 9-12周，单周': [1, 3, 9, 11],
        }.entries) {
          final records = await _runSingleLine(
            adapter, ['课程甲', '教师甲', '教室甲', entry.key].join(separator),
          );
          final (courses, skipped) = parseWebviewCourses(records);
          expect(skipped, 0, reason: '$separator ${entry.key}');
          expect(courses.single.name, '课程甲');
          expect(courses.single.weeks, entry.value);
        }
      }
      final (invalid, skipped) = parseWebviewCourses(
        await _runSingleLine(adapter, '课程甲,教师甲,教室甲,1-4,未知周,单周'),
      );
      expect(invalid, isEmpty);
      expect(skipped, 1);
    });
  }

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
      'recess_generic_${DateTime.now().microsecondsSinceEpoch}.js',
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

  test('正方接口按名称/星期/节次/周次去重，教师与教室不参与键', () async {
    const adapter = ConfiguredSchoolAdapter(
      schoolName: '正方',
      loginUrl: 'https://example.edu',
      system: AcademicSystemType.zhengfang,
    );
    final courses = await runAdapterCourses(adapter, r'''
      global.window = {location: {pathname: '/jwglxt/'}};
      global.document = {
        querySelector: function() { return null; },
        querySelectorAll: function() { return []; },
        body: {innerText: ''}
      };
      global.XMLHttpRequest = function() {
        this.open = function() {};
        this.setRequestHeader = function() {};
        this.send = function() {
          this.status = 200;
          this.responseText = JSON.stringify({kbList: [
            {kcmc: '高等数学', xqj: '1', jcs: '1-2', zcd: '1-16周',
             xm: '张老师', cdmc: 'A-201'},
            {kcmc: '高等数学', xqj: '1', jcs: '1-2', zcd: '1-16周',
             xm: '李老师', cdmc: 'B-302'},
            {kcmc: '高等数学', xqj: '1', jcs: '3-4', zcd: '1-16周',
             xm: '张老师', cdmc: 'A-201'}
          ]});
        };
      };
    ''', tag: 'zhengfang_dedupe');

    expect(courses, hasLength(2));
    expect(courses.map((c) => c['teacher']), ['张老师', '张老师']);
    expect(courses.map((c) => c['location']), ['A-201', 'A-201']);
    expect(courses.map((c) => c['startSection']), [1, 3]);
  });
}

Future<List<dynamic>> _runSingleLine(SchoolAdapter adapter, String text) async {
  final script = '''
    class Cell {
      constructor(text, attrs = {}) {
        this.innerText = this.textContent = text; this.attrs = attrs;
      }
      getAttribute(name) { return this.attrs[name] || null; }
      querySelectorAll() { return []; }
    }
    const cells = [new Cell(${jsonEncode(text)}, {
      'data-day':'1', 'data-begin-unit':'1', 'data-end-unit':'2'
    })];
    const row = {
      getAttribute() { return null; },
      querySelector(selector) { return cells.find(c => selector.split(',').some(
        s => /^\\[([^\\]]+)\\]\$/.test(s.trim()) && c.getAttribute(s.trim().slice(1,-1))
      )) || null; },
      querySelectorAll(selector) {
        return selector.split(',').some(s => s.trim() === 'td') ? cells : [];
      }
    };
    const table = {
      querySelectorAll(selector) {
        return selector.split(',').some(s => /(^| )tr\$/.test(s.trim())) ? [row]
          : selector === 'td' ? cells : [];
      }
    };
    global.document = {
      querySelector(selector) {
        return selector.split(',').some(s => s.trim() === '#kbTable') ? table : null;
      },
      querySelectorAll(selector) {
        const selectors = selector.split(',').map(s => s.trim());
        if (selectors.includes('table')) return [table];
        if (selectors.includes('td')) return cells;
        return [];
      },
      body: {innerText:''}
    };
    global.window = {location:{hostname:'example.edu',pathname:'/jwglxt/'}};
    global.XMLHttpRequest = function() {
      this.open = function() {}; this.setRequestHeader = function() {};
      this.send = function() { this.status = 200; this.responseText = '{"kbList":[]}'; };
    };
    const result = ${adapter.extractForSemester(18)};
    process.stdout.write(result);
  ''';
  final directory = await Directory.systemTemp.createTemp('recess_single_line_');
  try {
    final file = File('${directory.path}/fixture.js');
    await file.writeAsString(script);
    final result = await Process.run('node', [file.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return jsonDecode(result.stdout as String) as List<dynamic>;
  } finally {
    await directory.delete(recursive: true);
  }
}
