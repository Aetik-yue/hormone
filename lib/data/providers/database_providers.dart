import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hormone/data/app_database.dart';
import 'package:hormone/data/repositories/course_repository.dart';
import 'package:hormone/data/repositories/semester_repository.dart';

/// 进程级单例数据库。懒加载，首次访问时打开 SQLite 文件。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  return CourseRepository(ref.watch(appDatabaseProvider));
});

final semesterRepositoryProvider = Provider<SemesterRepository>((ref) {
  return SemesterRepository(ref.watch(appDatabaseProvider));
});
