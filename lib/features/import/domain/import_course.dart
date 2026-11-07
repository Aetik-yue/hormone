import 'package:recess/core/constants/app_constants.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/course_platform.dart';

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
  final bool useExplicitTimes;
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
    bool? useExplicitTimes,
    this.weeks = const [],
    this.colorValue = AppConstants.defaultCourseColor,
    this.notes,
    required this.source,
    this.selected = true,
  }) : useExplicitTimes = useExplicitTimes ??
            (startTime != null || endTime != null);

  /// 返回勾选状态改为 [selected] 的副本；`selected` 字段本身保持可变。
  ImportCourse withSelected(bool selected) => ImportCourse(
        name: name,
        teacher: teacher,
        location: location,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        startTime: startTime,
        endTime: endTime,
        useExplicitTimes: useExplicitTimes,
        weeks: weeks,
        colorValue: colorValue,
        notes: notes,
        source: source,
        selected: selected,
      );

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
        useExplicitTimes: useExplicitTimes,
        weeks: weeks,
        colorValue: colorValue,
        notes: notes,
      );

  /// 人类可读的星期+节次摘要，用于预览卡片副标题。
  String get sectionLabel {
    final day = dayOfWeek >= 1 && dayOfWeek <= 7
        ? '周${AppConstants.weekdayLabels[dayOfWeek - 1]}'
        : '?';
    final time = (useExplicitTimes && startTime != null && endTime != null)
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

/// 只保留实际导入的课程（预览中勾选的）所对应的课程平台，课程名 trim 后匹配。
/// 取消勾选的课程不应把平台写进目标学期。
CoursePlatformGroups platformsForImportedCourses(
  CoursePlatformGroups platforms,
  Iterable<ImportCourse> imported,
) {
  final names = {for (final c in imported) c.name.trim()};
  return {
    for (final entry in platforms.entries)
      if (names.contains(entry.key.trim())) entry.key: entry.value,
  };
}

/// 同一星期、节次重叠且周次有交集。
bool _overlaps(
  int dayOfWeek,
  int startSection,
  int endSection,
  List<int> weeks,
  int otherDayOfWeek,
  int otherStartSection,
  int otherEndSection,
  List<int> otherWeeks,
) =>
    dayOfWeek == otherDayOfWeek &&
    startSection <= otherEndSection &&
    otherStartSection <= endSection &&
    weeks.any(otherWeeks.contains);

/// 判断两门导入课程是否时间冲突：同一星期、节次重叠且周次有交集。
bool coursesConflict(ImportCourse a, ImportCourse b) => _overlaps(
      a.dayOfWeek, a.startSection, a.endSection, a.weeks,
      b.dayOfWeek, b.startSection, b.endSection, b.weeks,
    );

/// 判断导入课程与已落库课程是否时间冲突（合并导入时提示用户）。
bool conflictsWithCourse(ImportCourse a, Course b) => _overlaps(
      a.dayOfWeek, a.startSection, a.endSection, a.weeks,
      b.dayOfWeek, b.startSection, b.endSection, b.weeks,
    );

/// 返回存在时间冲突的已选课程名称集合（内部冲突 + 与现有课表冲突）。
Set<String> conflictNames(List<ImportCourse> courses, List<Course> existing) {
  final selected = courses.where((c) => c.selected).toList();
  final names = <String>{};
  for (var i = 0; i < selected.length; i++) {
    for (var j = i + 1; j < selected.length; j++) {
      if (coursesConflict(selected[i], selected[j])) {
        names
          ..add(selected[i].name)
          ..add(selected[j].name);
      }
    }
    for (final e in existing) {
      if (conflictsWithCourse(selected[i], e)) {
        names.add(selected[i].name);
      }
    }
  }
  return names;
}

/// 导入模式：替换当前学期课表，或在现有课表上合并追加。
enum ImportMode {
  /// 整体替换：先清空当前学期课程，再写入所选课程。
  replace,

  /// 合并追加：保留现有课程，把所选课程以新 id 追加进去。
  merge,
}
