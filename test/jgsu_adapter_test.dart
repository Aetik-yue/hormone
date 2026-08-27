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

  group('策略1：jwapp 课表接口', () {
    test('标准响应 datas.xsallkb.rows：解析周次/节次/单双周/星期文本', () async {
      final courses = await _runExtractor(r'''
        global.document = { querySelectorAll: function() { return []; } };
        global.XMLHttpRequest = _xhrAlways(200, JSON.stringify({ datas: {
          xsallkb: { rows: [
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
          ] } } }));
      ''');

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

    test('小写参数写法不被识别时，扫描退回到无参数请求（服务器默认学期）',
        () async {
      final courses = await _runExtractor(r'''
        global.document = { querySelectorAll: function() { return []; } };
        global.XMLHttpRequest = _xhrOnlyBody(
          '', // 仅无参数的请求返回数据
          JSON.stringify({ datas: { xsallkb: { rows: [
            { kcmc: '线性代数', xqj: '2', jc: '1-2节', zcd: '1-16周' }
          ] } } }));
      ''');
      expect(courses, hasLength(1));
      expect(courses.single['name'], '线性代数');
    });

    test('大写 XNM/XQM 参数变体生效', () async {
      final courses = await _runExtractor(r'''
        global.document = { querySelectorAll: function() { return []; } };
        global.XMLHttpRequest = _xhrBodyContains(
          'XNM=', // 仅大写参数的请求返回数据
          JSON.stringify({ datas: { xsallkb: { rows: [
            { kcmc: '概率论', xqj: '5', jc: '3-4节', zcd: '1-12周' }
          ] } } }));
      ''');
      expect(courses, hasLength(1));
      expect(courses.single['name'], '概率论');
    });

    test('响应行数据 key 不叫 xsallkb 时自适应（遍历 datas）', () async {
      final courses = await _runExtractor(r'''
        global.document = { querySelectorAll: function() { return []; } };
        global.XMLHttpRequest = _xhrAlways(200, JSON.stringify({ datas: {
          xsKb: { rows: [
            { kcmc: '大学物理', xqj: '4', jc: '6-7节', zcd: '3-14周' }
          ] } } }));
      ''');
      expect(courses, hasLength(1));
      expect(courses.single['name'], '大学物理');
    });

    test('乱序节次文本被排序，保证 startSection <= endSection', () async {
      final courses = await _runExtractor(r'''
        global.document = { querySelectorAll: function() { return []; } };
        global.XMLHttpRequest = _xhrAlways(200, JSON.stringify({ datas: {
          xsallkb: { rows: [
            { kcmc: '数据结构', xqj: '6', jc: '5,1-2', zcd: '1-16周' }
          ] } } }));
      ''');
      expect(courses, hasLength(1));
      expect(courses.single['startSection'], 1);
      expect(courses.single['endSection'], 5);
    });

    test('接口返回空（假期无课）时继续走 DOM/入口兜底而不误报', () async {
      final result = await _runExtractorRaw(r'''
        global.document = { querySelectorAll: function() { return []; } };
        global.XMLHttpRequest = _xhrAlways(200,
            JSON.stringify({ datas: { xsallkb: { rows: [] } } }));
      ''');
      expect(result, isEmpty);
    });
  });

  group('策略2：DOM 兜底', () {
    test('接口失败时 DOM data 属性兜底（主文档课表）', () async {
      final courses = await _runExtractor(r'''
        global.XMLHttpRequest = _xhrAlways(500, '');
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

    test('课表渲染在 iframe 内时同样能提取（遍历同源 frame）', () async {
      final courses = await _runExtractor(r'''
        global.XMLHttpRequest = _xhrAlways(500, '');
        const cell = {
          innerText: '毛概\n1-12周\n王老师\n教C-305',
          getAttribute: function(name) {
            if (name === 'data-week') return '3';
            if (name === 'data-begin-unit') return '8';
            if (name === 'data-end-unit') return '9';
            return null;
          },
          querySelectorAll: function() { return []; }
        };
        const row = { querySelectorAll: function(sel) {
          return sel.indexOf('td') >= 0 ? [cell] : [];
        } };
        const container = { querySelectorAll: function(sel) {
          return sel.indexOf('tr') >= 0 ? [row] : [];
        } };
        const iframeDoc = { querySelectorAll: function(sel) {
          if (sel.indexOf('#kbTable') >= 0) return [container];
          return []; // frame 内无链接
        } };
        const iframeEl = { contentDocument: iframeDoc };
        global.document = {
          querySelectorAll: function(sel) {
            if (sel.indexOf('frame') >= 0) return [iframeEl];
            return []; // 主文档没有任何课表与链接
          }
        };
      ''');
      expect(courses, hasLength(1));
      expect(courses.single['name'], '毛概');
      expect(courses.single['dayOfWeek'], 3);
      expect(courses.single['startSection'], 8);
      expect(courses.single['endSection'], 9);
    });
  });

  group('策略3：__nav 入口点击', () {
    test('长文本入口「学生个人课表」也能触发点击跳转', () async {
      final result = await _runExtractorRaw(r'''
        global.XMLHttpRequest = _xhrAlways(500, '');
        global.document = { querySelectorAll: function(sel) {
          if (sel.indexOf('frame') >= 0) return [];
          if (sel.indexOf('#kbTable') >= 0) return [];
          if (sel.indexOf('a,') >= 0) return [{
            textContent: '学生个人课表',
            getAttribute: function(name) {
              return name === 'title' ? null : '/jsxsd/kbcx/xskbcx.html';
            },
            click: function() { global.__clicked = true; }
          }];
          return [];
        } };
      ''');
      expect(result, isA<Map<String, dynamic>>());
      expect(result['__nav'], isTrue);
    });

    test('href 指向 wdkb 应用时优先点击（第一轮匹配）', () async {
      final result = await _runExtractorRaw(r'''
        global.XMLHttpRequest = _xhrAlways(500, '');
        global.document = { querySelectorAll: function(sel) {
          if (sel.indexOf('frame') >= 0) return [];
          if (sel.indexOf('#kbTable') >= 0) return [];
          if (sel.indexOf('a,') >= 0) return [{
            textContent: '随便什么入口',
            getAttribute: function(name) {
              return name === 'title' ? null : '/jwapp/sys/wdkb/index.do';
            },
            click: function() {}
          }];
          return [];
        } };
      ''');
      expect(result, isA<Map<String, dynamic>>());
      expect(result['__nav'], isTrue);
    });
  });

  test('无课程且无入口时返回空数组', () async {
    final result = await _runExtractorRaw(r'''
      global.XMLHttpRequest = _xhrAlways(500, '');
      global.document = { querySelectorAll: function() { return []; } };
    ''');
    expect(result, isEmpty);
  });

  group('学期参数推算（依赖 Node Date，这里用固定 mock 时钟验证）', () {
    test('9-12 月推算为当年秋季学期，两种学期编码都尝试', () async {
      final courses = await _runExtractor(r'''
        global.document = { querySelectorAll: function() { return []; } };
        global.XMLHttpRequest = function() {
          this.open = function() {};
          this.setRequestHeader = function() {};
          this.send = function(body) {
            // 2026 年 10 月（秋季学期）→ xnm 应为当年 2026
            if (String(body || '').indexOf('xnm=2026&') >= 0) {
              this.status = 200;
              this.responseText = JSON.stringify({ datas: { xsallkb: { rows: [
                { kcmc: '秋季课', xqj: '1', jc: '1-2节', zcd: '1-16周' }
              ] } } });
            } else {
              this.status = 500;
              this.responseText = '';
            }
          };
        };
        const RealDate = Date;
        global.Date = class extends RealDate {
          constructor(...args) {
            if (args.length === 0) { super(2026, 9, 15); } // 2026-10-15
            else { super(...args); }
          }
        };
      ''');
      expect(courses, hasLength(1));
      expect(courses.single['name'], '秋季课');
    });

    test('1-8 月推算为上一年学年（跨年学期）', () async {
      final courses = await _runExtractor(r'''
        global.document = { querySelectorAll: function() { return []; } };
        global.XMLHttpRequest = function() {
          this.open = function() {};
          this.setRequestHeader = function() {};
          this.send = function(body) {
            // 2026 年 3 月（春季学期）→ xnm 应为上一年 2025
            if (String(body || '').indexOf('xnm=2025&') >= 0) {
              this.status = 200;
              this.responseText = JSON.stringify({ datas: { xsallkb: { rows: [
                { kcmc: '春季课', xqj: '2', jc: '3-4节', zcd: '2-16周' }
              ] } } });
            } else {
              this.status = 500;
              this.responseText = '';
            }
          };
        };
        const RealDate = Date;
        global.Date = class extends RealDate {
          constructor(...args) {
            if (args.length === 0) { super(2026, 2, 20); } // 2026-03-20
            else { super(...args); }
          }
        };
      ''');
      expect(courses, hasLength(1));
      expect(courses.single['name'], '春季课');
    });
  });
}

// ─── Node 侧公共 mock 工具（在 setup 前注入） ───

const _mockHelpers = r'''
function _xhrAlways(status, responseText) {
  return function() {
    this.open = function() {};
    this.setRequestHeader = function() {};
    this.send = function() {
      this.status = status;
      this.responseText = responseText;
    };
  };
}
function _xhrOnlyBody(acceptedBody, responseText) {
  return function() {
    this.open = function() {};
    this.setRequestHeader = function() {};
    this.send = function(body) {
      if (body === acceptedBody) {
        this.status = 200;
        this.responseText = responseText;
      } else {
        this.status = 500;
        this.responseText = '';
      }
    };
  };
}
function _xhrBodyContains(fragment, responseText) {
  return function() {
    this.open = function() {};
    this.setRequestHeader = function() {};
    this.send = function(body) {
      if (String(body || '').indexOf(fragment) >= 0) {
        this.status = 200;
        this.responseText = responseText;
      } else {
        this.status = 500;
        this.responseText = '';
      }
    };
  };
}
''';

/// 在 Node 中执行 JGSU 适配器的 [extractJs]，返回解析后的课程列表。
Future<List<Map<String, dynamic>>> _runExtractor(String setup) async {
  final raw = await _runExtractorRaw(setup);
  expect(raw, isA<List<dynamic>>(), reason: '期望课程数组，实际: $raw');
  return (raw as List).cast<Map<String, dynamic>>();
}

/// 在 Node 中执行并返回原始解码结果（数组或 __nav 对象）。
Future<dynamic> _runExtractorRaw(String setup) async {
  final script = '''
    $_mockHelpers
    $setup
    const result = ${JgsuAdapter().extractJs};
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
    return jsonDecode(result.stdout as String);
  } finally {
    if (await file.exists()) await file.delete();
  }
}
