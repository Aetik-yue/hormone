import 'dart:collection';

/// 根据最近一段时间的实际接收量识别持续低速，避免瞬时波动触发重新下载。
class SlowDownloadDetector {
  final Duration warmup;
  final Duration window;
  final Duration slowDuration;
  final Duration sampleInterval;
  final int minimumBytesPerSecond;
  final int minimumRemainingBytes;
  final double completionThreshold;
  final _samples = Queue<({Duration elapsed, int received})>();
  Duration? _slowSince;

  SlowDownloadDetector({
    this.warmup = const Duration(seconds: 10),
    this.window = const Duration(seconds: 10),
    this.slowDuration = const Duration(seconds: 15),
    this.sampleInterval = const Duration(seconds: 1),
    this.minimumBytesPerSecond = 32 * 1024,
    this.minimumRemainingBytes = 2 * 1024 * 1024,
    this.completionThreshold = 0.8,
  });

  bool shouldSwitch({
    required Duration elapsed,
    required int received,
    required int total,
  }) {
    if (elapsed < warmup) return false;
    // 临近完成时保留已有进度；未知大小仍可根据速度判断。
    if (total > 0 &&
        (received >= total * completionThreshold ||
            total - received <= minimumRemainingBytes)) {
      return false;
    }
    if (_samples.isNotEmpty &&
        elapsed - _samples.last.elapsed < sampleInterval) {
      return false;
    }
    _samples.add((elapsed: elapsed, received: received));
    final cutoff = elapsed - window;
    // 保留窗口起点前最近的一次采样，完整覆盖窗口。
    while (_samples.length > 1 && _samples.elementAt(1).elapsed <= cutoff) {
      _samples.removeFirst();
    }
    final first = _samples.first;
    final span = elapsed - first.elapsed;
    if (span < window || span.inMicroseconds <= 0) return false;
    final speed =
        (received - first.received) *
        Duration.microsecondsPerSecond /
        span.inMicroseconds;
    if (speed >= minimumBytesPerSecond) {
      _slowSince = null;
      return false;
    }
    _slowSince ??= elapsed;
    return elapsed - _slowSince! >= slowDuration;
  }
}
