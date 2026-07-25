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
  Future<Semester?> getActiveSemester() async {
    await _db.seedDefaultSemester();
    final rows = await (_db.select(_db.semesters)
          ..where((s) => s.isActive.equals(true)))
        .get();
    return rows.isEmpty ? null : rows.first.toDomain();
  }

  /// 设为唯一激活学期（其余置为非激活）。
  Future<void> setActive(String id) async {
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

  Future<void> upsert(Semester semester, {bool activate = false}) async {
    final companion = semester.toCompanion(isActive: activate);
    await _db
        .into(_db.semesters)
        .insertOnConflictUpdate(companion);
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.semesters)..where((s) => s.id.equals(id))).go();
  }
}
