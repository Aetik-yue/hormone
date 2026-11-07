import 'package:flutter_test/flutter_test.dart';
import 'support/node_extractor.dart';
import 'package:recess/features/import/data/school_adapter.dart';
import 'package:recess/features/import/data/syuct_adapter.dart';

void main() {
  final adapter = SyuctAdapter();

  test('使用正方学生入口并识别 xskbcx 课表页', () {
    expect(adapter.schoolName, '沈阳化工大学');
    expect(adapter.loginUrl, 'https://jws.syuct.edu.cn/');
    expect(
      adapter.isSchedulePage('https://jws.syuct.edu.cn/xskbcx.aspx?xh=1'),
      isTrue,
    );
    expect(adapter.isSchedulePage(adapter.loginUrl), isFalse);
    expect(adapter.supportLevel, AdapterSupportLevel.schoolVerified);
    expect(adapter.systemName, '专用适配');
  });

  test('课表单元格解析星期、节次与周次', () async {
    final courses = await runAdapterCourses(adapter, r'''
      const cell = {
        innerText: '周一第1-2节{第1-16周}\n高等数学\nA-101',
        textContent: '周一第1-2节{第1-16周}\n高等数学\nA-101'
      };
      const table = {querySelectorAll: function(selector) {
        return selector.indexOf('td') >= 0 ? [cell] : [];
      }};
      global.document = {
        getElementById: function(id) { return id === 'Table1' ? table : null; },
        querySelector: function() { return null; },
        querySelectorAll: function() { return []; }
      };
    ''', tag: 'syuct_parse');

    expect(courses, hasLength(1));
    expect(courses.single['name'], '高等数学');
    expect(courses.single['dayOfWeek'], 1);
    expect(courses.single['startSection'], 1);
    expect(courses.single['endSection'], 2);
    expect(courses.single['weeks'], List<int>.generate(16, (i) => i + 1));
  });

  test('课表在 iframe 内的 Table1 时同样能提取', () async {
    final courses = await runAdapterCourses(adapter, r'''
      const cell = {
        innerText: '周三第5-6节{第2-18周}\n大学物理\nB-202',
        textContent: '周三第5-6节{第2-18周}\n大学物理\nB-202'
      };
      const table = {querySelectorAll: function(selector) {
        return selector.indexOf('td') >= 0 ? [cell] : [];
      }};
      const iframeDoc = {
        getElementById: function(id) { return id === 'Table1' ? table : null; },
        querySelector: function() { return null; },
        querySelectorAll: function() { return []; }
      };
      global.document = {
        getElementById: function() { return null; },
        querySelector: function() { return null; },
        querySelectorAll: function(selector) {
          return selector.indexOf('frame') >= 0
              ? [{contentDocument: iframeDoc}] : [];
        }
      };
    ''', tag: 'syuct_frame');

    expect(courses, hasLength(1));
    expect(courses.single['name'], '大学物理');
    expect(courses.single['dayOfWeek'], 3);
    expect(courses.single['startSection'], 5);
    expect(courses.single['endSection'], 6);
    expect(courses.single['weeks'], [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]);
  });

  test('Table1 已存在但未渲染出课程时返回 __pending', () async {
    final result = await runAdapterExtractor(adapter, r'''
      const table = {querySelectorAll: function() { return []; }};
      global.document = {
        getElementById: function(id) { return id === 'Table1' ? table : null; },
        querySelector: function() { return null; },
        querySelectorAll: function() { return []; }
      };
    ''', tag: 'syuct_pending');

    expect(result, isA<Map<String, dynamic>>());
    expect(result['__pending'], isTrue);
  });

  test('命中「学生个人课表」入口时点击并返回 __nav', () async {
    final (result, clicked) = await runAdapterExtractorProbe(adapter, r'''
      const link = {
        textContent: '学生个人课表',
        getAttribute: function() { return 'xskbcx.aspx?xh=1'; },
        click: function() { global.__clicked = true; }
      };
      global.document = {
        getElementById: function() { return null; },
        querySelector: function() { return null; },
        querySelectorAll: function(selector) {
          return selector.indexOf('xskbcx') >= 0 ? [link] : [];
        }
      };
    ''', probe: 'global.__clicked === true', tag: 'syuct_nav');

    expect(result, isA<Map<String, dynamic>>());
    expect(result['__nav'], isTrue);
    expect(clicked, isTrue);
  });

  test('入口文本不匹配时回退点击第一个课表链接', () async {
    final (result, clicked) = await runAdapterExtractorProbe(adapter, r'''
      const link = {
        textContent: '课表查询',
        getAttribute: function() { return 'xskbcx.aspx?xh=1'; },
        click: function() { global.__clicked = true; }
      };
      global.document = {
        getElementById: function() { return null; },
        querySelector: function() { return null; },
        querySelectorAll: function(selector) {
          return selector.indexOf('xskbcx') >= 0 ? [link] : [];
        }
      };
    ''', probe: 'global.__clicked === true', tag: 'syuct_nav_fallback');

    expect(result, isA<Map<String, dynamic>>());
    expect(result['__nav'], isTrue);
    expect(clicked, isTrue);
  });

  test('去重键不含教室：同星期同节次不同教室只留先出现者，节次不同则分别保留', () async {
    final courses = await runAdapterCourses(adapter, r'''
      // 名称行留 48 字符：syuct 的 location 只取模式行后长度 ≤40 的行，
      // 长名称行被跳过，教室行才会落到 location，从而能观察不同教室。
      const longName = '超长课程名称'.repeat(8);
      function makeCell(sections, location) {
        return {
          innerText: '周一第' + sections + '节{第1-16周}\n' + longName + '\n' + location,
          textContent: '周一第' + sections + '节{第1-16周}\n' + longName + '\n' + location
        };
      }
      const table = {querySelectorAll: function(selector) {
        return selector.indexOf('td') >= 0
            ? [makeCell('1-2', 'A-101'), makeCell('1-2', 'A-101'),
               makeCell('1-2', 'B-202'), makeCell('3-4', 'A-101')]
            : [];
      }};
      global.document = {
        getElementById: function(id) { return id === 'Table1' ? table : null; },
        querySelector: function() { return null; },
        querySelectorAll: function() { return []; }
      };
    ''', tag: 'syuct_dedupe');

    expect(courses, hasLength(2));
    expect(courses.map((c) => c['startSection']), [1, 3]);
    expect(courses.where((c) => c['startSection'] == 1), hasLength(1));
    expect(courses.first['location'], 'A-101');
  });
}
