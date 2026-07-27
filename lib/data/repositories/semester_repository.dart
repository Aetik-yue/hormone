import 'package:drift/drift.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/data/app_database.dart' as db;
import 'package:hormone/data/mappers.dart';

/// 学期数据访问，含「激活学期」概念与首次启动播种。
class SemesterRepository {
  final db.AppDatabase _db;

  SemesterRepository(this._db);

  /// 监听全部学期（用于学期管理页）。
  Stream<List<Semester>> watchSemesters() {
    return _db.select(_db.semesters).watch().map(
          (rows) => rows.map((r) => r.toDomain()).toList(),
        );
  }

  Future<List<Semester>> getSemesters() async {
    final rows = await _db.select(_db.semesters).get();
    return rows.map((r) => r.toDomain()).toList();
  }

  /// 返回当前激活学期；若无任何学期，先播种默认学期再返回。
  /// 若已有学期但都未激活，将第一个设为激活并返回。
  Future<Semester?> getActiveSemester() async {
    await _db.seedDefaultSemester();

    final rows = await (_db.select(_db.semesters)
          ..where((s) => s.isActive.equals(true)))
        .get();
    if (rows.isNotEmpty) return rows.first.toDomain();

    // 有学期但都未激活：将第一个设为激活。
    final anySemester = await _db.select(_db.semesters).get();
    if (anySemester.isNotEmpty) {
      await (_db.update(_db.semesters)
            ..where((s) => s.id.equals(anySemester.first.id)))
          .write(const db.SemestersCompanion(isActive: Value(true)));
      return anySemester.first.toDomain();
    }

    return null;
  }

  /// 设为唯一激活学期（其余置为非激活）。
  /// 若 id 不存在，抛出 StateError 以避免零激活状态。
  Future<void> setActive(String id) async {
    final exists = await (_db.select(_db.semesters)
          ..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    if (exists == null) {
      throw StateError('Semester not found: $id');
    }
    await _db.batch((batch) {
      batch.update(
        _db.semesters,
        const db.SemestersCompanion(isActive: Value(false)),
      );
      batch.update(
        _db.semesters,
        const db.SemestersCompanion(isActive: Value(true)),
        where: (s) => s.id.equals(id),
      );
    });
  }

  /// 插入或更新（id 相同则冲突更新）。激活请使用 [setActive]。
  Future<void> upsert(Semester semester) async {
    final companion = semester.toCompanion();
    await _db
        .into(_db.semesters)
        .insertOnConflictUpdate(companion);
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.semesters)..where((s) => s.id.equals(id))).go();
  }
}
