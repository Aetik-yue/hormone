import 'package:drift/drift.dart';
import 'package:recess/core/models/course_platform.dart';
import 'package:recess/data/app_database.dart' as db;
import 'package:recess/data/mappers.dart';

/// 课程平台数据访问。平台按「学期 id + 课程名」归属（课程名 trim 后精确
/// 匹配），同一学期内同名课程共享一组平台，见 docs/adr/0001。
///
/// 对外只暴露领域模型 [CoursePlatform]。
class CoursePlatformRepository {
  final db.AppDatabase _db;

  CoursePlatformRepository(this._db);

  /// 监听某门课的平台（按组内顺序），详情面板直接消费流。
  Stream<List<CoursePlatform>> watchPlatforms(
    String semesterId,
    String courseName,
  ) {
    return _query(semesterId, courseName)
        .watch()
        .map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  Future<List<CoursePlatform>> getPlatforms(
    String semesterId,
    String courseName,
  ) async {
    final rows = await _query(semesterId, courseName).get();
    return rows.map((r) => r.toDomain()).toList();
  }

  /// 某学期的全部平台，按课程名分组（JSON 备份导出使用）。
  Future<CoursePlatformGroups> getPlatformsBySemester(
    String semesterId,
  ) async {
    final rows = await (_db.select(_db.coursePlatforms)
          ..where((p) => p.semesterId.equals(semesterId))
          ..orderBy([
            (p) => OrderingTerm.asc(p.courseName),
            (p) => OrderingTerm.asc(p.sortOrder),
          ]))
        .get();
    final CoursePlatformGroups result = {};
    for (final row in rows) {
      result.putIfAbsent(row.courseName, () => []).add(row.toDomain());
    }
    return result;
  }

  /// 用 [platforms] 整体替换某门课的平台列表，列表顺序即显示顺序。
  Future<void> replacePlatforms(
    String semesterId,
    String courseName,
    List<CoursePlatform> platforms,
  ) {
    final name = courseName.trim();
    return _db.transaction(() async {
      await _deleteFor(semesterId, name);
      if (platforms.isEmpty) return;
      await _db.batch((batch) {
        batch.insertAll(
          _db.coursePlatforms,
          platforms.toCompanions(semesterId: semesterId, courseName: name),
        );
      });
    });
  }

  /// 课程从 [from] 改名为 [to] 后调用（课程本身已保存）。
  ///
  /// 新名下还没有平台时，把旧名下的平台复制过去；之后若本学期已没有课程
  /// 使用旧名，删除旧名下的平台，避免留下没人认领的数据。
  Future<void> migrateOnRename(
    String semesterId, {
    required String from,
    required String to,
  }) {
    final oldName = from.trim();
    final newName = to.trim();
    if (oldName == newName) return Future.value();
    return _db.transaction(() async {
      final oldPlatforms = await getPlatforms(semesterId, oldName);
      if (oldPlatforms.isEmpty) return;
      final existing = await getPlatforms(semesterId, newName);
      if (existing.isEmpty) {
        await replacePlatforms(semesterId, newName, oldPlatforms);
      }
      final stillUsed = await (_db.select(_db.courses)
            ..where((c) => c.semesterId.equals(semesterId)))
          .get()
          .then((rows) => rows.any((c) => c.name.trim() == oldName));
      if (!stillUsed) await _deleteFor(semesterId, oldName);
    });
  }

  SimpleSelectStatement<db.$CoursePlatformsTable, db.CoursePlatform> _query(
    String semesterId,
    String courseName,
  ) {
    return _db.select(_db.coursePlatforms)
      ..where((p) =>
          p.semesterId.equals(semesterId) &
          p.courseName.equals(courseName.trim()))
      ..orderBy([(p) => OrderingTerm.asc(p.sortOrder)]);
  }

  Future<void> _deleteFor(String semesterId, String courseName) async {
    await (_db.delete(_db.coursePlatforms)
          ..where((p) =>
              p.semesterId.equals(semesterId) &
              p.courseName.equals(courseName)))
        .go();
  }
}
