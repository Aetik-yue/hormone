import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hormone/app/router.dart';
import 'package:hormone/core/theme/app_theme.dart';
import 'package:hormone/features/notification/application/notification_service.dart';
import 'package:hormone/features/notification/application/reminder_settings_provider.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';
import 'package:hormone/features/settings/application/theme_mode_provider.dart';
import 'package:hormone/features/update/application/app_update_controller.dart';
import 'package:hormone/features/update/presentation/update_dialog.dart';
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

  /// 通知重排的防抖定时器：课表/设置变化会连发多次事件，合并为一次。
  Timer? _reminderDebounce;
  WidgetService? _service;
  NotificationService? _notificationService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForAppUpdate());
  }

  /// Android 启动后每天最多检查一次；无更新或网络失败时不打扰用户。
  Future<void> _checkForAppUpdate() async {
    if (!Platform.isAndroid) return;
    final release = await ref
        .read(appUpdateControllerProvider.notifier)
        .checkForUpdate(automatic: true);
    if (!mounted || release == null) return;
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null) return;
    await showAppUpdateDialog(navigatorContext, release);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _reminderDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台：可能跨越了午夜，立即补刷一次今日课程。
    if (state == AppLifecycleState.resumed) {
      _service?.updateTodayWidget();
      _scheduleReminderRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 首次访问时取出小组件与通知服务（懒加载，失败静默）。
    _service ??= ref.read(widgetServiceProvider);
    _notificationService ??= ref.read(notificationServiceProvider);

    // 任一与「今日课程 / 提醒」相关的数据变化，都触发一次防抖同步。
    ref.listen(activeSemesterProvider, (_, __) => _onDataChanged());
    ref.listen(scheduleCoursesProvider, (_, __) => _onDataChanged());
    ref.listen(sectionTimesProvider, (_, __) => _onDataChanged());
    ref.listen(reminderSettingsProvider, (_, __) => _onDataChanged());

    return widget.child;
  }

  /// 数据变化后的统一入口：刷新小组件 + 重排课前提醒（各自防抖）。
  void _onDataChanged() {
    _service?.scheduleUpdate();
    _scheduleReminderRefresh();
  }

  void _scheduleReminderRefresh() {
    _reminderDebounce?.cancel();
    _reminderDebounce = Timer(const Duration(milliseconds: 800), () {
      _notificationService?.reschedule();
    });
  }

  /// 在下一个午夜安排一次刷新。跨过午夜后今日课程、当前周与提醒都会变化。
  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      nextMidnight.difference(now) + const Duration(seconds: 1),
      () {
        _service?.updateTodayWidget();
        _scheduleReminderRefresh();
        _scheduleMidnightRefresh();
      },
    );
  }
}
