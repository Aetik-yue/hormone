import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/update/domain/slow_download_detector.dart';

const _largeApk = 24 * 1024 * 1024;

void main() {
  test('预热和完整窗口之后仍持续低速才切源', () {
    final detector = SlowDownloadDetector();
    for (var second = 0; second < 35; second++) {
      expect(_sample(detector, second, second * 1024), isFalse);
    }
    expect(_sample(detector, 35, 35 * 1024), isTrue);
  });

  test('短暂低速恢复后重新计算持续时间', () {
    final detector = SlowDownloadDetector();
    for (var second = 0; second <= 29; second++) {
      expect(_sample(detector, second, second * 1024), isFalse);
    }
    // 一次真实传输恢复使滑动窗口不再低速。
    for (var second = 30; second < 55; second++) {
      expect(_sample(detector, second, 1024 * 1024 + second * 1024), isFalse);
    }
    expect(_sample(detector, 55, 1024 * 1024 + 55 * 1024), isTrue);
  });

  test('早期高速不能掩盖最近窗口内的持续低速', () {
    final detector = SlowDownloadDetector();
    for (var second = 0; second < 35; second++) {
      expect(
        _sample(detector, second, 5 * 1024 * 1024 + second * 1024),
        isFalse,
      );
    }
    expect(_sample(detector, 35, 5 * 1024 * 1024 + 35 * 1024), isTrue);
  });

  test('达到最低速度时保留当前源', () {
    final detector = SlowDownloadDetector();
    for (var second = 0; second < 100; second++) {
      expect(_sample(detector, second, second * 32 * 1024), isFalse);
    }
  });

  test('已完成八成时不因低速丢弃进度', () {
    final detector = SlowDownloadDetector();
    for (var second = 0; second < 100; second++) {
      expect(
        _sample(detector, second, 20 * 1024 * 1024 + second * 1024),
        isFalse,
      );
    }
  });

  test('小包仅剩两 MiB 以内时不因低速重新下载', () {
    final detector = SlowDownloadDetector();
    for (var second = 0; second < 100; second++) {
      expect(
        detector.shouldSwitch(
          elapsed: Duration(seconds: second),
          received: 1024 * 1024 + second * 1024,
          total: 3 * 1024 * 1024,
        ),
        isFalse,
      );
    }
  });

  test('未知大小也能识别持续低速', () {
    final detector = SlowDownloadDetector();
    var shouldSwitch = false;
    for (var second = 0; second <= 35; second++) {
      shouldSwitch = detector.shouldSwitch(
        elapsed: Duration(seconds: second),
        received: second * 1024,
        total: 0,
      );
    }
    expect(shouldSwitch, isTrue);
  });
}

bool _sample(SlowDownloadDetector detector, int second, int received) =>
    detector.shouldSwitch(
      elapsed: Duration(seconds: second),
      received: received,
      total: _largeApk,
    );
