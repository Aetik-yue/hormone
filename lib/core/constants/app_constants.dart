/// 应用级常量与默认节次时间表（示例，可按学校自定义）。
class AppConstants {
  static const appName = 'hormone';

  /// 课程卡片默认主题色（应用主蓝，ARGB）。
  static const int defaultCourseColor = 0xFF5B8DEF;

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

  /// 课程卡片可选配色（柔和马卡龙色系，彼此可区分且深浅主题协调）。
  /// 编辑页色板、导入自动配色、ICS 解析配色共用这一份，保证全 App 一致。
  static const List<int> coursePalette = [
    0xFF5B8DEF,
    0xFF3FBFA8,
    0xFFF2A25C,
    0xFF9B8AFB,
    0xFFEF6E8D,
    0xFF4FA3E3,
    0xFFE8BE50,
    0xFF63C98D,
    0xFFC08CE8,
    0xFFF08C7C,
  ];

  /// 按序取色：导入课表时给相邻课程分配不同的柔和色。
  static int courseAutoColor(int index) =>
      coursePalette[index % coursePalette.length];
}
