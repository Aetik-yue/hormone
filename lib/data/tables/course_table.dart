import 'package:drift/drift.dart';

/// 课程持久化表。
///
/// [weeks] 以逗号分隔的整数字符串存储（如 "1,2,3,16"），避免为周次单独建表，
/// 对课表类应用足够且查询简单。映射逻辑见 [lib/data/mappers.dart]。
class Courses extends Table {
  TextColumn get id => text()();

  TextColumn get semesterId => text()();

  TextColumn get name => text()();

  TextColumn get teacher => text().nullable()();

  TextColumn get location => text().nullable()();

  /// 1=周一 .. 7=周日，与 [DateTime.weekday] 一致。
  IntColumn get dayOfWeek => integer()();

  IntColumn get startSection => integer()();

  IntColumn get endSection => integer()();

  /// "08:00" 可选，未填写时由节次时间表推算。
  TextColumn get startTime => text().nullable()();

  TextColumn get endTime => text().nullable()();

  /// 上课周次 CSV，如 "1,2,3,16"。空串表示未设置。
  TextColumn get weeks => text().withDefault(const Constant(''))();

  /// 卡片主题色（ARGB int）。
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF5B8DEF))();

  TextColumn get notes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
