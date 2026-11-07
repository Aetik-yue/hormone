import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'support/webview_parse_helper.dart';
import 'package:recess/features/import/data/school_adapter.dart';
import 'package:recess/features/import/data/configured_school_adapter.dart';
import 'package:recess/features/import/data/generic_adapter.dart';
import 'package:recess/features/import/data/cqu_adapter.dart';
import 'package:recess/core/models/semester.dart';
import 'package:recess/features/import/application/webview_import_provider.dart';
import 'package:recess/features/import/data/jgsu_adapter.dart';
import 'package:recess/features/import/data/jufe_adapter.dart';
import 'package:recess/features/import/data/ncu_adapter.dart';
import 'package:recess/features/import/data/syuct_adapter.dart';

void main() {
  final adapters = <SchoolAdapter>[
    CquAdapter(),
    GenericAdapter(url: 'https://example.edu'),
    const ConfiguredSchoolAdapter(
      schoolName: '正方',
      loginUrl: 'https://example.edu',
      system: AcademicSystemType.zhengfang,
    ),
    JgsuAdapter(),
    JufeAdapter(),
    NcuAdapter(),
    SyuctAdapter(),
  ];
  for (final adapter in [adapters[0], adapters[1]]) {
    test('${adapter.schoolName} 纯文本兜底保留范围与单双上下文', () async {
      for (final entry
          in {
            '单周': [1, 3, 5, 7],
            '1-8周，单周': [1, 3, 5, 7],
            '2-10周，双周': [2, 4, 6, 8, 10],
            '1-4,9-12周(单)': [1, 3, 9, 11],
          }.entries) {
        final result = await runWeekFixture(
          adapter,
          entry.key,
          totalWeeks: 8,
          textOnly: true,
        );
        expect(result.single['weeks'], entry.value, reason: entry.key);
      }
    });
  }
  test('通用单行明确范围和单双条件共同解析', () async {
    final result = await runWeekFixture(
      adapters[1],
      '1-8周，单周',
      singleLine: true,
      totalWeeks: 18,
    );
    expect(result.single['weeks'], [1, 3, 5, 7]);
  });
  for (final adapter in [adapters[2], JgsuAdapter(), NcuAdapter()]) {
    test('${adapter.schoolName} 接口单条坏记录不截断后续课程', () async {
      final records = await runWeekFixture(adapter, '1周', mixedApi: true);
      final (courses, skipped) = parseWebviewCourses(records);
      expect(courses.map((c) => c.name), ['课程甲', '课程乙']);
      expect(skipped, 2);
    });
  }
  for (final adapter in [adapters[2], NcuAdapter()]) {
    test('${adapter.schoolName} 接口空结果后的通用fallback使用相同上下文', () async {
      final result = await runWeekFixture(
        adapter,
        '单周',
        totalWeeks: 8,
        fallback: true,
      );
      expect(result.single['weeks'], [1, 3, 5, 7]);
    });
  }
  for (final adapter in adapters) {
    for (final total in [8, 18, 20]) {
      test('${adapter.schoolName} 仅单双周使用$total周上下文', () async {
        final odd = await runWeekFixture(adapter, '单周', totalWeeks: total);
        final even = await runWeekFixture(adapter, '双周', totalWeeks: total);
        final expectedOdd = switch (total) {
          8 => [1, 3, 5, 7],
          18 => [1, 3, 5, 7, 9, 11, 13, 15, 17],
          _ => [1, 3, 5, 7, 9, 11, 13, 15, 17, 19],
        };
        final expectedEven = switch (total) {
          8 => [2, 4, 6, 8],
          18 => [2, 4, 6, 8, 10, 12, 14, 16, 18],
          _ => [2, 4, 6, 8, 10, 12, 14, 16, 18, 20],
        };
        expect(odd.single['weeks'], expectedOdd);
        expect(even.single['weeks'], expectedEven);
      });
    }
    test('${adapter.schoolName} 节次坏记录不裁剪或反向修补，交给预览诊断', () async {
      for (final sections in ['17-17', '1-21', '4-3', '1.5-2', '']) {
        final records = await runWeekFixture(
          adapter,
          '1-8周',
          sections: sections,
        );
        final (courses, skipped) = parseWebviewCourses(records);
        expect(courses, isEmpty, reason: sections);
        expect(skipped, 1, reason: sections);
      }
    });
    test('${adapter.schoolName} 明确单双范围与非法周次均不猜补', () async {
      expect((await runWeekFixture(adapter, '1-8周，单周')).single['weeks'], [
        1,
        3,
        5,
        7,
      ]);
      expect((await runWeekFixture(adapter, '2-10周，双周')).single['weeks'], [
        2,
        4,
        6,
        8,
        10,
      ]);
      for (final text in ['1-4,未知周', '1.5周', '8-1周', '0-4周']) {
        final (courses, skipped) = parseWebviewCourses(
          await runWeekFixture(adapter, text),
        );
        expect(courses, isEmpty, reason: text);
        expect(skipped, 1, reason: text);
      }
    });
    test('${adapter.schoolName} 第16节有效且明确19周保留为上下文冲突', () async {
      final records = await runWeekFixture(
        adapter,
        '19周',
        sections: '16-16',
        totalWeeks: 18,
      );
      final preview = previewWebviewCourses(
        records,
        WebviewPreviewContext.fromSemester(
          Semester(
            id: 's',
            name: '学期',
            startDate: DateTime(2026, 9, 7),
            totalWeeks: 18,
          ),
        ),
      );
      expect(preview.courses.single.startSection, 16);
      expect(preview.courses.single.weeks, [19]);
      expect(preview.skippedCount, 0);
      expect(preview.weekConflicts, hasLength(1));
      expect(preview.canSubmit, isFalse);
    });
    test('${adapter.schoolName} 明确离散范围只在原范围内筛单双', () async {
      final result = await runWeekFixture(adapter, '1-4,9-12周(单)');
      expect(result.single['weeks'], [1, 3, 9, 11]);
    });
  }
}

