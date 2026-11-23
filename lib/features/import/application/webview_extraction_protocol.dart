import 'dart:async';

import 'package:recess/features/import/domain/webview_course_parser.dart';

/// WebView 抓取协议的最终结果。屏幕只负责把它映射成 UI。
sealed class WebviewExtractOutcome {
  const WebviewExtractOutcome();
}

/// 抓取成功，得到可提交的预览。
final class WebviewExtractPreview extends WebviewExtractOutcome {
  const WebviewExtractPreview(this.preview);

  final WebviewCoursePreview preview;
}

/// 抓取为空，附带供「查看详情」展示的调试信息。
final class WebviewExtractNotFound extends WebviewExtractOutcome {
  const WebviewExtractNotFound(this.debugInfo);

  final String debugInfo;
}

/// 自动导航课表页重试超过上限。
final class WebviewExtractNavFailed extends WebviewExtractOutcome {
  const WebviewExtractNavFailed();
}

/// 无需提示的退出：页面已卸载、注入异常时已在课表页等待自动重试，
/// 或重试期间已被新的一轮抓取取代。
final class WebviewExtractSilent extends WebviewExtractOutcome {
  const WebviewExtractSilent();
}

/// 抓取异常，需要在页面上提示。
final class WebviewExtractError extends WebviewExtractOutcome {
  const WebviewExtractError(this.error);

  final Object error;
}

/// WebView 抓取协议：等待渲染、注入脚本、处理适配器的导航/等待信号并重试。
///
/// 平台相关能力全部由调用方注入，便于用 fake 执行器测试重试与等待时序。
class WebviewExtractionProtocol {
  WebviewExtractionProtocol({
    required this.isReady,
    required this.isMounted,
    required this.enterCaptureMode,
    required this.leaveCaptureMode,
    required this.waitForLandscapeLayout,
    required this.wait,
    required this.executeJs,
    required this.loadPreviewContext,
    required this.buildExtractJs,
    required this.currentUrl,
    required this.isSchedulePage,
    required this.onExtracting,
    required this.onNotice,
  });

  static const initialRenderWait = Duration(seconds: 2);
  static const navRetryWait = Duration(seconds: 3);
  static const pendingRetryWait = Duration(seconds: 2);
  static const maxNavRetries = 3;

  final bool Function() isReady;
  final bool Function() isMounted;
  final Future<bool> Function() enterCaptureMode;
  final Future<void> Function() leaveCaptureMode;
  final Future<bool> Function() waitForLandscapeLayout;
  final Future<void> Function(Duration duration) wait;
  final Future<dynamic> Function(String js) executeJs;
  final Future<WebviewPreviewContext> Function() loadPreviewContext;
  final String Function(WebviewPreviewContext context) buildExtractJs;
  final Future<String?> Function() currentUrl;
  final bool Function(String url) isSchedulePage;
  final void Function(bool extracting) onExtracting;
  final void Function(String message) onNotice;

  int _navRetries = 0;

  /// 运行代数：重试等待期间若页面加载触发新的一轮抓取，旧链据此自我中止。
  int _generation = 0;

