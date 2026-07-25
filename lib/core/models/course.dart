/// 单门课程。周次以 [weeks] 列表表示（如 [1,2,3,5,6,..18]）。
class Course {
  final String id;
  final String semesterId;
  final String name;
  final String? teacher;
  final String? location;
  final int dayOfWeek; // 1=周一 .. 7=周日
  final int startSection;
  final int endSection;
  final String? startTime; // "08:00"
  final String? endTime; // "08:45"
  final List<int> weeks;
  final int colorValue; // 卡片主题色（ARGB）
  final String? notes;

  const Course({
    required this.id,
    required this.semesterId,
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
  });

  Course copyWith({
    String? id,
    String? semesterId,
    String? name,
    String? teacher,
    String? location,
    int? dayOfWeek,
    int? startSection,
    int? endSection,
    String? startTime,
    String? endTime,
    List<int>? weeks,
    int? colorValue,
    String? notes,
  }) =>
      Course(
        id: id ?? this.id,
        semesterId: semesterId ?? this.semesterId,
        name: name ?? this.name,
        teacher: teacher ?? this.teacher,
        location: location ?? this.location,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        startSection: startSection ?? this.startSection,
        endSection: endSection ?? this.endSection,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        weeks: weeks ?? this.weeks,
        colorValue: colorValue ?? this.colorValue,
        notes: notes ?? this.notes,
      );
}
