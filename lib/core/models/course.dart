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
  })  : assert(dayOfWeek >= 1 && dayOfWeek <= 7, 'dayOfWeek must be 1-7'),
        assert(startSection >= 1, 'startSection must be >= 1'),
        assert(endSection >= startSection, 'endSection must be >= startSection');

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Course &&
          id == other.id &&
          semesterId == other.semesterId &&
          name == other.name &&
          teacher == other.teacher &&
          location == other.location &&
          dayOfWeek == other.dayOfWeek &&
          startSection == other.startSection &&
          endSection == other.endSection &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          _listEquals(weeks, other.weeks) &&
          colorValue == other.colorValue &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(
        id,
        semesterId,
        name,
        teacher,
        location,
        dayOfWeek,
        startSection,
        endSection,
        startTime,
        endTime,
        Object.hashAll(weeks),
        colorValue,
        notes,
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
