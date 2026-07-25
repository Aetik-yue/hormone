import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hormone/core/utils/week_calculator.dart';
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/data/repositories/semester_repository.dart';

/// 当前展示周（1-based）。首屏根据激活学期开学日期自动定位到「本周」，
/// 用户手动切换后不再被自动覆盖，符合课表使用直觉。
final selectedWeekProvider =
    StateNotifierProvider<SelectedWeekNotifier, int>((ref) {
  final repo = ref.watch(semesterRepositoryProvider);
  return SelectedWeekNotifier(repo);
});

class SelectedWeekNotifier extends StateNotifier<int> {
  final SemesterRepository _repo;
  bool _userChanged = false;

  SelectedWeekNotifier(this._repo) : super(1) {
    _init();
  }

  Future<void> _init() async {
    final semester = await _repo.getActiveSemester();
    if (semester == null) return;
    // 优先使用手动覆盖的当前周（调课/假期），否则按开学日期推算。
    final computed = semester.currentWeekOverride ??
        computeCurrentWeek(semester.startDate, DateTime.now());
    final capped = computed < 1
        ? 1
        : (computed > semester.totalWeeks ? semester.totalWeeks : computed);
    if (!_userChanged) state = capped;
  }

  /// 手动跳转到指定周（用户操作或小组件深链）。
  void goTo(int week) {
    _userChanged = true;
    state = week;
  }

  void nextWeek(int totalWeeks) => goTo(state < totalWeeks ? state + 1 : state);

  void prevWeek() => goTo(state > 1 ? state - 1 : state);
}
