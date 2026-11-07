import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'support/node_extractor.dart';
import 'package:recess/features/import/data/ncu_adapter.dart';
import 'package:recess/features/import/data/school_adapter.dart';

void main() {
  final adapter = NcuAdapter();

  test('使用南昌大学官方统一认证入口并识别个人课表页', () {
    expect(adapter.schoolName, '南昌大学');
    expect(adapter.loginUrl, 'https://jwpt.ncu.edu.cn/jsxsd/sso.jsp');
    expect(
      adapter.isSchedulePage(
        'https://jwxt.ncu.edu.cn/student/course/schedule',
      ),
      isTrue,
    );
    expect(adapter.isSchedulePage(adapter.loginUrl), isFalse);
    expect(adapter.supportLevel, AdapterSupportLevel.schoolVerified);
    expect(adapter.systemName, '专用适配');
  });

  test('登录态接口解析 jcs 节次、单双周、教师与教室', () async {
    final courses = await _runExtractor(r'''
      global.window = {};
      global.document = {
        querySelector: function(selector) {
          if (selector.indexOf('xnm') >= 0) return {value: '2026'};
          if (selector.indexOf('xqm') >= 0) return {value: '12'};
          return null;
        },
        querySelectorAll: function() { return []; }
      };
      global.XMLHttpRequest = function() {
        this.open = function() {};
        this.setRequestHeader = function() {};
        this.send = function() {
          this.status = 200;
          this.responseText = JSON.stringify({kbList: [{
            kcmc: '高等数学', xqj: '3', jcs: '第3-4节',
            zcd: '1-8周(单)', xm: '张老师', cdmc: '前湖校区教一101'
          }]});
        };
      };
    ''');

    expect(courses, hasLength(1));
    expect(courses.single, {
      'name': '高等数学',
      'teacher': '张老师',
      'location': '前湖校区教一101',
      'dayOfWeek': 3,
      'startSection': 3,
      'endSection': 4,
      'weeks': [1, 3, 5, 7],
    });
  });

  test('新平台跳过旧接口并使用 data 属性表格兜底', () async {
    final courses = await _runExtractor(r'''
      global.window = {location: {
        hostname: 'jwxt.ncu.edu.cn', pathname: '/student/course/schedule'
      }};
      const cell = {
        innerText: '大学物理\n1-6周\n陈老师\n建工楼301',
        textContent: '大学物理\n1-6周\n陈老师\n建工楼301',
        innerHTML: '',
        getAttribute: function(name) {
          if (name === 'data-day') return '4';
          if (name === 'data-begin-unit') return '5';
          if (name === 'data-end-unit') return '6';
          return null;
        }
      };
      const row = {
        getAttribute: function() { return null; },
        querySelector: function(selector) {
          return selector.indexOf('data-day') >= 0 ? cell : null;
        },
        querySelectorAll: function(selector) {
          return selector.indexOf('td') >= 0 ? [cell] : [];
        }
      };
      const table = {querySelectorAll: function(selector) {
        return selector.indexOf('tr') >= 0 ? [row] : [];
      }};
      global.document = {
        body: table,
        querySelector: function(selector) {
          return selector.indexOf('#kbTable') >= 0 ? table : null;
        },
        querySelectorAll: function(selector) {
          if (selector.indexOf('frame') >= 0) return [];
          return [];
        }
      };
      global.XMLHttpRequest = function() {
        throw new Error('新平台不应请求旧强智接口');
      };
    ''');

    expect(courses, hasLength(1));
    expect(courses.single['name'], '大学物理');
    expect(courses.single['dayOfWeek'], 4);
    expect(courses.single['startSection'], 5);
    expect(courses.single['endSection'], 6);
    expect(courses.single['weeks'], [1, 2, 3, 4, 5, 6]);
  });

  test('秋季学期按当年学年请求并兼容 datas.rows 响应', () async {
    final courses = await _runExtractor(r'''
      global.window = {};
      global.document = {
        querySelector: function() { return null; },
        querySelectorAll: function() { return []; }
      };
      global.XMLHttpRequest = function() {
        this.open = function() {};
        this.setRequestHeader = function() {};
        this.send = function(body) {
          if (String(body).indexOf('xnm=2026&xqm=12') >= 0) {
            this.status = 200;
            this.responseText = JSON.stringify({datas: {rows: [{
              courseName: '大学英语', weekDayName: '星期二',
              sections: '1-2节', weekDescription: '2-6周(双)',
              teacherName: '李老师', classroomName: '外经楼201'
            }]}});
          } else {
            this.status = 200;
            this.responseText = JSON.stringify({kbList: []});
          }
        };
      };
      const RealDate = Date;
      global.Date = class extends RealDate {
        constructor(...args) {
          if (args.length === 0) super(2026, 9, 15);
          else super(...args);
        }
      };
    ''');

    expect(courses, hasLength(1));
    expect(courses.single['name'], '大学英语');
    expect(courses.single['dayOfWeek'], 2);
    expect(courses.single['weeks'], [2, 4, 6]);
  });

  test('接口与 DOM 均无课程时点击学生个人课表入口', () async {
    final (result, clicked) = await runAdapterExtractorProbe(adapter, r'''
      global.window = {};
      const link = {
        textContent: '学生个人课表',
        href: '/jsxsd/kbcx/xskbcx_cxXsgg.html',
        click: function() { global.__clicked = true; }
      };
      global.document = {
        querySelector: function() { return null; },
        querySelectorAll: function(selector) {
          if (selector.indexOf('menuitem') >= 0) return [link];
          return [];
        }
      };
      global.XMLHttpRequest = function() {
        this.open = function() {};
        this.setRequestHeader = function() {};
        this.send = function() { this.status = 500; this.responseText = ''; };
      };
    ''', probe: 'global.__clicked === true', tag: 'ncu_nav');

    expect(result, isA<Map<String, dynamic>>());
    expect(result['__nav'], isTrue);
    expect(clicked, isTrue);
  });

  test('课表渲染在 iframe 内时同样能解析（遍历同源 frame）', () async {
    final courses = await _runExtractor(r'''
      global.window = {location: {
        hostname: 'jwxt.ncu.edu.cn', pathname: '/student/course/schedule'
      }};
      const cell = {
        innerText: '高等数学\n周一第1-2节{第1-16周}\nA-201',
        textContent: '高等数学\n周一第1-2节{第1-16周}\nA-201'
      };
      const iframeDoc = {querySelectorAll: function(selector) {
        return selector.indexOf('td') >= 0 ? [cell] : [];
      }};
      const iframeEl = {contentDocument: iframeDoc};
      global.document = {
        querySelector: function() { return null; },
        querySelectorAll: function(selector) {
          if (selector.indexOf('frame') >= 0) return [iframeEl];
          return [];
        }
      };
      global.XMLHttpRequest = function() {
        throw new Error('新平台不应请求旧强智接口');
      };
    ''');

    expect(courses, hasLength(1));
    expect(courses.single['name'], '高等数学');
    expect(courses.single['location'], 'A-201');
    expect(courses.single['dayOfWeek'], 1);
    expect(courses.single['startSection'], 1);
    expect(courses.single['endSection'], 2);
    expect(courses.single['weeks'], List<int>.generate(16, (i) => i + 1));
  });

  test('课表容器存在但未渲染出课程时返回 __pending', () async {
    final result = await _runExtractorRaw(r'''
      global.window = {location: {
        hostname: 'jwxt.ncu.edu.cn', pathname: '/student/course/schedule'
      }};
      const container = {querySelectorAll: function() { return []; }};
      global.document = {
        body: {innerText: '', querySelectorAll: function() { return []; }},
        querySelector: function(selector) {
          return selector.indexOf('#kbTable') >= 0 ? container : null;
        },
        querySelectorAll: function() { return []; }
      };
      global.XMLHttpRequest = function() {
        throw new Error('新平台不应请求旧强智接口');
      };
    ''');

    expect(result, isA<Map<String, dynamic>>());
    expect(result['__pending'], isTrue);
  });

  test('同一课程不同教室按名称/星期/节次/周次去重，先出现者生效', () async {
    final courses = await _runExtractor(r'''
      global.window = {location: {
        hostname: 'jwxt.ncu.edu.cn', pathname: '/student/course/schedule'
      }};
      function makeCell(sections, location) {
        return {
          innerText: '高等数学\n周一第' + sections + '节{第1-16周}\n' + location,
          textContent: '高等数学\n周一第' + sections + '节{第1-16周}\n' + location
        };
      }
      const first = makeCell('1-2', 'A-201');
      const second = makeCell('1-2', 'B-302');
      const third = makeCell('3-4', 'C-403');
      global.document = {
        querySelector: function() { return null; },
        querySelectorAll: function(selector) {
          if (selector.indexOf('frame') >= 0) return [];
          return selector.indexOf('td') >= 0 ? [first, second, third] : [];
        }
      };
      global.XMLHttpRequest = function() {
        throw new Error('新平台不应请求旧强智接口');
      };
    ''');

    expect(courses, hasLength(2));
    expect(courses.map((c) => c['location']), ['A-201', 'C-403']);
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
    const result = ${NcuAdapter().extractJs};
    process.stdout.write(result);
  ''';
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'recess_ncu_${DateTime.now().microsecondsSinceEpoch}.js',
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
