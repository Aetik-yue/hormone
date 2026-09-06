import 'section_time.dart';

/// 无法整体调整时间时的可读原因；调用方保持原配置并提示用户。
class SectionTimeShiftException implements Exception {
  final String message;

  const SectionTimeShiftException(this.message);
}

/// 以第一节的新开始时间为基准，将已设置的节次整体平移。
///
/// 保留各节课长及所有间隔（包括午休、晚休）；空节次不自动填充。
/// 先校验整张时间表，避免跨天时仅修改部分节次或静默绕回当天。
Map<int, SectionTime> shiftSectionTimes(
  Map<int, SectionTime> times,
  String firstStart,
) {
  final originalFirst = _minutes(times[1]?.startTime ?? '');
  if (originalFirst == null) {
    throw const SectionTimeShiftException('请先设置第一节时间，或应用节次模板后再同步顺延');
  }
  final newFirst = _minutes(firstStart);
  if (newFirst == null) {
    throw const SectionTimeShiftException('请选择有效的第一节开始时间');
  }
  final offset = newFirst - originalFirst;
  final shifted = <int, SectionTime>{};
  for (final entry in times.entries) {
    final time = entry.value;
    if (time.startTime.isEmpty) {
      shifted[entry.key] = time;
      continue;
    }
    final start = _minutes(time.startTime);
    if (start == null || time.durationMinutes <= 0) {
      throw SectionTimeShiftException('第 ${entry.key} 节时间无效，请先单独调整该节');
    }
    final next = start + offset;
    if (next < 0 || next >= 1440 || next + time.durationMinutes > 1440) {
      throw SectionTimeShiftException(
        '调整后第 ${entry.key} 节会超出当天，请缩小调整幅度或关闭同步顺延',
      );
    }
    final formatted =
        '${(next ~/ 60).toString().padLeft(2, '0')}:'
        '${(next % 60).toString().padLeft(2, '0')}';
    shifted[entry.key] = SectionTime(formatted, time.durationMinutes);
  }
  return shifted;
}

int? _minutes(String time) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
  if (match == null) return null;
  final hour = int.parse(match[1]!);
  final minute = int.parse(match[2]!);
  return hour < 24 && minute < 60 ? hour * 60 + minute : null;
}
