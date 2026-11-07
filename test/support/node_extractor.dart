import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recess/features/import/data/school_adapter.dart';

/// 在 Node 中执行学校适配器的提取脚本，返回解码后的 JSON。
///
/// [setup] 在提取脚本之前执行，用于安装 document / XMLHttpRequest 等 mock。
/// [totalWeeks] 非空时改用 [SchoolAdapter.extractForSemester]，为无范围单双周
/// 提供学期周数上下文。[tag] 只用于临时目录命名，便于失败时定位来源。
Future<dynamic> runAdapterExtractor(
  SchoolAdapter adapter,
  String setup, {
  int? totalWeeks,
  String tag = 'school',
}) =>
    _runAdapterScript(adapter, setup, totalWeeks: totalWeeks, tag: tag);

/// 同 [runAdapterExtractor]，并在提取脚本执行后求值 [probe]，返回
/// (提取结果, 探测值)。提取脚本只返回固定的 JSON（如 `{"__nav":true}`），
/// fixture 中“点击是否真的发生”这类副作用只能靠执行后的探测表达式观察。
Future<(dynamic, dynamic)> runAdapterExtractorProbe(
  SchoolAdapter adapter,
  String setup, {
  required String probe,
  int? totalWeeks,
  String tag = 'school',
}) async {
  final decoded = await _runAdapterScript(
    adapter,
    setup,
    totalWeeks: totalWeeks,
    tag: tag,
    probe: probe,
  ) as Map<String, dynamic>;
  return (decoded['result'], decoded['probe']);
}

Future<dynamic> _runAdapterScript(
  SchoolAdapter adapter,
  String setup, {
  int? totalWeeks,
  String tag = 'school',
  String? probe,
}) async {
  final extractor = totalWeeks == null
      ? adapter.extractJs
      : adapter.extractForSemester(totalWeeks);
  final output = probe == null
      ? 'result'
      : 'JSON.stringify({result: JSON.parse(result), probe: ($probe)})';
  final script = '''
    $setup
    const result = $extractor;
    process.stdout.write($output);
  ''';
  final directory = await Directory.systemTemp.createTemp('recess_${tag}_');
  final file = File('${directory.path}/fixture.js');
  try {
    await file.writeAsString(script);
    final result = await Process.run(
      'node',
      [file.path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: result.stderr as String?);
    return jsonDecode(result.stdout as String);
  } finally {
    await directory.delete(recursive: true);
  }
}

/// 同 [runAdapterExtractor]，但要求结果是课程数组。
Future<List<Map<String, dynamic>>> runAdapterCourses(
  SchoolAdapter adapter,
  String setup, {
  int? totalWeeks,
  String tag = 'school',
}) async {
  final raw = await runAdapterExtractor(
    adapter,
    setup,
    totalWeeks: totalWeeks,
    tag: tag,
  );
  expect(raw, isA<List<dynamic>>(), reason: '期望课程数组，实际: $raw');
  return (raw as List).cast<Map<String, dynamic>>();
}
