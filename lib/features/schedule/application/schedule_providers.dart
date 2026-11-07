import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:recess/core/utils/week_calculator.dart';
import 'package:recess/data/providers/database_providers.dart';
import 'package:recess/data/repositories/semester_repository.dart';

/// 查看周（1-based）。首屏及切换当前学期后定位到当前周，
/// 同一学期内保留用户手动选择的周。
final selectedWeekProvider =
    StateNotifierProvider<SelectedWeekNotifier, int>((ref) {
  final repo = ref.watch(semesterRepositoryProvider);
  return SelectedWeekNotifier(repo);
});

class SelectedWeekNotifier extends StateNotifier<int> {
  final SemesterRepository _repo;
  final DateTime Function() _now;
  bool _userChanged = false;

  SelectedWeekNotifier(this._repo, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(1) {
    _init();
  }

  Future<void> _init() async {
    try {
      final semester = await _repo.getActiveSemester();
      if (!mounted || semester == null) return;
      // 优先使用手动覆盖的当前周（调课/假期），否则按开学日期推算。
      final computed = currentWeekOf(semester, _now());
      final capped = clampWeek(computed, semester.totalWeeks);
      if (!_userChanged) state = capped;
    } catch (_) {
      // 数据库异常时保持默认第 1 周，避免首屏崩溃。
    }
  }

  /// 手动跳转到指定周（用户操作或小组件深链）。
  /// 周次会被钳制到 [1, totalWeeks] 范围内。
  void goTo(int week, {int totalWeeks = 999}) {
    _userChanged = true;
    state = clampWeek(week, totalWeeks);
  }
}
