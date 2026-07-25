import 'package:drift/drift.dart';
import 'package:hormone/core/models/course.dart';
import 'package:hormone/data/app_database.dart' as db;
import 'package:hormone/data/mappers.dart';

/// 课程数据访问。所有方法以领域模型 [Course] 与外界交互，
/// 内部使用 drift 实体与流式监听，支撑离线优先与实时 UI 更新。
class CourseRepository {
  final db.AppDatabase _db;

  CourseRepository(this._db);

  /// 监听某学期全部课程（按星期、节次排序），UI 直接消费流。
  Stream<List<Course>> watchCourses(String semesterId) {
    final query = _db.select(_db.courses)
      ..where((c) => c.semesterId.equals(semesterId))
      ..orderBy([
        (c) => OrderingTerm.asc(c.dayOfWeek),
        (c) => OrderingTerm.asc(c.startSection),
      ]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  Future<List<Course>> getCourses(String semesterId) async {
    final rows = await (_db.select(_db.courses)
          ..where((c) => c.semesterId.equals(semesterId)))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  /// 按 id 查询单门课程（编辑页加载已有数据）。
  Future<Course?> getCourse(String id) async {
    final row = await (_db.select(_db.courses)
          ..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  /// 插入或更新（id 相同则冲突更新），供编辑页与导入复用。
  Future<void> upsert(Course course) async {
    await _db
        .into(_db.courses)
        .insertOnConflictUpdate(course.toCompanion());
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.courses)..where((c) => c.id.equals(id))).go();
  }

  /// 删除某学期下全部课程（更换/删除学期时清理）。
  Future<void> deleteBySemester(String semesterId) async {
    await (_db.delete(_db.courses)
          ..where((c) => c.semesterId.equals(semesterId)))
        .go();
  }
}
