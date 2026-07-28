import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/models/semester.dart';
import 'package:hormone/data/providers/database_providers.dart';

/// 当前激活学期（首次启动会自动播种默认学期）。
final activeSemesterProvider = FutureProvider<Semester?>((ref) async {
  final repo = ref.watch(semesterRepositoryProvider);
  return repo.getActiveSemester();
});

/// 全部学期列表（学期管理页使用）。
/// 激活学期置顶，其余按开学日期倒序排列。
final semestersProvider = FutureProvider<List<Semester>>((ref) async {
  final repo = ref.watch(semesterRepositoryProvider);
  final semesters = await repo.getSemesters();
  // 等待激活学期加载完成，确保首次排序正确
  final active = await ref.watch(activeSemesterProvider.future);
  semesters.sort((a, b) {
    // 激活学期置顶
    if (a.id == active?.id) return -1;
    if (b.id == active?.id) return 1;
    // 其余按开学日期倒序（最新的在上面）
    return b.startDate.compareTo(a.startDate);
  });
  return semesters;
});

/// 激活学期下的全部课程流（课程表主视图使用）。
final scheduleCoursesProvider =
    StreamProvider<List<Course>>((ref) {
  final repo = ref.watch(courseRepositoryProvider);
  final active = ref.watch(activeSemesterProvider).value;
  if (active == null) return const Stream.empty();
  return repo.watchCourses(active.id);
});
