import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/import/data/jgsu_adapter.dart';

void main() {
  final adapter = JgsuAdapter();

  test('入口与课表页识别：ehall 大厅登录，jwapp/wdkb 为课表页', () {
    expect(adapter.schoolName, '井冈山大学');
    expect(adapter.loginUrl, 'https://ehall.jgsu.edu.cn/');
    expect(
      adapter.scheduleUrl,
      'https://ehall.jgsu.edu.cn/jwapp/sys/wdkb/index.do',
    );
    expect(
      adapter.isSchedulePage(
          'https://ehall.jgsu.edu.cn/jwapp/sys/wdkb/index.do'),
      isTrue,
    );
    expect(
      adapter.isSchedulePage(
          'https://xsfw.jgsu.edu.cn/jwapp/sys/wdkb/modules/xskcb/xsallkb.do'),
      isTrue,
    );
    expect(
      adapter.isSchedulePage(
          'https://ehall.jgsu.edu.cn/ywtb-portal/official/index.html'),
      isFalse,
    );
    expect(adapter.isSchedulePage(adapter.loginUrl), isFalse);
    expect(adapter.supportLevel.toString(), contains('systemCompatible'));
    expect(adapter.systemName, '金智智慧校园');
  });

  test('登录态 jwapp 接口：解析 kbList（周次/节次/单双周/星期文本）', () async {
    final courses = await _runExtractor(r'''
      global.document = { querySelectorAll: function() { return []; } };
      global.XMLHttpRequest = function() {
        this.open = function() {};
        this.setRequestHeader = function() {};
        this.send = function() {
          this.status = 200;
          this.responseText = JSON.stringify({ datas: { xsallkb: { rows: [
            {
              kcmc: '高等数学', xqj: '1', jc: '1-2节',
              zcd: '1-16周', xm: '张老师', cdmc: '教A-201'
            },
            {
              kcmc: '大学英语', xqj: '3', jc: '3-4节',
              zcd: '1-15周(单)', xm: '李老师', cdmc: '教B-102'
            },
            {
              kcmc: '体育', xqjmc: '周四', jc: '5,6',
              zcd: '2-16周(双)', xm: null, cdmc: '田径场'
            }
          ] } } });
        };
      };
    ''', endpoint: '/jwapp/sys/wdkb/modules/xskcb/xsallkb.do');

    expect(courses, hasLength(3));
    expect(courses[0], {
      'name': '高等数学',
      'teacher': '张老师',
      'location': '教A-201',
      'dayOfWeek': 1,
      'startSection': 1,
      'endSection': 2,
      'weeks': [for (var i = 1; i <= 16; i++) i],
    });
    expect(courses[1]['weeks'], [1, 3, 5, 7, 9, 11, 13, 15]);
    expect(courses[2]['dayOfWeek'], 4);
    expect(courses[2]['weeks'], [2, 4, 6, 8, 10, 12, 14, 16]);
    expect(courses[2]['startSection'], 5);
    expect(courses[2]['endSection'], 6);
  });

  test('接口失败时 DOM data 属性兜底，__nav 兜底点击课表入口', () async {
    // 无 XHR 数据、但页面有带 data-* 属性的金智 el-table 课表。
    final courses = await _runExtractor(r'''
      global.XMLHttpRequest = function() {
        this.open = function() {};
        this.setRequestHeader = function() {};
        this.send = function() { this.status = 500; };
      };
      const cell = {
        innerText: '高等数学\n1-16周\n张老师\n教A-201',
        getAttribute: function(name) {
          if (name === 'data-week') return '2';
          if (name === 'data-begin-unit') return '3';
          if (name === 'data-end-unit') return '4';
          return null;
        },
        querySelectorAll: function() { return []; }
      };
      const row = { querySelectorAll: function(sel) {
        return sel.indexOf('td') >= 0 ? [cell] : [];
      } };
      const container = { querySelectorAll: function(sel) {
        // container.querySelectorAll('tbody tr, tr') 返回行节点数组
        return sel.indexOf('tr') >= 0 ? [row] : [];
      } };
      global.document = {
        querySelectorAll: function(sel) {
          if (sel.indexOf('frame') >= 0) return [];
          if (sel.indexOf('#kbTable') >= 0) return [container];
          // 点击兜底用的 a 列表
          return [{ textContent: '', getAttribute: function() { return null; } }];
        }
      };
    ''');
    expect(courses, hasLength(1));
    expect(courses.single['name'], '高等数学');
    expect(courses.single['dayOfWeek'], 2);
    expect(courses.single['startSection'], 3);
    expect(courses.single['endSection'], 4);
    expect(courses.single['teacher'], '张老师');
    expect(courses.single['location'], '教A-201');
  });

  test('无课程且无入口时返回空数组', () async {
    final courses = await _runExtractor(r'''
      global.XMLHttpRequest = function() {
        this.open = function() {};
        this.setRequestHeader = function() {};
        this.send = function() { this.status = 500; };
      };
      global.document = { querySelectorAll: function() { return []; } };
    ''');
    expect(courses, isEmpty);
  });
}

/// 在 Node 中执行 [extractJs]，返回解析后的课程列表。
///
/// [setup] 负责 mock window/document/XMLHttpRequest；若接口 mock 命中，
/// 额外校验请求打到了 jwapp 课表接口。
Future<List<Map<String, dynamic>>> _runExtractor(
  String setup, {
  String? endpoint,
}) async {
  final script = '''
    let requestedUrl = null;
    const RealXHR = function() {
      this.open = function(method, url) { requestedUrl = url; };
      this.setRequestHeader = function() {};
    };
    ${endpoint != null ? "global.__expectEndpoint = '$endpoint';" : ''}
    $setup
    const result = ${JgsuAdapter().extractJs};
    if (global.__expectEndpoint && requestedUrl &&
        requestedUrl.indexOf(global.__expectEndpoint) < 0) {
      throw new Error('expected endpoint ' + global.__expectEndpoint +
                      ' but got ' + requestedUrl);
    }
    process.stdout.write(result);
  ''';
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'hormone_jgsu_${DateTime.now().microsecondsSinceEpoch}.js',
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
    return (jsonDecode(result.stdout as String) as List)
        .cast<Map<String, dynamic>>();
  } finally {
    if (await file.exists()) await file.delete();
  }
}
