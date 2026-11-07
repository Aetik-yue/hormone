import 'package:drift/drift.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/course_platform.dart';
import 'package:recess/data/app_database.dart' as db;
import 'package:recess/data/mappers.dart';
import 'package:recess/data/repositories/course_platform_repository.dart';

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
    final row = await (_db.select(_db.courses)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  /// 插入或更新（id 相同则冲突更新），供编辑页与导入复用。
  /// [course.id] 必须非空，否则多条记录会碰撞到同一行。
  Future<void> upsert(Course course) async {
    if (course.id.isEmpty) {
      throw ArgumentError('Course.id must not be empty');
    }
    await _db.into(_db.courses).insertOnConflictUpdate(course.toCompanion());
  }

  /// 编辑页保存：写入课程，并在同一事务内处理课程平台。
  ///
  /// [renamedFrom] 为编辑已有课程时的原课程名，名字变了就做改名迁移；
  /// [platforms] 非 null 时整体写到当前课程名下。任何一步失败整体回滚，
  /// 不会出现课程已改名、平台却留在旧名下的半截状态。
  Future<void> saveWithPlatforms(
    Course course, {
    String? renamedFrom,
    List<CoursePlatform>? platforms,
  }) {
    final platformRepo = CoursePlatformRepository(_db);
    return _db.transaction(() async {
      await upsert(course);
      if (renamedFrom != null) {
        await platformRepo.migrateOnRename(
          course.semesterId,
          from: renamedFrom,
          to: course.name,
        );
      }
      if (platforms != null) {
        await platformRepo.replacePlatforms(
          course.semesterId,
          course.name,
          platforms,
        );
      }
    });
  }

  /// 用 [courses] 原子替换指定学期的全部课程。
  ///
  /// 导入课表时不能逐条 upsert：每次导入都会生成新 id，逐条写入只会把新课
  /// 追加到旧课表中。这里把删除和批量插入放在同一事务内，任何一条写入失败
  /// 都会回滚，避免用户得到一张只写入了一部分的课表。
  Future<void> replaceForSemester(
    String semesterId,
    Iterable<Course> courses,
  ) async {
    final replacements = _validatedBatch(semesterId, courses);

    await _db.transaction(() async {
      await (_db.delete(_db.courses)
            ..where((c) => c.semesterId.equals(semesterId)))
          .go();
      if (replacements.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(
            _db.courses,
            replacements.map((course) => course.toCompanion()).toList(),
          );
        });
      }
    });
  }

  /// 向指定学期批量追加课程（合并导入使用）。
  ///
  /// 与 [replaceForSemester] 不同：不删除现有课程，仅追加。id 必填且唯一，
  /// 校验失败抛 [ArgumentError] 且不写入任何数据。
  Future<void> addCourses(String semesterId, Iterable<Course> courses) async {
    final additions = _validatedBatch(semesterId, courses);
    if (additions.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAll(
        _db.courses,
        additions.map((course) => course.toCompanion()).toList(),
      );
    });
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.courses)..where((c) => c.id.equals(id))).go();
  }

  /// 批量写入前的统一校验：学期 id 非空、每门课程 id 非空且唯一、
  /// 全部属于 [semesterId]。校验失败抛 [ArgumentError]，不写入任何数据。
  List<Course> _validatedBatch(String semesterId, Iterable<Course> courses) {
    if (semesterId.isEmpty) {
      throw ArgumentError.value(semesterId, 'semesterId', 'must not be empty');
    }
    final list = courses.toList(growable: false);
    final ids = <String>{};
    for (final course in list) {
      if (course.id.isEmpty) {
        throw ArgumentError('Course.id must not be empty');
      }
      if (course.semesterId != semesterId) {
        throw ArgumentError(
          'Course ${course.id} belongs to semester ${course.semesterId}, '
          'not $semesterId',
        );
      }
      if (!ids.add(course.id)) {
        throw ArgumentError('Duplicate course id: ${course.id}');
      }
    }
    return list;
  }
}
