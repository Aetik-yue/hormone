import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/features/notification/application/reminder_scheduler.dart';
import 'package:hormone/features/notification/application/reminder_settings_provider.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';

/// 课前提醒的原生封装。
///
/// 成功与否都不影响主流程（通知是可选项）：所有初始化与调度都包在
/// try-catch 中静默降级，插件通道在测试环境缺失时也不会抛到上层。
class NotificationService {
  static const _channelId = 'course_reminder';
  static const _channelName = '上课提醒';

  final Ref _ref;
  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;

  NotificationService(this._ref);

  Future<void> _ensureInit() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(_localLocation());
      _plugin = FlutterLocalNotificationsPlugin();
      await _plugin!.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _initialized = true;
    } catch (_) {
      _initialized = false; // 插件不可用时下次重试，避免永久失效。
    }
  }

  /// 尽量解析本机时区；失败回退 UTC（触发时间按绝对时刻调度，不受影响）。
  static tz.Location _localLocation() {
    try {
      return tz.getLocation(DateTime.now().timeZoneName);
    } catch (_) {
      return tz.UTC;
    }
  }

  /// 请求 Android 13+ 的通知运行时权限。返回是否已授权。
  Future<bool> requestPermission() async {
    try {
      await _ensureInit();
      final android = _plugin
          ?.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 取消全部旧提醒，并按当前课表重排。
  ///
  /// 每次重排都 cancelAll + 全量重排：id 无需跨批稳定，也天然清理了
  /// 学期/课表变化后残留的提醒。
  Future<void> reschedule() async {
    try {
      await _ensureInit();
      final settings = _ref.read(reminderSettingsProvider);
      await _plugin!.cancelAll();
      if (!settings.enabled) return;

      final semester =
          await _ref.read(semesterRepositoryProvider).getActiveSemester();
      if (semester == null) return;

      final courses =
          await _ref.read(courseRepositoryProvider).getCourses(semester.id);
      final sectionTimes = _ref.read(sectionTimesProvider);
      final reminders = computeReminders(
        courses: courses,
        semester: semester,
        sectionTimes: sectionTimes,
        now: DateTime.now(),
        leadMinutes: settings.leadMinutes,
      );

      for (final r in reminders) {
        await _plugin!.zonedSchedule(
          r.id,
          r.title,
          r.body,
          tz.TZDateTime.from(r.trigger, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: '在每节课开始前提醒你',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          // 不精确闹钟：无需 SCHEDULE_EXACT_ALARM 特殊权限，Doze 下可能
          // 延迟 1-2 分钟，对课前提醒足够。
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {
      // 通知是可选项，失败静默。
    }
  }
}

/// 全局单例，供根部的 _AppEffects 在数据变化时统一重排。
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref);
});