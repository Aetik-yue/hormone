/// 单节课的时间配置：开始时间 + 时长（分钟）。
class SectionTime {
  final String startTime; // "HH:mm"
  final int durationMinutes;

  const SectionTime(this.startTime, this.durationMinutes);

  /// 计算结束时间字符串。溢出 24h 时取模。
  String get endTime {
    final parts = startTime.split(':');
    if (parts.length != 2) return '';
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return '';
    var total = (h * 60 + m + durationMinutes) % (24 * 60);
    if (total < 0) total += 24 * 60;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// 完整时间范围显示，如 "08:00-08:45"。
  String get timeRange => '$startTime-$endTime';
}
