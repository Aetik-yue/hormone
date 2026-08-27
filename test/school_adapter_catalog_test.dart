import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/import/data/configured_school_adapter.dart';
import 'package:hormone/features/import/data/school_adapter.dart';

void main() {
  const expectedKeyUniversityNames = {
    '北京大学',
    '清华大学',
    '中国人民大学',
    '北京航空航天大学',
    '北京理工大学',
    '中国农业大学',
    '北京师范大学',
    '中央民族大学',
    '南开大学',
    '天津大学',
    '大连理工大学',
    '东北大学',
    '吉林大学',
    '哈尔滨工业大学',
    '复旦大学',
    '同济大学',
    '上海交通大学',
    '华东师范大学',
    '南京大学',
    '东南大学',
    '浙江大学',
    '中国科学技术大学',
    '厦门大学',
    '山东大学',
    '中国海洋大学',
    '武汉大学',
    '华中科技大学',
    '湖南大学',
    '中南大学',
    '国防科技大学',
    '中山大学',
    '华南理工大学',
    '四川大学',
    '电子科技大学',
    '重庆大学',
    '西安交通大学',
    '西北工业大学',
    '西北农林科技大学',
    '兰州大学',
  };

  test('重点高校目录完整且没有重复学校', () {
    final names = eliteUniversityAdapters.map((e) => e.schoolName).toSet();

    expect(eliteUniversityAdapters, hasLength(39));
    expect(names, expectedKeyUniversityNames);
    expect(names, hasLength(eliteUniversityAdapters.length));
  });

  test('所有学校入口均为有效 HTTP(S) URL 且抽取脚本非空', () {
    for (final adapter in schoolAdapters) {
      final uri = Uri.tryParse(adapter.loginUrl);
      expect(uri, isNotNull, reason: adapter.schoolName);
      expect(uri!.scheme, anyOf('http', 'https'), reason: adapter.schoolName);
      expect(uri.host, isNotEmpty, reason: adapter.schoolName);
      expect(adapter.extractJs.trim(), isNotEmpty, reason: adapter.schoolName);
    }
  });

  test('新版正方学校使用登录态接口并保留 DOM 回退', () {
    final adapter = eliteUniversityAdapters.singleWhere(
      (item) => item.schoolName == '浙江大学',
    );

    expect(adapter, isA<ConfiguredSchoolAdapter>());
    expect(adapter.systemName, '正方教务');
    expect(adapter.supportLevel, AdapterSupportLevel.systemCompatible);
    expect(adapter.extractJs, contains('xskbcx_cxXsgrkb.html'));
    expect(adapter.extractJs, contains("document.querySelector('#kbTable')"));
  });

  test('新版正方接口解析课程、单双周和节次', () async {
    final adapter = eliteUniversityAdapters.singleWhere(
      (item) => item.schoolName == '浙江大学',
    );
    final script = '''
      global.window = { location: { pathname: '/jwglxt/kbcx/index.html' } };
      global.document = {
        querySelector: function(selector) {
          if (selector.indexOf('xnm') >= 0) return { value: '2025' };
          if (selector.indexOf('xqm') >= 0) return { value: '12' };
          return null;
        }
      };
      global.XMLHttpRequest = function() {
        this.open = function() {};
        this.setRequestHeader = function() {};
        this.send = function() {
          this.status = 200;
          this.responseText = JSON.stringify({ kbList: [{
            kcmc: '高等数学', xqj: '3', jcs: '3-4节',
            zcd: '1-8周(单)', xm: '张老师', cdmc: '东教101'
          }] });
        };
      };
      const result = ${adapter.extractJs};
      process.stdout.write(result);
    ''';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'hormone_zhengfang_${DateTime.now().microsecondsSinceEpoch}.js',
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
        'dayOfWeek': 3,
        'startSection': 3,
        'endSection': 4,
        'weeks': [1, 3, 5, 7],
      });
    } finally {
      if (await file.exists()) await file.delete();
    }
  });

  test('未知产品学校明确标记为通用抓取', () {
    final adapter = eliteUniversityAdapters.singleWhere(
      (item) => item.schoolName == '国防科技大学',
    );

    expect(adapter.systemName, '通用抓取');
    expect(adapter.supportLevel, AdapterSupportLevel.generic);
  });

  test('全量注册表学校名称唯一', () {
    final names = schoolAdapters.map((e) => e.schoolName).toList();
    expect(names.toSet(), hasLength(names.length));
  });
}
