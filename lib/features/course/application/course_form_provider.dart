import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/data/repositories/course_repository.dart';

/// 解析课程编辑页的初始数据：
/// - 给定 [courseId] 且存在 → 返回该课程（编辑）
/// - 否则 → 返回属于当前激活学期的空白课程，周次默认填满整学期
final courseInitialProvider =
    FutureProvider.family<Course, String?>((ref, courseId) async {
  final courseRepo = ref.watch(courseRepositoryProvider);
  final semesterRepo = ref.watch(semesterRepositoryProvider);

  if (courseId != null && courseId.isNotEmpty) {
    final existing = await courseRepo.getCourse(courseId);
    if (existing != null) return existing;
    // Course not found for the given ID — could be deleted or invalid.
    // Throw so the UI can show an error instead of silently creating a blank course.
    throw StateError('课程不存在：$courseId');
  }

  final semester = await semesterRepo.getActiveSemester();
  final totalWeeks = semester?.totalWeeks ?? 18;
  return Course(
    id: '',
    semesterId: semester?.id ?? '',
    name: '',
    dayOfWeek: 1,
    startSection: 1,
    endSection: 2,
    weeks: List.generate(totalWeeks, (i) => i + 1),
    colorValue: 0xFF5B8DEF,
  );
});

/// 课程表单状态机。所有字段修改都通过 copyWith 生成新状态，UI 直接 watch。
final courseFormProvider =
    StateNotifierProvider.autoDispose<CourseFormNotifier, Course>(
  (ref) => CourseFormNotifier(ref.watch(courseRepositoryProvider)),
);

class CourseFormNotifier extends StateNotifier<Course> {
  final CourseRepository _repo;
  CourseFormNotifier(this._repo)
      : super(const Course(
          id: '',
          semesterId: '',
          name: '',
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          weeks: [],
          colorValue: 0xFF5B8DEF,
        ));

  bool _initialized = false;

  /// 用解析出的初始课程填充表单（仅一次，避免覆盖用户已输入内容）。
  void init(Course initial) {
    if (_initialized) return;
    _initialized = true;
    state = initial;
  }

  void setName(String v) => state = state.copyWith(name: v);

  void setTeacher(String v) =>
      state = state.copyWith(teacher: v.isEmpty ? null : v);

  void setLocation(String v) =>
      state = state.copyWith(location: v.isEmpty ? null : v);

  void setDayOfWeek(int d) => state = state.copyWith(dayOfWeek: d);

  void setStartSection(int s) {
    final end = state.endSection < s ? s : state.endSection;
    state = state.copyWith(startSection: s, endSection: end);
  }

  void setEndSection(int e) {
    final start = state.startSection > e ? e : state.startSection;
    state = state.copyWith(startSection: start, endSection: e);
  }

  void toggleWeek(int w, {int maxWeek = 30}) {
    if (w < 1 || w > maxWeek) return;
    final set = {...state.weeks};
    if (set.contains(w)) {
      set.remove(w);
    } else {
      set.add(w);
    }
    state = state.copyWith(weeks: set.toList()..sort());
  }

  void setAllWeeks(List<int> all) =>
      state = state.copyWith(weeks: [...all]..sort());

  void clearWeeks() => state = state.copyWith(weeks: const []);

  void setColor(int v) => state = state.copyWith(colorValue: v);

  void setNotes(String v) =>
      state = state.copyWith(notes: v.isEmpty ? null : v);

  /// 保存：新增时生成 id，编辑时沿用。返回是否成功。
  Future<bool> save() async {
    if (state.semesterId.isEmpty) return false;
    final toSave =
        state.copyWith(id: state.id.isEmpty ? const Uuid().v4() : state.id);
    try {
      await _repo.upsert(toSave);
      return true;
    } catch (e) {
      return false;
    }
  }
}
