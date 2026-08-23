import 'package:flutter/services.dart';

typedef PreferredOrientationsSetter = Future<void> Function(
  List<DeviceOrientation> orientations,
);

/// 课程抓取阶段的屏幕方向控制器。
///
/// 教务课表通常按桌面七列表格渲染，竖屏下响应式布局会改变课程卡片和星期
/// 表头的横坐标。抓取脚本依赖这些坐标判断星期，因此登录和抓取阶段固定横屏，
/// 进入预览或离开页面时恢复竖屏。
class CourseCaptureOrientationController {
  final PreferredOrientationsSetter _setPreferredOrientations;
  bool _landscapeRequested = false;

  CourseCaptureOrientationController({
    PreferredOrientationsSetter? setPreferredOrientations,
  }) : _setPreferredOrientations =
            setPreferredOrientations ?? SystemChrome.setPreferredOrientations;

  bool get isLandscapeRequested => _landscapeRequested;

  /// 进入稳定的横屏抓取环境。平台拒绝方向请求时返回 false。
  Future<bool> enterCaptureMode() async {
    if (_landscapeRequested) return true;
    _landscapeRequested = true;
    try {
      await _setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      return true;
    } catch (_) {
      _landscapeRequested = false;
      return false;
    }
  }

  /// 恢复 App 的竖屏课表布局。重复调用不会重复请求平台。
  Future<void> leaveCaptureMode() async {
    if (!_landscapeRequested) return;
    _landscapeRequested = false;
    try {
      await _setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    } catch (_) {
      // 屏幕方向恢复失败不应影响课程预览、导入或页面退出。
    }
  }
}
