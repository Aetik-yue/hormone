/// 应用级常量与默认节次时间表（示例，可按学校自定义）。
class AppConstants {
  static const appName = 'recess';

  /// 课程默认色（冷暖平衡色板的蓝色，ARGB）。
  static const int defaultCourseColor = 0xFF4399F1;

  /// 一周七天的单字标签（一…日），`dayOfWeek` 1=周一 … 7=周日。
  /// 带“周”的写法由它派生：`'周${AppConstants.weekdayLabels[i]}'`。
  static const List<String> weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

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

  /// 一天最多支持 16 节；13-16 节默认不预设时间，可在设置中按学校作息填写。
  static const int maxSections = 16;

  /// 默认每节课时长（分钟）。
  static const int defaultSectionDuration = 45;

  /// 冷暖平衡、20% 柔化后的浅色色板，也是持久化的颜色标识。
  /// 编辑页色板、导入自动配色、ICS 解析配色共用这一份，保证全 App 一致。
  static const List<int> coursePalette = [
    0xFF4399F1,
    0xFF4BA89A,
    0xFFE3753F,
    0xFF7C83E7,
    0xFFE36679,
    0xFF46A4C1,
    0xFFB28C6D,
    0xFF53A88D,
  ];

  static const List<int> _courseDarkPalette = [
    0xFF217BD1,
    0xFF298B7E,
    0xFFC3581D,
    0xFF6266C7,
    0xFFC2485D,
    0xFF2287A3,
    0xFF947052,
    0xFF348B72,
  ];

  static const List<int> _legacyCoursePalette = [
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

  /// 新旧色板共用的索引；旧十色仅在显示时按原索引循环映射到八色。
  /// 自定义颜色返回 null，不更改数据库或备份里的原始值。
  static int? coursePaletteIndex(int value) {
    final index = coursePalette.indexOf(value);
    if (index >= 0) return index;
    final legacyIndex = _legacyCoursePalette.indexOf(value);
    return legacyIndex < 0 ? null : legacyIndex % coursePalette.length;
  }

  /// 解析主题下的最终显示色；冻结色值不再二次柔化，自定义颜色原样返回。
  static int courseDisplayColor(int value, {bool dark = false}) {
    final index = coursePaletteIndex(value);
    if (index == null) return value;
    return (dark ? _courseDarkPalette : coursePalette)[index];
  }

  /// 按序取色：导入课表时给相邻课程分配不同的柔和色。
  static int courseAutoColor(int index) =>
      coursePalette[index % coursePalette.length];
}
