import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:recess/core/models/semester.dart';
import 'package:recess/features/import/application/webview_extraction_protocol.dart';
import 'package:recess/features/import/domain/webview_course_parser.dart';

const _initialWait = Duration(seconds: 2);
const _navWait = Duration(seconds: 3);
const _pendingWait = Duration(seconds: 2);

class _FakeJs {
  _FakeJs(this._responses);

  final List<Object> _responses;
  final List<String> calls = [];
  int _index = 0;

  Future<dynamic> call(String js) async {
    calls.add(js);
    if (_index >= _responses.length) {
      throw StateError('没有更多 fake 响应');
    }
    final response = _responses[_index++];
    if (response is Exception) throw response;
    return response;
  }
}

class _Harness {
  _Harness({
    required List<Object> responses,
    this.enterResult = true,
    this.layoutChanged = true,
  }) : js = _FakeJs(responses);

  final _FakeJs js;
  final bool enterResult;
  final bool layoutChanged;
  bool mounted = true;
  bool ready = true;
  Completer<void>? navWaitGate;
  final Completer<void> navWaitStarted = Completer<void>();

  final List<Duration> waits = [];
  final List<bool> extracting = [];
  final List<String> notices = [];
  int enterCalls = 0;
  int leaveCalls = 0;
  int layoutChecks = 0;
  String? currentUrlValue = 'https://jw.example.com/login';
  late final WebviewPreviewContext context = WebviewPreviewContext.fromSemester(
    Semester(
      id: 's1',
      name: '学期',
      startDate: DateTime(2026, 9, 7),
      totalWeeks: 18,
    ),
  );

  late final WebviewExtractionProtocol protocol = WebviewExtractionProtocol(
    isReady: () => ready,
    isMounted: () => mounted,
    enterCaptureMode: () async {
      enterCalls++;
      return enterResult;
    },
    leaveCaptureMode: () async {
      leaveCalls++;
    },
    waitForLandscapeLayout: () async {
      layoutChecks++;
      return layoutChanged;
    },
    wait: (duration) async {
      waits.add(duration);
      if (duration == _navWait && navWaitGate != null) {
        if (!navWaitStarted.isCompleted) navWaitStarted.complete();
        await navWaitGate!.future;
      }
    },
    executeJs: js.call,
    loadPreviewContext: () async => context,
    buildExtractJs: (ctx) => 'EXTRACT:${ctx.totalWeeks}',
    currentUrl: () async => currentUrlValue,
    isSchedulePage: (url) => url.contains('schedule'),
    onExtracting: extracting.add,
    onNotice: notices.add,
  );
}

Map<String, Object> _course(String name) => {
      'name': name,
      'dayOfWeek': 1,
      'startSection': 1,
      'endSection': 2,
      'weeks': [1, 2, 3],
    };

String _nav() => '{"__nav":true}';
String _pending() => '{"__pending":true}';

