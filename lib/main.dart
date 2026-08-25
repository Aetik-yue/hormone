import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hormone/app/router.dart';
import 'package:hormone/core/theme/app_theme.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';
import 'package:hormone/features/settings/application/theme_mode_provider.dart';
import 'package:hormone/features/widget/application/widget_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: HormoneApp()));
}

class HormoneApp extends ConsumerWidget {
  const HormoneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'hormone',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 280),
      themeAnimationCurve: Curves.easeOutCubic,
      routerConfig: appRouter,
      // 把副作用（小组件刷新、跨午夜刷新）集中在这一层，避免散落在各页面。
      builder: (context, child) => _AppEffects(child: child!),
    );
  }
}

/// 应用级副作用宿主：监听课表/节次/激活学期变化统一刷新桌面小组件，
/// 并在回到前台或跨过午夜时补刷（解决进程常驻后台时「今日课程」停更的问题）。
class _AppEffects extends ConsumerStatefulWidget {
  final Widget child;
  const _AppEffects({required this.child});

  @override
  ConsumerState<_AppEffects> createState() => _AppEffectsState();
}

class _AppEffectsState extends ConsumerState<_AppEffects>
    with WidgetsBindingObserver {
  Timer? _midnightTimer;
  WidgetService? _service;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台：可能跨越了午夜，立即补刷一次今日课程。
    if (state == AppLifecycleState.resumed) {
      _service?.updateTodayWidget();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 首次访问时取出小组件服务（懒加载，失败静默）。
    _service ??= ref.read(widgetServiceProvider);

    // 任一与「今日课程」相关的数据变化，都触发一次防抖刷新。
    ref.listen(activeSemesterProvider, (_, __) => _service!.scheduleUpdate());
    ref.listen(scheduleCoursesProvider, (_, __) => _service!.scheduleUpdate());
    ref.listen(sectionTimesProvider, (_, __) => _service!.scheduleUpdate());

    return widget.child;
  }

  /// 在下一个午夜安排一次刷新。跨过午夜后今日课程与当前周都会变化。
  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      nextMidnight.difference(now) + const Duration(seconds: 1),
      () {
        _service?.updateTodayWidget();
        _scheduleMidnightRefresh();
      },
    );
  }
}
