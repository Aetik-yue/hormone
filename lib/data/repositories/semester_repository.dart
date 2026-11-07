import 'package:drift/drift.dart';
import 'package:recess/core/models/semester.dart';
import 'package:recess/core/utils/week_calculator.dart';
import 'package:recess/data/app_database.dart' as db;
import 'package:recess/data/mappers.dart';

/// 学期数据访问，含「激活学期」概念与首次启动播种。
class SemesterRepository {
  final db.AppDatabase _db;

  SemesterRepository(this._db);

  Future<List<Semester>> getSemesters() async {
    final rows = await _db.select(_db.semesters).get();
    return rows.map((r) => r.toDomain()).toList();
  }

  /// 返回当前激活学期；若无任何学期，先播种默认学期再返回。
  /// 若已有学期但都未激活，将第一个设为激活并返回。
  Future<Semester?> getActiveSemester() async {
    return _db.transaction(() async {
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
    });
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

  /// 插入或更新；[activate] 为 true 时在同一事务内设为唯一激活学期。
  Future<void> upsert(Semester semester, {bool activate = false}) async {
    await _db.transaction(() async {
      await _db
          .into(_db.semesters)
          .insertOnConflictUpdate(
            normalizeSemesterWeeks(semester).toCompanion(),
          );
      if (activate) await setActive(semester.id);
    });
  }

  Future<void> delete(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.courses)
            ..where((c) => c.semesterId.equals(id)))
          .go();
      await (_db.delete(_db.coursePlatforms)
            ..where((p) => p.semesterId.equals(id)))
          .go();
      await (_db.delete(_db.semesters)..where((s) => s.id.equals(id))).go();
      await getActiveSemester();
    });
  }
}
