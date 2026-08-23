import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/features/import/application/course_capture_orientation.dart';

void main() {
  test('抓取阶段只请求一次横屏，结束后只请求一次竖屏', () async {
    final calls = <List<DeviceOrientation>>[];
    final controller = CourseCaptureOrientationController(
      setPreferredOrientations: (orientations) async {
        calls.add(List.of(orientations));
      },
    );

    expect(await controller.enterCaptureMode(), isTrue);
    expect(await controller.enterCaptureMode(), isTrue);
    expect(controller.isLandscapeRequested, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single, const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    await controller.leaveCaptureMode();
    await controller.leaveCaptureMode();
    expect(controller.isLandscapeRequested, isFalse);
    expect(calls, hasLength(2));
    expect(calls.last, const [DeviceOrientation.portraitUp]);
  });

  test('平台拒绝横屏请求时返回 false 且允许再次尝试', () async {
    var attempts = 0;
    final controller = CourseCaptureOrientationController(
      setPreferredOrientations: (_) async {
        attempts++;
        throw PlatformException(code: 'orientation_denied');
      },
    );

    expect(await controller.enterCaptureMode(), isFalse);
    expect(await controller.enterCaptureMode(), isFalse);
    expect(controller.isLandscapeRequested, isFalse);
    expect(attempts, 2);
  });
}
