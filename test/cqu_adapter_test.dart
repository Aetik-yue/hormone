import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/import/application/webview_import_provider.dart';
import 'package:hormone/features/import/data/cqu_adapter.dart';

void main() {
  test('区分账号登录入口与课表页，并兼容旧课表路径', () {
    final adapter = CquAdapter();

    expect(adapter.loginUrl, 'https://my.cqu.edu.cn');
    expect(
      adapter.scheduleUrl,
      'https://my.cqu.edu.cn/tt/university-timetable',
    );
    expect(
      adapter.isSchedulePage('https://my.cqu.edu.cn/tt/university-timetable'),
      isTrue,
    );
    expect(
      adapter.isSchedulePage('https://my.cqu.edu.cn/workspace/curriculum'),
      isTrue,
    );
    expect(
      adapter.isSchedulePage('https://my.cqu.edu.cn/workspace/home'),
      isFalse,
    );
    expect(adapter.isSchedulePage(adapter.loginUrl), isFalse);
  });

  group('CquAdapter extractJs', () {
    test('普通课与无编号实验课混排时保留周四6-9节及各自周次', () async {
      final courses = await _runExtractor(r'''
        const headers = makeHeaders([
          [1, 100], [2, 200], [3, 300], [4, 400],
          [5, 500], [6, 600], [7, 700]
        ]);
        const lecture = new FakeElement(
          '本科 - 操作系统\n[000373-004]\n[1-3,5-12周] [3-4节] D1449',
          380, 40);
        const memoryInfo = new FakeElement('[8周] [6-9节] 计算机机房DS1401', 380, 40);
        const memory = new FakeElement(
          '操作系统[基于 Namespace 的内存管理]\n' + memoryInfo.innerText,
          380, 40, {}, [memoryInfo]);
        const bpf = new FakeElement(
          '操作系统\n[BPF 内核代码注入技术的应用]\n[6周] [6-9节] 计算机机房DS1401',
          380, 40);
        const group = new FakeElement(memory.innerText + '\n' + bpf.innerText,
          350, 100, {}, [memory, bpf]);
        const row = new FakeElement(lecture.innerText + '\n' + group.innerText,
          350, 200, {}, [lecture, group]);
        installDocument(headers.concat([row, lecture, group, memory, memoryInfo, bpf]));
      ''');

      expect(courses, hasLength(3));
      expect(courses.first['name'], '操作系统');
      final (imported, skipped) = importCoursesFromDecoded(courses);
      expect(skipped, 0);
      final labs = imported.where((c) => c.startSection == 6).toList();
      expect(labs, hasLength(2));
      expect(labs.map((c) => c.name), [
        '操作系统[基于 Namespace 的内存管理]',
        '操作系统[BPF 内核代码注入技术的应用]',
      ]);
      expect(labs.map((c) => c.weeks), [
        [8],
        [6],
      ]);
      for (final lab in labs) {
        expect(lab.dayOfWeek, DateTime.thursday);
        expect(lab.endSection, 9);
        expect(lab.location, '计算机机房DS1401');
      }
    });

    test('无编号实验卡片保留完整项目和换行教室，排除只有时间的子元素', () async {
      final courses = await _runExtractor(r'''
        const info = new FakeElement('[7,9-11周] [6-9节]\n计算机机房DS140\n1', 380, 40);
        const card = new FakeElement(
          '操作系统[基于\nNamespace 的内存管理]\n' + info.innerText,
          380, 40, {'data-day': '4'}, [info]);
        const outer = new FakeElement(card.innerText, 350, 200, {}, [card]);
        installDocument([outer, card, info]);
      ''');

      expect(courses, hasLength(1));
      expect(courses.single['name'], '操作系统[基于Namespace 的内存管理]');
      expect(courses.single['location'], '计算机机房DS1401');
      expect(courses.single['weeks'], [7, 9, 10, 11]);
      expect(courses.single['dayOfWeek'], DateTime.thursday);
    });

    test('实验项目或结束节次不同时分别保留，相同卡片只导入一次', () async {
      final courses = await _runExtractor(r'''
        const texts = [
          '操作系统[内存管理]\n[8周] [6-9节] DS1401',
          '操作系统[内存管理]\n[8周] [6-9节] DS1401',
          '操作系统[进程管理]\n[8周] [6-9节] DS1401',
          '操作系统[内存管理]\n[8周] [6-7节] DS1401'
        ];
        installDocument(texts.map(text =>
          new FakeElement(text, 380, 40, {'data-day': '4'})));
      ''');

      expect(courses, hasLength(3));
      expect(courses.map((c) => c['name']), [
        '操作系统[内存管理]',
        '操作系统[进程管理]',
        '操作系统[内存管理]',
      ]);
      expect(courses.map((c) => c['endSection']), [9, 9, 7]);
    });

    test('仅有周次节次和教室时不生成无名实验课', () async {
      final courses = await _runExtractor(r'''
        installDocument([
          new FakeElement('[8周] [6-9节] DS1401', 380, 40, {'data-day': '4'})
        ]);
      ''');

      expect(courses, isEmpty);
    });

    test('保留最内层课程元素，避免周五课程偏移到周六', () async {
      final courses = await _runExtractor(r'''
        const headers = makeHeaders([
          [1, 100], [2, 200], [3, 300], [4, 400],
          [5, 500], [6, 600], [7, 700]
        ]);
        const text = '[2024-01]\n[1-16周] [1-2节] A101\n本科 - 高等数学';
        const inner = new FakeElement(text, 480, 40);
        const outer = new FakeElement(text, 550, 100, {}, [inner]);
        installDocument(headers.concat([outer, inner]));
      ''');

      expect(courses, hasLength(1));
      expect(courses.single['name'], '高等数学');
      expect(courses.single['dayOfWeek'], DateTime.friday);
    });

    test('过滤屏外表头并外推缺失的周一', () async {
      final courses = await _runExtractor(r'''
        const headers = makeHeaders([
          [1, -500],
          [2, 200], [3, 300], [4, 400], [5, 500], [6, 600], [7, 700]
        ]);
        const text = '[2024-02]\n[1-16周] [3-4节] A102\n本科 - 大学物理';
        const course = new FakeElement(text, 80, 40);
        installDocument(headers.concat([course]));
      ''');

      expect(courses, hasLength(1));
      expect(courses.single['dayOfWeek'], DateTime.monday);
    });

    test('课程超出可信匹配半径时不猜测相邻星期', () async {
      final courses = await _runExtractor(r'''
        const headers = makeHeaders([[5, 500]]);
        const text = '[2024-03]\n[1-16周] [5-6节] A103\n本科 - 程序设计';
        const course = new FakeElement(text, 580, 40);
        installDocument(headers.concat([course]));
      ''');

      expect(courses, hasLength(1));
      expect(courses.single['dayOfWeek'], 0);
    });

    test('发现折叠课程时先展开并返回等待信号', () async {
      final result = await _runExtractorRaw(r'''
        const headers = makeHeaders([
          [1, 100], [2, 200], [3, 300], [4, 400],
          [5, 500], [6, 600], [7, 700]
        ]);
        const expander = new FakeElement('还有3条未展\n开 ▼', 380, 40);
        installDocument(headers.concat([expander]));
      ''');

      expect(result, isA<Map<String, dynamic>>());
      expect(result['__pending'], isTrue);
      expect(result['reason'], 'expandingCollapsedCourses');
      expect(result['expandedGroupCount'], 1);
    });

    test('等待展开完成后抓取原本隐藏的实验课', () async {
      final courses = await _runExtractor(r'''
        const headers = makeHeaders([
          [1, 100], [2, 200], [3, 300], [4, 400],
          [5, 500], [6, 600], [7, 700]
        ]);
        const hiddenText = '操作系统[实验项目]\n[6周] [6-9节] DS1401';
        const hiddenCourse = new FakeElement(hiddenText, 380, 40);
        const expander = new FakeElement('还有1条未展开', 380, 40);
        const elements = headers.concat([expander]);
        expander.click = function() {
          expander.innerText = '收起';
          expander.textContent = '收起';
          elements.push(hiddenCourse);
        };
        installDocument(elements);
      ''', runs: 2);

      expect(courses, hasLength(1));
      expect(courses.single['name'], '操作系统[实验项目]');
      expect(courses.single['dayOfWeek'], DateTime.thursday);
      expect(courses.single['startSection'], 6);
      expect(courses.single['endSection'], 9);
      expect(courses.single['location'], 'DS1401');
      expect(courses.single['weeks'], [6]);
    });
  });
}

