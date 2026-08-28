import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/import/data/jufe_adapter.dart';
import 'package:hormone/features/import/data/school_adapter.dart';

void main() {
  final adapter = JufeAdapter();

  test('使用江西财经大学当前教务入口并识别常见课表 URL', () {
    expect(adapter.schoolName, '江西财经大学');
    expect(adapter.loginUrl, 'http://xk.jxufe.edu.cn/');
    expect(adapter.scheduleUrl, 'http://xk.jxufe.edu.cn/');
    expect(
      adapter.isSchedulePage(
        'http://xk.jxufe.edu.cn/student/course/schedule',
      ),
      isTrue,
    );
    expect(
      adapter.isSchedulePage('http://xk.jxufe.edu.cn/xsjxgl/xskbcx'),
      isTrue,
    );
    expect(adapter.isSchedulePage(adapter.loginUrl), isFalse);
    expect(adapter.supportLevel, AdapterSupportLevel.schoolVerified);
    expect(adapter.systemName, '专用适配');
  });

  test('新版 data 属性表格解析星期、节次、周次、教师与地点', () async {
    final courses = await _runExtractor(r'''
      const cell = {
        innerText: '微观经济学\n1-8周(单)\n张老师\n蛟桥园教一101',
        textContent: '微观经济学\n1-8周(单)\n张老师\n蛟桥园教一101',
        getAttribute: function(name) {
          if (name === 'data-day') return '2';
          if (name === 'data-start-section') return '3';
          if (name === 'data-end-section') return '4';
          return null;
        }
      };
      const row = {
        getAttribute: function() { return null; },
        querySelectorAll: function(selector) {
          return selector.indexOf('td') >= 0 ? [cell] : [];
        }
      };
      const table = {querySelectorAll: function(selector) {
        return selector.indexOf('tr') >= 0 ? [row] : [];
      }};
      global.document = {
        querySelector: function() { return table; },
        querySelectorAll: function(selector) {
          return selector.indexOf('frame') >= 0 ? [] : [];
        }
      };
    ''');

    expect(courses, hasLength(1));
    expect(courses.single, {
      'name': '微观经济学',
      'teacher': '张老师',
      'location': '蛟桥园教一101',
      'dayOfWeek': 2,
      'startSection': 3,
      'endSection': 4,
      'weeks': [1, 3, 5, 7],
    });
  });

  test('传统表格使用 rowspan 计算连续节次', () async {
    final courses = await _runExtractor(r'''
      function cell(text, rowspan) {
        return {
          textContent: text,
          innerText: text,
          getAttribute: function(name) {
            return name === 'rowspan' ? rowspan : null;
          }
        };
      }
      const header = {querySelectorAll: function() {
        return [cell('节次', null), cell('星期一', null), cell('星期二', null)];
      }};
      const courseRow = {querySelectorAll: function(selector) {
        if (selector === 'td') {
          return [cell('5', null), cell('', null),
            cell('财政学\n1-16周\n王老师\n麦庐园教二203', '2')];
        }
        return [];
      }};
      const table = {querySelectorAll: function(selector) {
        if (selector === 'tr') return [header, courseRow];
        if (selector.indexOf('tbody tr') >= 0) return [courseRow];
        return [];
      }};
      global.document = {
        querySelector: function() { return table; },
        querySelectorAll: function(selector) {
          return selector.indexOf('frame') >= 0 ? [] : [];
        }
      };
    ''');

    expect(courses, hasLength(1));
    expect(courses.single['name'], '财政学');
    expect(courses.single['dayOfWeek'], 2);
    expect(courses.single['startSection'], 5);
    expect(courses.single['endSection'], 6);
  });

  test('未进入课表时点击课程安排明细入口并请求自动重试', () async {
    final result = await _runExtractorRaw(r'''
      const link = {
        textContent: '网上选课 - 课程安排明细',
        getAttribute: function(name) {
          return name === 'href' ? '/student/courseArrange/detail' : null;
        },
        click: function() { global.__clicked = true; }
      };
      global.document = {
        querySelector: function() { return null; },
        querySelectorAll: function(selector) {
          if (selector.indexOf('frame') >= 0 || selector === 'table') return [];
          if (selector.indexOf('menuitem') >= 0) return [link];
          return [];
        }
      };
    ''');

    expect(result, isA<Map<String, dynamic>>());
    expect(result['__nav'], isTrue);
  });
}

Future<List<Map<String, dynamic>>> _runExtractor(String setup) async {
  final result = await _runExtractorRaw(setup);
  expect(result, isA<List<dynamic>>(), reason: '期望课程数组，实际: $result');
  return (result as List).cast<Map<String, dynamic>>();
}

Future<dynamic> _runExtractorRaw(String setup) async {
  final script = '''
    $setup
    const result = ${JufeAdapter().extractJs};
    process.stdout.write(result);
  ''';
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'hormone_jufe_${DateTime.now().microsecondsSinceEpoch}.js',
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
    return jsonDecode(result.stdout as String);
  } finally {
    if (await file.exists()) await file.delete();
  }
}
