import 'package:hormone/core/constants/app_constants.dart';
import 'package:hormone/core/utils/week_calculator.dart';
import 'package:hormone/features/import/domain/import_course.dart';

/// 自包含的 ICS（iCalendar）课程解析器。
///
/// 仅依赖标准库，避免外部包 API 形状变化带来的风险。覆盖课程表场景常见的
/// `VEVENT` + `RRULE:FREQ=WEEKLY`（含 `BYDAY` / `INTERVAL` / `COUNT` / `UNTIL`）。
///
/// 时区说明（MVP 简化）：忽略 `TZID`，将时间按学校本地时间处理；UTC（`Z` 后缀）
/// 直接按字面解析为本地时间。这对绝大多数「按本地上课时间导出」的课表足够。
class IcsCourseParser {
  static const _weekdayMap = {
    'MO': 1,
    'TU': 2,
    'WE': 3,
    'TH': 4,
    'FR': 5,
    'SA': 6,
    'SU': 7,
  };

  /// 解析整段 ICS 文本为导入课程列表。
  ///
  /// [semesterStart] 与 [totalWeeks] 用于把重复事件的真实日期映射到「教学周」。
  static List<ImportCourse> parse(
    String ics, {
    required DateTime semesterStart,
    required int totalWeeks,
  }) {
    final blocks = _extractVevents(_unfold(ics));
    final result = <ImportCourse>[];

    for (final ev in blocks) {
      final summary = _decode(ev['SUMMARY'] ?? '未命名课程');
      final location = _decode(ev['LOCATION']);
      final description = _decode(ev['DESCRIPTION']);
      final dtstart = ev['DTSTART'];
      if (dtstart == null) continue;

      final start = _parseDateTime(dtstart);
      if (start == null) continue;
      final end = ev['DTEND'] != null ? _parseDateTime(ev['DTEND']!) : null;

      final rrule = ev['RRULE'];
      final interval = (_parseInterval(rrule) ?? 1).clamp(1, 52);
      final count = _parseCount(rrule);
      final until = _parseUntil(rrule);
      final byDays = _parseByDays(rrule);

      // 首次上课所处的教学周。早于开学或无意义则跳过。
      final firstWeek = computeCurrentWeek(semesterStart, start);
      if (firstWeek < 1) continue;

      // 由 RRULE 推算所有上课周（每周一次，间隔 interval 周）。
      final weeks = _expandWeeks(
        firstWeek: firstWeek,
        interval: interval,
        count: count,
        until: until,
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
      );
      if (weeks.isEmpty) continue;

      final startSection = _sectionFromTime(_hhmm(start));
      final endSection = end != null
          ? _sectionFromTime(_hhmm(end))
          : startSection;
      if (endSection < startSection) {
        // 容错：结束节次低于开始节次时跳过该事件，避免污染其余解析。
        continue;
      }

      // 默认按 DTSTART 的星期；若 RRULE 指定了 BYDAY 则按每个星期各生成一条。
      final days = byDays.isNotEmpty ? byDays : [start.weekday];
      for (final d in days) {
        result.add(ImportCourse(
          name: summary,
          teacher: _extractTeacher(description),
          location: location,
          dayOfWeek: d,
          startSection: startSection,
          endSection: endSection,
          startTime: _hhmm(start),
          endTime: end != null ? _hhmm(end) : null,
          weeks: weeks,
          colorValue: _pickColor(result.length),
          notes: _stripTeacher(description),
          source: 'ics',
        ));
      }
    }
    return result;
  }