Future<List<Map<String, dynamic>>> _runExtractor(
  String fixtureSetup, {
  int runs = 1,
}) async {
  final decoded = await _runExtractorRaw(fixtureSetup, runs: runs);
  return (decoded as List<dynamic>).cast<Map<String, dynamic>>();
}

Future<dynamic> _runExtractorRaw(String fixtureSetup, {int runs = 1}) async {
  final script = '''
    console.log = function() {};

    class FakeElement {
      constructor(text, left, width, attrs = {}, children = []) {
        this.innerText = text;
        this.textContent = text;
        this._rect = {left: left, width: width, height: 40};
        this._attrs = attrs;
        this.children = children;
        this.parentElement = null;
        for (const child of children) child.parentElement = this;
      }

      contains(other) {
        if (this === other) return true;
        return this.children.some(function(child) { return child.contains(other); });
      }

      getAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this._attrs, name)
            ? this._attrs[name]
            : null;
      }

      getBoundingClientRect() {
        return this._rect;
      }

      click() {}
    }

    function makeHeaders(entries) {
      const labels = ['', '一', '二', '三', '四', '五', '六', '日'];
      return entries.map(function(entry) {
        return new FakeElement('周' + labels[entry[0]], entry[1] - 20, 40);
      });
    }

    function installDocument(elements) {
      global.document = {
        body: {
          innerText: '',
          querySelectorAll: function() { return elements; }
        }
      };
      global.window = {innerWidth: 980};
    }

    $fixtureSetup

    let result;
    for (let run = 0; run < $runs; run++) {
      result = ${CquAdapter().extractJs};
    }
    process.stdout.write(result);
  ''';

  final tempFile = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'hormone_cqu_extractor_${DateTime.now().microsecondsSinceEpoch}.js',
  );
  await tempFile.writeAsString(script);
  try {
    final result = await Process.run(
      'node',
      [tempFile.path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      fail('Node 执行 CQU 提取脚本失败：${result.stderr}');
    }
    return jsonDecode(result.stdout as String);
  } finally {
    if (await tempFile.exists()) await tempFile.delete();
  }
}
