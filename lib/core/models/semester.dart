/// 学期。用于推算当前周与周次切换。
class Semester {
  final String id;
  final String name;
  final DateTime startDate; // 开学第一天
  final int totalWeeks;
  final int? currentWeekOverride; // 手动覆盖当前周（调课/假期）

  const Semester({
    required this.id,
    required this.name,
    required this.startDate,
    required this.totalWeeks,
    this.currentWeekOverride,
  });

  Semester copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    int? totalWeeks,
    Object? currentWeekOverride = _sentinel,
  }) =>
      Semester(
        id: id ?? this.id,
        name: name ?? this.name,
        startDate: startDate ?? this.startDate,
        totalWeeks: totalWeeks ?? this.totalWeeks,
        currentWeekOverride: identical(currentWeekOverride, _sentinel)
            ? this.currentWeekOverride
            : currentWeekOverride as int?,
      );

  static const _sentinel = Object();
}