  // 工具：根据节次时间表把 "HH:MM" 反推到最接近的起始节次。
  static int _sectionFromTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 1;
    final mins = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    int best = 1;
    final sorted = AppConstants.sectionStartTimes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in sorted) {
      final sp = e.value.split(':');
      final sm = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
      if (sm <= mins) best = e.key;
    }
    return best;
  }

  /// 把重复事件展开为教学周列表。
  static List<int> _expandWeeks({
    required int firstWeek,
    required int interval,
    int? count,
    DateTime? until,
    required DateTime semesterStart,
    required int totalWeeks,
  }) {
    final weeks = <int>[];
    var w = firstWeek;
    var k = 0;
    while (w >= 1 && w <= totalWeeks) {
      weeks.add(w);
      k++;
      if (count != null && k >= count) break;
      if (until != null) {
        // Compute the actual course date for the next occurrence.
        final nextDate =
            semesterStart.add(Duration(days: k * interval * 7));
        if (nextDate.isAfter(until)) break;
      }
      w += interval;
    }
    return weeks;
  }

  // ---- 低层解析工具 ----

  /// 去掉换行续行（RFC5545 行折叠：以空格/制表符开头的行是上一行续接）。
  static List<String> _unfold(String ics) {
    final out = <String>[];
    for (var line in ics.split('\n')) {
      line = line.replaceAll('\r', '');
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (out.isNotEmpty) out[out.length - 1] += line.substring(1);
      } else {
        out.add(line);
      }
    }
    return out;
  }

  /// 提取所有 VEVENT 块为字段映射（键已去掉参数，如 `DTSTART;TZID=...` → `DTSTART`）。
  static List<Map<String, String>> _extractVevents(List<String> lines) {
    final events = <Map<String, String>>[];
    Map<String, String>? current;
    for (final raw in lines) {
      final line = raw.trim();
      if (line == 'BEGIN:VEVENT') {
        current = {};
      } else if (line == 'END:VEVENT') {
        if (current != null) events.add(current);
        current = null;
      } else if (current != null && line.contains(':')) {
        final idx = line.indexOf(':');
        final key = line.substring(0, idx).split(';').first;
        final value = line.substring(idx + 1);
        current[key] = value;
      }
    }
    return events;
  }

  /// 解析 ICS 日期时间：`20240902T080000`、`...Z`（UTC，按本地处理）、`20240902`。
  static DateTime? _parseDateTime(String s) {
    final v = s.replaceAll('Z', '').trim();
    try {
      if (v.length >= 15) {
        final y = int.parse(v.substring(0, 4));
        final mo = int.parse(v.substring(4, 6));
        final d = int.parse(v.substring(6, 8));
        final h = int.parse(v.substring(9, 11));
        final mi = int.parse(v.substring(11, 13));
        return DateTime(y, mo, d, h, mi);
      } else if (v.length >= 8) {
        final y = int.parse(v.substring(0, 4));
        final mo = int.parse(v.substring(4, 6));
        final d = int.parse(v.substring(6, 8));
        return DateTime(y, mo, d);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  static int? _parseInterval(String? rrule) {
    if (rrule == null) return null;
    return _intParam(rrule, 'INTERVAL');
  }

  static int? _parseCount(String? rrule) {
    if (rrule == null) return null;
    return _intParam(rrule, 'COUNT');
  }

  static DateTime? _parseUntil(String? rrule) {
    if (rrule == null) return null;
    final m = RegExp(r'UNTIL=([0-9TZ]+)').firstMatch(rrule);
    if (m == null) return null;
    return _parseDateTime(m.group(1)!);
  }

  static List<int> _parseByDays(String? rrule) {
    if (rrule == null) return const [];
    final m = RegExp(r'BYDAY=([^;]+)').firstMatch(rrule);
    if (m == null) return const [];
    return m
        .group(1)!
        .split(',')
        .map((d) => _weekdayMap[d.trim().toUpperCase()])
        .where((d) => d != null)
        .cast<int>()
        .toList();
  }

  static int? _intParam(String rrule, String key) {
    final m = RegExp('$key=([0-9]+)').firstMatch(rrule);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// 处理转义序列（常见 \\n、\\,、\\;）。
  static String _decode(String? s) {
    if (s == null) return '';
    return s
        .replaceAll(r'\\n', '\n')
        .replaceAll(r'\\N', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';');
  }

  /// 从 DESCRIPTION 提取教师（形如 "教师: 张三" / "teacher:张三" / "张三"）。
  static String? _extractTeacher(String? description) {
    if (description == null || description.isEmpty) return null;
    final m = RegExp(r'(?:教师|teacher|授课教师)\s*[:：]\s*(.+)',
            caseSensitive: false)
        .firstMatch(description);
    if (m != null) return m.group(1)?.trim();
    // 退而求其次：取第一句非空文本作为教师。
    final first = description.split(RegExp(r'[\n;；]')).first.trim();
    return first.isEmpty ? null : first;
  }

  static String? _stripTeacher(String? description) {
    if (description == null) return null;
    // 去掉已单独提取的教师片段，保留其余备注。
    return description
        .replaceAll(RegExp(r'(?:教师|teacher|授课教师)\s*[:：]\s*\S+',
            caseSensitive: false), '')
        .replaceAll(RegExp(r'[\n\s]+'), ' ')
        .trim();
  }

  static int _pickColor(int index) {
    const palette = [
      0xFF5B8DEF,
      0xFFE57373,
      0xFF81C784,
      0xFFFFB74D,
      0xFFBA68C8,
      0xFF4DB6AC,
      0xFFA1887F,
      0xFF9575CD,
      0xFF7986CB,
      0xFF4FC3F7,
    ];
    return palette[index % palette.length];
  }
}
