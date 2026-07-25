import 'package:hormone/core/models/course.dart';

/// 导入过程中的单门课程中间表示。
///
/// 与持久化无关，仅承载「从 ICS/JSON 解析出来、尚未写入数据库」的字段。
/// 预览阶段可在 UI 中逐条勾选是否导入（[selected]）。
class ImportCourse {
  final String name;
  final String? teacher;
  final String? location;
  final int dayOfWeek; // 1=周一 .. 7=周日
  final int startSection;
  final int endSection;
  final String? startTime; // "08:00"
  final String? endTime; // "08:45"
  final List<int> weeks;
  final int colorValue;
  final String? notes;
  final String source; // 'ics' | 'json'
  bool selected;

  ImportCourse({
    required this.name,
    this.teacher,
    this.location,
    required this.dayOfWeek,
    required this.startSection,
    required this.endSection,
    this.startTime,
    this.endTime,
    this.weeks = const [],
    this.colorValue = 0xFF5B8DEF,
    this.notes,
    required this.source,
    this.selected = true,
  });

  /// 转换为领域模型 [Course]（生成新 id，归属指定学期）。
  Course toCourse(String semesterId) => Course(
        id: '',
        semesterId: semesterId,
        name: name,
        teacher: teacher,
        location: location,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        startTime: startTime,
        endTime: endTime,
        weeks: weeks,
        colorValue: colorValue,
        notes: notes,
      );

  /// 人类可读的星期+节次摘要，用于预览卡片副标题。
  String get sectionLabel {
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final day = dayOfWeek >= 1 && dayOfWeek <= 7 ? days[dayOfWeek - 1] : '?';
    final time = (startTime != null && endTime != null)
        ? ' $startTime-$endTime'
        : '';
    return '$day 第$startSection-${endSection}节$time';
  }

  /// 周次摘要（如「1-18周」或「1,3,5周」）。
  String get weekLabel {
    if (weeks.isEmpty) return '未排周次';
    final sorted = [...weeks]..sort();
    if (sorted.length == 1) return '第${sorted.first}周';
    if (sorted.last - sorted.first == sorted.length - 1) {
      return '${sorted.first}-${sorted.last}周';
    }
    return '${sorted.join(',')}周';
  }
}

/// 判断两门导入课程是否时间冲突：同一星期、节次重叠且周次有交集。
bool coursesConflict(ImportCourse a, ImportCourse b) {
  if (a.dayOfWeek != b.dayOfWeek) return false;
  final sectionsOverlap =
      a.startSection <= b.endSection && b.startSection <= a.endSection;
  if (!sectionsOverlap) return false;
  final weekOverlap = a.weeks.any((w) => b.weeks.contains(w));
  return weekOverlap;
}
