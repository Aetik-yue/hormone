import 'package:drift/drift.dart';

/// 学期持久化表。用于推算当前周、周次切换与学期管理。
class Semesters extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  /// 开学第一天（日期，忽略时间部分）。
  DateTimeColumn get startDate => dateTime()();

  IntColumn get totalWeeks => integer()();

  /// 手动覆盖的当前周（调课/假期）。null 表示按开学日期自动推算。
  IntColumn get currentWeekOverride => integer().nullable()();

  /// 是否当前激活学期（同一时刻至多一个为 true）。
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