  Future<WebviewExtractOutcome> run() async {
    if (!isReady()) return const WebviewExtractSilent();
    final generation = ++_generation;
    onExtracting(true);
    try {
      final early = await _prepareCapture();
      if (early != null) return early;

      while (true) {
        // 等待 SPA 动态渲染完成
        await wait(initialRenderWait);
        if (!isMounted()) {
          await leaveCaptureMode();
          onExtracting(false);
          return const WebviewExtractSilent();
        }

        final context = await loadPreviewContext();
        final raw = await executeJs(buildExtractJs(context));
        final decoded = decodeWebviewExtractResult(raw);

        // 适配器导航/等待信号：已跳转课表页或课表仍在加载，延迟后自动重试
        if (decoded is Map<String, dynamic> &&
            (decoded['__nav'] == true || decoded['__pending'] == true)) {
          onExtracting(false);
          if (_navRetries >= maxNavRetries) {
            _navRetries = 0;
            await leaveCaptureMode();
            return const WebviewExtractNavFailed();
          }
          _navRetries++;
          final isNav = decoded['__nav'] == true;
          await wait(isNav ? navRetryWait : pendingRetryWait);
          // 等待期间页面可能已加载完成并启动了新的一轮抓取；旧链让位，
          // 不再碰抓取状态或屏幕方向，避免两条链并发注入。
          if (generation != _generation) {
            return const WebviewExtractSilent();
          }
          if (!isMounted()) {
            await leaveCaptureMode();
            return const WebviewExtractSilent();
          }
          onExtracting(true);
          // 与旧实现的重试递归一致：每次重试都重新确认横屏布局。
          final retryEarly = await _prepareCapture();
          if (retryEarly != null) return retryEarly;
          continue;
        }
        _navRetries = 0;

        if (decoded == null) {
          throw Exception('未抓取到课程数据，请确认已进入课表页面后重试');
        }
        if (decoded is! List) {
          throw Exception('课表数据格式异常，请确认已进入课表页面后重试');
        }

        final preview = previewWebviewCourses(decoded, context);
        if (preview.courses.isEmpty && preview.skippedCount == 0) {
          // 抓取为空，捕获调试信息供「查看详情」展示。
          final debugRaw = await executeJs(_debugInfoJs);
          final debugInfo = debugRaw is String ? debugRaw : debugRaw.toString();
          onExtracting(false);
          await leaveCaptureMode();
          return WebviewExtractNotFound(debugInfo);
        }

        onExtracting(false);
        await leaveCaptureMode();
        return WebviewExtractPreview(preview);
      }
    } catch (e) {
      onExtracting(false);
      await leaveCaptureMode();
      if (!isMounted()) return const WebviewExtractSilent();
      // 跳转进行中注入异常（JS 上下文销毁）时静默等待，onPageFinished 会自动重试
      final url = await currentUrl();
      if (url != null && isSchedulePage(url)) {
        return const WebviewExtractSilent();
      }
      return WebviewExtractError(e);
    }
  }

  /// 进入抓取所需的横屏环境；返回非 null 表示应直接结束。
  Future<WebviewExtractOutcome?> _prepareCapture() async {
    // 登录和浏览阶段保持正常竖屏，只在坐标敏感的抓取瞬间临时横屏。
    final landscapeReady = await enterCaptureMode();
    if (!isMounted()) {
      await leaveCaptureMode();
      onExtracting(false);
      return const WebviewExtractSilent();
    }
    if (!landscapeReady) {
      onNotice('无法自动切换横屏，请手动将手机旋转为横屏后再抓取');
    } else {
      // 等待 Android 完成 Activity 与 WebView 尺寸变更，避免读取旧的竖屏坐标。
      final layoutChanged = await waitForLandscapeLayout();
      if (!isMounted()) {
        await leaveCaptureMode();
        onExtracting(false);
        return const WebviewExtractSilent();
      }
      if (!layoutChanged) {
        onNotice('屏幕尚未切换为横屏，请手动旋转手机后再抓取');
      }
    }
    return null;
  }
}

/// 空结果时收集页面结构，帮助判断教务系统是否使用了未支持的渲染方式。
const String _debugInfoJs = r'''
  (function() {
    var info = 'URL: ' + location.href + '\n\n';
    var els = document.body.querySelectorAll('*');
    var found = false;
    for (var i = 0; i < els.length; i++) {
      var t = (els[i].textContent || '');
      if (/\[\d{4,}-\d{2,}/.test(t) && t.length < 300 && t.length > 10) {
        info += '=== 课程元素 outerHTML ===\n';
        info += els[i].outerHTML.substring(0, 800) + '\n\n';
        info += '=== 父元素 outerHTML (前1500字符) ===\n';
        var p = els[i].parentElement;
        if (p) info += p.outerHTML.substring(0, 1500);
        found = true;
        break;
      }
    }
    if (!found) {
      info += '未找到含课程编号的元素\n\n';
      info += '=== body.innerText 前1500字符 ===\n';
      info += (document.body ? document.body.innerText : '').substring(0, 1500);
    }
    return info;
  })()
''';