import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/utils/week_calculator.dart';
import 'package:hormone/data/providers/database_providers.dart';

/// Android 桌面小组件的 Dart 桥接层。
///
/// 负责三件事：
/// 1. 初始化 home_widget 与 Android SharedPreferences 的通信通道。
/// 2. 把「今日课程」序列化为原生侧可读取的键值对并触发 UI 刷新。
/// 3. 处理小组件点击（默认仅拉起 App；如需深链可在原生侧回传 URI 后扩展）。
///
/// 原生侧模板见仓库 `native_templates/`，整合步骤见 `WIDGET_SETUP.md`。
class WidgetService {
  static const _androidWidgetName = 'CourseWidgetProvider';
  static const _keyCourses = 'courses';
  static const _keyTitle = 'widget_title';

  final Ref _ref;
  bool _initialized = false;

  /// 防抖定时器：课表数据变更时会连发多次流事件，合并为一次刷新。
  Timer? _debounce;

  WidgetService(this._ref);

  /// 幂等初始化并注册小组件点击回调。
  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    // 冷启动时若由小组件拉起，initiallyLaunchedFromHomeWidget 是 Future；运行期点击则是 Stream。
    HomeWidget.initiallyLaunchedFromHomeWidget()
        .then(_onWidgetClicked)
        .catchError((_) {});
    HomeWidget.widgetClicked.listen(_onWidgetClicked);
  }

  /// 课表/节次/当前周变化后集中触发的刷新入口。
  ///
  /// 用短防抖合并一条打印链路上连续发射的多次流事件（切换学期、批量导入、
  /// 恢复备份都会同时波及多个 provider），避免对原生小组件反复写数据。
  void scheduleUpdate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      updateTodayWidget();
    });
  }

  /// 计算并写入「今日课程」到原生小组件，然后刷新 UI。
  ///
  /// 失败时不抛出（小组件是加分项，不应影响主流程）。
  Future<void> updateTodayWidget() async {
    await _ensureInit();
    try {
      final semesterRepo = _ref.read(semesterRepositoryProvider);
      final semester = await semesterRepo.getActiveSemester();
      if (semester == null) return;

      final courseRepo = _ref.read(courseRepositoryProvider);
      final all = await courseRepo.getCourses(semester.id);

      final now = DateTime.now();
      final currentWeek = semester.currentWeekOverride ??
          computeCurrentWeek(semester.startDate, now);
      final todayWeekday = now.weekday;

      final todayCourses = all
          .where((c) =>
              c.dayOfWeek == todayWeekday && c.weeks.contains(currentWeek))
          .toList()
        ..sort((a, b) => a.startSection.compareTo(b.startSection));

      final items = todayCourses
          .map((c) => {
                'name': c.name,
                'time': _timeRange(c),
                'location': c.location ?? '',
                'color': c.colorValue,
              })
          .toList();

      final title = currentWeek >= 1 ? '今天 · 第$currentWeek周' : '今天';

      await HomeWidget.saveWidgetData(_keyTitle, title);
      await HomeWidget.saveWidgetData(_keyCourses, jsonEncode(items));
      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
      );
    } catch (_) {
      // 忽略：小组件刷新失败不影响主 App。
    }
  }

  void _onWidgetClicked(Uri? uri) {
    // MVP：点击小组件仅拉起 App。如需深链（如跳到某周），可在原生侧
    // 通过 HomeWidget.updateWidget 回传 URI 后在此处理。
  }

  String _timeRange(Course c) {
    if (c.startTime != null && c.endTime != null) {
      return '${c.startTime}-${c.endTime}';
    }
    return '第${c.startSection}-${c.endSection}节';
  }
}

/// 全局单例 Provider，供任意位置（如导入完成后）触发小组件刷新。
final widgetServiceProvider = Provider<WidgetService>((ref) {
  return WidgetService(ref);
});