Future<List<dynamic>> runWeekFixture(
  SchoolAdapter adapter,
  String weeks, {
  int? totalWeeks,
  String sections = '1-2',
  bool fallback = false,
  bool mixedApi = false,
  bool textOnly = false,
  bool singleLine = false,
}) async {
  final text = jsonEncode(
    singleLine ? '课程甲 $weeks 1-2节 教室甲' : '课程甲\n$weeks\n教师甲\n教室甲',
  );
  final syuct = jsonEncode('周一第$sections节{第$weeks}\n课程甲\n教室甲');
  final response = jsonEncode({
    'kbList':
        fallback
            ? []
            : [
              {
                'kcmc': '课程甲',
                'xqj': '1',
                'jcs': sections,
                'jc': sections,
                'zcd': weeks,
              },
              if (mixedApi) ...[
                null,
                {
                  'kcmc': '坏记录',
                  'xqj': '1',
                  'jcs': '1-2',
                  'jc': '1-2',
                  'zcd': '1-4,未知周',
                },
                {
                  'kcmc': '课程乙',
                  'xqj': '1',
                  'jcs': '1-2',
                  'jc': '1-2',
                  'zcd': '2周',
                },
              ],
            ],
  });
  final cqu = jsonEncode('本科 - 课程甲[992499-001]\n[$weeks] [$sections节] 教室甲');
  final bodyText =
      !textOnly
          ? ''
          : adapter is CquAdapter
          ? '周一\n[992499-001]\n[$weeks] [$sections节] 教室甲\n本科 - 课程甲'
          : '周一\n课程甲 $weeks ${sections}节 教室甲';
  final script = '''
    console.log = function() {};
    const cell = {
      innerText: ${adapter is CquAdapter
      ? cqu
      : adapter is SyuctAdapter
      ? syuct
      : text},
      textContent: ${adapter is CquAdapter
      ? cqu
      : adapter is SyuctAdapter
      ? syuct
      : text}, innerHTML: '',
      getAttribute: function(name) {
        return {'data-day':'1', 'data-begin-unit':${jsonEncode(sections.split('-').first)}, 'data-start-section':${jsonEncode(sections.split('-').first)}, 'data-end-unit':${jsonEncode(sections.split('-').last)}, 'data-end-section':${jsonEncode(sections.split('-').last)}}[name] || null;
      }, querySelectorAll: function() { return []; }, contains: function() { return false; }, getBoundingClientRect: function() { return {left:42,width:101,height:40}; }
    };
    const row = { getAttribute: function() { return null; },
      querySelector: function() { return cell; },
      querySelectorAll: function() { return [cell]; } };
    const table = { querySelectorAll: function(selector) { return selector === 'td' ? [cell] : [row]; } };
    global.document = {
      body: {innerText: ${jsonEncode(bodyText)}, querySelectorAll: function() { return ${!textOnly && adapter is CquAdapter ? '[cell]' : '[]'}; }},
      getElementById: function() { return ${textOnly ? 'null' : 'table'}; },
      querySelector: function(selector) { return ${textOnly ? 'null' : "/xnm|xqm/.test(selector) ? {value:'2026'} : table"}; },
      querySelectorAll: function(selector) { return ${textOnly ? '[]' : "/frame|table|a|menu/.test(selector) ? [] : [cell]"}; }
    };
    global.window = {location: {hostname:'jwpt.ncu.edu.cn', pathname:'/jwglxt/'}, frames: []};
    global.XMLHttpRequest = function() {
      this.open = function() {}; this.setRequestHeader = function() {};
      this.send = function() {
        this.status = 200;
        this.responseText = ${jsonEncode(response)};
      };
    };
    const result = ${totalWeeks == null ? adapter.extractJs : adapter.extractForSemester(totalWeeks)};
    process.stdout.write(result);
  ''';
  final directory = await Directory.systemTemp.createTemp('recess_weeks_');
  final file = File('${directory.path}/fixture.js');
  try {
    await file.writeAsString(script);
    final result = await Process.run(
      'node',
      [file.path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return jsonDecode(result.stdout as String) as List<dynamic>;
  } finally {
    await directory.delete(recursive: true);
  }
}