void main() {
  test('抓取成功后返回预览，退出横屏并复位抓取状态', () async {
    final h = _Harness(responses: [
      jsonEncode([_course('高等数学')]),
    ]);

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractPreview>());
    expect((outcome as WebviewExtractPreview).preview.courses.single.name,
        '高等数学');
    expect(h.waits, [_initialWait]);
    expect(h.extracting, [true, false]);
    expect(h.enterCalls, 1);
    expect(h.leaveCalls, 1);
    expect(h.notices, isEmpty);
    expect(h.js.calls, ['EXTRACT:18']);
    expect(h.waits.where((d) => d == _navWait), isEmpty);
  });

  test('__nav 连续 4 次触发重试上限，前 3 次各等 3 秒', () async {
    final h = _Harness(responses: [_nav(), _nav(), _nav(), _nav()]);

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractNavFailed>());
    expect(h.waits, [
      _initialWait,
      _navWait,
      _initialWait,
      _navWait,
      _initialWait,
      _navWait,
      _initialWait,
    ]);
    expect(h.extracting, [
      true,
      false,
      true,
      false,
      true,
      false,
      true,
      false,
    ]);
    expect(h.js.calls.length, 4);
    expect(h.leaveCalls, 1);
  });

  test('跳转失败后重试计数复位，下一轮仍允许 3 次重试', () async {
    final h = _Harness(responses: [
      _nav(),
      _nav(),
      _nav(),
      _nav(),
      _nav(),
      _nav(),
      _nav(),
      _nav(),
    ]);

    expect(await h.protocol.run(), isA<WebviewExtractNavFailed>());
    h.waits.clear();
    expect(await h.protocol.run(), isA<WebviewExtractNavFailed>());
    expect(h.waits.where((d) => d == _navWait).length, 3);
    expect(h.waits.length, 7);
  });

  test('__pending 重试等待 2 秒，随后成功返回预览', () async {
    final h = _Harness(responses: [
      _pending(),
      jsonEncode([_course('线性代数')]),
    ]);

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractPreview>());
    expect(h.waits, [_initialWait, _pendingWait, _initialWait]);
    expect(h.waits.where((d) => d == _navWait), isEmpty);
    // 重试会重新确认横屏布局，与旧实现的递归一致。
    expect(h.enterCalls, 2);
    expect(h.layoutChecks, 2);
  });

  test('成功后重试计数复位，下一次仍允许 3 次 __nav 重试', () async {
    final h = _Harness(responses: [
      _nav(),
      jsonEncode([_course('大学物理')]),
      _nav(),
      _nav(),
      _nav(),
      _nav(),
    ]);

    final first = await h.protocol.run();
    expect(first, isA<WebviewExtractPreview>());

    h.waits.clear();
    final second = await h.protocol.run();
    expect(second, isA<WebviewExtractNavFailed>());
    expect(h.waits, [
      _initialWait,
      _navWait,
      _initialWait,
      _navWait,
      _initialWait,
      _navWait,
      _initialWait,
    ]);
  });

  test('重试等待期间启动新一轮抓取时旧链让位', () async {
    final h = _Harness(responses: [
      _nav(),
      jsonEncode([_course('数据结构')]),
    ]);
    h.navWaitGate = Completer<void>();

    final first = h.protocol.run();
    await h.navWaitStarted.future;
    final second = h.protocol.run();
    h.navWaitGate!.complete();

    expect(await first, isA<WebviewExtractSilent>());
    final secondOutcome = await second;
    expect(secondOutcome, isA<WebviewExtractPreview>());
    expect(
      (secondOutcome as WebviewExtractPreview).preview.courses.single.name,
      '数据结构',
    );
    // 旧链让位时不得再碰抓取状态或横屏：只有新链各 true/false 一次。
    expect(h.extracting, [true, false, true, false]);
    expect(h.leaveCalls, 1);
  });

  test('重试等待期间页面卸载时离开横屏并静默结束', () async {
    final h = _Harness(responses: [_nav()]);
    h.navWaitGate = Completer<void>();

    final future = h.protocol.run();
    await h.navWaitStarted.future;
    h.mounted = false;
    h.navWaitGate!.complete();

    expect(await future, isA<WebviewExtractSilent>());
    expect(h.leaveCalls, 1);
    // 走的是重试等待后的卸载分支，而不是回到循环顶部再等一轮。
    expect(h.waits.length, 2);
    expect(h.js.calls.length, 1);
  });

  test('注入异常且已在课表页时静默退出', () async {
    final h = _Harness(responses: [Exception('JS 上下文销毁')]);
    h.currentUrlValue = 'https://jw.example.com/schedule';

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractSilent>());
    expect(h.leaveCalls, 1);
    expect(h.extracting, [true, false]);
  });

  test('注入异常且不在课表页时返回错误', () async {
    final h = _Harness(responses: [Exception('网络错误')]);

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractError>());
    expect((outcome as WebviewExtractError).error.toString(), contains('网络错误'));
    expect(h.leaveCalls, 1);
    expect(h.extracting.last, isFalse);
  });

  test('空结果执行调试脚本并返回调试信息', () async {
    final h = _Harness(responses: [
      jsonEncode(<Object>[]),
      'URL: https://jw.example.com/schedule\n未找到课程元素',
    ]);

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractNotFound>());
    expect(
      (outcome as WebviewExtractNotFound).debugInfo,
      contains('未找到课程元素'),
    );
    expect(h.js.calls, hasLength(2));
    expect(h.js.calls[1], contains('outerHTML'));
    expect(h.js.calls[1], contains(r'/\[\d{4,}-\d{2,}/'));
    expect(h.js.calls[1], contains('未找到含课程编号的元素'));
    expect(h.leaveCalls, 1);
    expect(h.extracting.last, isFalse);
  });

  test('无法切换横屏时提示并继续抓取', () async {
    final h = _Harness(
      responses: [
        jsonEncode([_course('数据库')]),
      ],
      enterResult: false,
    );

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractPreview>());
    expect(h.layoutChecks, 0);
    expect(h.notices, ['无法自动切换横屏，请手动将手机旋转为横屏后再抓取']);
    expect(h.leaveCalls, 1);
  });

  test('横屏布局未生效时提示并继续抓取', () async {
    final h = _Harness(
      responses: [
        jsonEncode([_course('操作系统')]),
      ],
      layoutChanged: false,
    );

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractPreview>());
    expect(h.layoutChecks, 1);
    expect(h.notices, ['屏幕尚未切换为横屏，请手动旋转手机后再抓取']);
  });

  test('进入横屏后页面卸载时退出横屏并静默结束', () async {
    final h = _Harness(responses: const []);
    h.mounted = false;

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractSilent>());
    expect(h.leaveCalls, 1);
    expect(h.extracting, [true, false]);
    expect(h.js.calls, isEmpty);
  });

  test('页面缺少适配器或控制器时直接静默结束', () async {
    final h = _Harness(responses: const []);
    h.ready = false;

    final outcome = await h.protocol.run();

    expect(outcome, isA<WebviewExtractSilent>());
    expect(h.enterCalls, 0);
    expect(h.js.calls, isEmpty);
    expect(h.extracting, isEmpty);
  });
}