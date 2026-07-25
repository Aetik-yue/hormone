import 'cqu_adapter.dart';
import 'jufe_adapter.dart';

/// 学校教务系统适配器：定义登录页、课表页 URL 及 JS 提取脚本。
///
/// 每所学校实现一个适配器，WebView 导入流程通过适配器驱动：
/// 1. 打开 [loginUrl] 让用户登录
/// 2. 检测登录成功后跳转 [scheduleUrl]
/// 3. 页面加载完成后注入 [extractJs] 提取课程 JSON
/// 4. 解析 JSON 为 [ExtractedCourse] 列表
abstract class SchoolAdapter {
  /// 学校名称（显示用）。
  String get schoolName;

  /// 教务系统登录页 URL。
  String get loginUrl;

  /// 课程表页面 URL（登录成功后跳转）。
  String get scheduleUrl;

  /// 判断当前 URL 是否已到达课表页（用于自动检测登录成功）。
  bool isSchedulePage(String currentUrl);

  /// 注入课表页的 JavaScript，返回 JSON 字符串。
  ///
  /// 返回格式：
  /// ```json
  /// [
  ///   {
  ///     "name": "高等数学",
  ///     "teacher": "张三",
  ///     "location": "教三-201",
  ///     "dayOfWeek": 1,
  ///     "startSection": 1,
  ///     "endSection": 2,
  ///     "weeks": [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]
  ///   }
  /// ]
  /// ```
  String get extractJs;
}

/// 从教务系统提取的单门课程（中间模型，尚未入库）。
class ExtractedCourse {
  final String name;
  final String? teacher;
  final String? location;
  final int dayOfWeek; // 1-7
  final int startSection;
  final int endSection;
  final List<int> weeks;

  const ExtractedCourse({
    required this.name,
    this.teacher,
    this.location,
    required this.dayOfWeek,
    required this.startSection,
    required this.endSection,
    required this.weeks,
  });

  factory ExtractedCourse.fromJson(Map<String, dynamic> json) {
    return ExtractedCourse(
      name: json['name'] as String? ?? '',
      teacher: json['teacher'] as String?,
      location: json['location'] as String?,
      dayOfWeek: json['dayOfWeek'] as int? ?? 1,
      startSection: json['startSection'] as int? ?? 1,
      endSection: json['endSection'] as int? ?? 1,
      weeks: (json['weeks'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
    );
  }
}

/// 已注册的学校适配器列表。
final List<SchoolAdapter> schoolAdapters = [
  CquAdapter(),
  JufeAdapter(),
];
