/// 应用级常量与默认节次时间表（示例，可按学校自定义）。
class AppConstants {
  static const appName = 'hormone';

  /// 默认节次 -> 开始时间（24h），用于时间轴展示。
  static const Map<int, String> sectionStartTimes = {
    1: '08:00',
    2: '08:55',
    3: '10:00',
    4: '10:55',
    5: '14:00',
    6: '14:55',
    7: '16:00',
    8: '16:55',
    9: '19:00',
    10: '19:55',
    11: '20:50',
    12: '21:45',
  };

  static const int maxSections = 12;

  /// 默认每节课时长（分钟）。
  static const int defaultSectionDuration = 45;
}
