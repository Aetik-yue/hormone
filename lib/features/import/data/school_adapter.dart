import 'cqu_adapter.dart';
import 'configured_school_adapter.dart';
import 'generic_adapter.dart';
import 'jufe_adapter.dart';
import 'ncu_adapter.dart';
import 'syuct_adapter.dart';

/// 教务导入规则的验证级别。
enum AdapterSupportLevel {
  /// 已针对该校页面结构编写并回归测试专用规则。
  schoolVerified,

  /// 按该校使用的教务产品类型复用兼容规则，仍需学校账号做最终实机验证。
  systemCompatible,

  /// 仅提供学校入口并使用通用 DOM 抓取器。
  generic,
}

/// 学校教务系统适配器：定义登录页、课表页 URL 及 JS 提取脚本。
///
/// 每所学校实现一个适配器，WebView 导入流程通过适配器驱动：
/// 1. 打开 [loginUrl] 让用户登录
/// 2. 检测登录成功后跳转 [scheduleUrl]
/// 3. 页面加载完成后注入 [extractJs] 提取课程 JSON
/// 4. 解析 JSON 为 [ExtractedCourse] 列表
abstract class SchoolAdapter {
  const SchoolAdapter();

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

  /// 适配方式，用于向用户准确说明当前规则的可靠程度。
  AdapterSupportLevel get supportLevel => AdapterSupportLevel.schoolVerified;

  /// 教务系统产品或抓取策略名称。
  String get systemName => '专用适配';

  /// 是否为内置适配器（非用户自定义）。
  bool get isBuiltin => true;
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
    final dayOfWeek = json['dayOfWeek'] as int? ?? 1;
    final startSection = json['startSection'] as int? ?? 1;
    final endSection = json['endSection'] as int? ?? 1;
    assert(
        dayOfWeek >= 1 && dayOfWeek <= 7, 'dayOfWeek out of range: $dayOfWeek');
    assert(startSection >= 1 && startSection <= 20,
        'startSection out of range: $startSection');
    assert(endSection >= startSection,
        'endSection ($endSection) < startSection ($startSection)');
    return ExtractedCourse(
      name: json['name'] as String? ?? '',
      teacher: json['teacher'] as String?,
      location: json['location'] as String?,
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      weeks: (json['weeks'] as List<dynamic>?)?.map((e) => e as int).toList() ??
          [],
    );
  }
}

/// 原“985 工程”39 所高校目录。
///
/// “985”不再作为现行建设项目使用，但仍是用户最常用的学校集合称呼。
/// 重庆大学使用专用适配器，其余学校按公开可确认的教务系统产品类型
/// 复用系统兼容规则；无法确认产品类型的学校使用通用抓取器。
final List<SchoolAdapter> eliteUniversityAdapters = List.unmodifiable([
  CquAdapter(),
  const ConfiguredSchoolAdapter(
    schoolName: '北京大学',
    loginUrl: 'https://elective.pku.edu.cn/',
    system: AcademicSystemType.urp,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '清华大学',
    loginUrl: 'http://zhjw.cic.tsinghua.edu.cn/',
    system: AcademicSystemType.urp,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '中国人民大学',
    loginUrl: 'https://jw.ruc.edu.cn/Njw2017/login.html',
    system: AcademicSystemType.wisedu,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '北京航空航天大学',
    loginUrl: 'http://bhjwc.buaa.edu.cn/',
    system: AcademicSystemType.zhengfang,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '北京理工大学',
    loginUrl: 'http://jwms.bit.edu.cn/',
    system: AcademicSystemType.wisedu,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '中国农业大学',
    loginUrl: 'http://newjw.cau.edu.cn/',
    system: AcademicSystemType.qiangzhi,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '北京师范大学',
    loginUrl: 'http://zyfw.prsc.bnu.edu.cn/cas/login.action',
    system: AcademicSystemType.kingosoft,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '中央民族大学',
    loginUrl: 'https://jwxs.muc.edu.cn/login',
    system: AcademicSystemType.urp,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '南开大学',
    loginUrl: 'http://eamis.nankai.edu.cn/',
    system: AcademicSystemType.qiangzhi,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '天津大学',
    loginUrl: 'http://eam.tju.edu.cn/',
    system: AcademicSystemType.urp,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '大连理工大学',
    loginUrl: 'http://teach.dlut.edu.cn/',
    system: AcademicSystemType.qiangzhi,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '东北大学',
    loginUrl: 'https://jwxt.neu.edu.cn/',
    system: AcademicSystemType.generic,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '吉林大学',
    loginUrl: 'http://uims.jlu.edu.cn/',
    system: AcademicSystemType.kingosoft,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '哈尔滨工业大学',
    loginUrl: 'http://jwts.hit.edu.cn/',
    system: AcademicSystemType.kingosoft,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '复旦大学',
    loginUrl: 'http://xk.fudan.edu.cn/',
    system: AcademicSystemType.urp,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '同济大学',
    loginUrl: 'http://1.tongji.edu.cn/',
    system: AcademicSystemType.generic,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '上海交通大学',
    loginUrl: 'http://i.sjtu.edu.cn/',
    system: AcademicSystemType.kingosoft,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '华东师范大学',
    loginUrl: 'http://www.idc.ecnu.edu.cn/',
    system: AcademicSystemType.kingosoft,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '南京大学',
    loginUrl: 'http://jw.nju.edu.cn/',
    system: AcademicSystemType.kingosoft,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '东南大学',
    loginUrl: 'http://ehall.seu.edu.cn/',
    system: AcademicSystemType.urp,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '浙江大学',
    loginUrl: 'https://jwbinfosys.zju.edu.cn/',
    system: AcademicSystemType.zhengfang,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '中国科学技术大学',
    loginUrl: 'https://jw.ustc.edu.cn/',
    system: AcademicSystemType.zhengfang,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '厦门大学',
    loginUrl: 'http://jw.xmu.edu.cn/',
    system: AcademicSystemType.kingosoft,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '山东大学',
    loginUrl: 'http://bkjw.sdu.edu.cn/',
    system: AcademicSystemType.zhengfang,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '中国海洋大学',
    loginUrl: 'https://id.ouc.edu.cn/sso/login',
    system: AcademicSystemType.kingosoft,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '武汉大学',
    loginUrl: 'http://jwgl.whu.edu.cn/',
    system: AcademicSystemType.qiangzhi,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '华中科技大学',
    loginUrl: 'http://hub.hust.edu.cn/',
    system: AcademicSystemType.urp,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '湖南大学',
    loginUrl: 'http://hdjw.hnu.edu.cn/',
    system: AcademicSystemType.southSoft,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '中南大学',
    loginUrl: 'http://csujwc.its.csu.edu.cn/',
    system: AcademicSystemType.zhengfang,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '国防科技大学',
    loginUrl: 'https://www.nudt.edu.cn/',
    system: AcademicSystemType.generic,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '中山大学',
    loginUrl: 'http://uems.sysu.edu.cn/',
    system: AcademicSystemType.zhengfang,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '华南理工大学',
    loginUrl: 'http://xsjw2018.jw.scut.edu.cn/',
    system: AcademicSystemType.zhengfang,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '四川大学',
    loginUrl: 'http://zhjw.scu.edu.cn/index',
    system: AcademicSystemType.urp,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '电子科技大学',
    loginUrl: 'https://eportal.uestc.edu.cn/',
    system: AcademicSystemType.generic,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '西安交通大学',
    loginUrl: 'http://ehall.xjtu.edu.cn/',
    system: AcademicSystemType.qiangzhi,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '西北工业大学',
    loginUrl: 'https://uis.nwpu.edu.cn/',
    system: AcademicSystemType.urp,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '西北农林科技大学',
    loginUrl: 'https://newehall.nwafu.edu.cn/',
    system: AcademicSystemType.wisedu,
  ),
  const ConfiguredSchoolAdapter(
    schoolName: '兰州大学',
    loginUrl: 'http://jwk.lzu.edu.cn/academic/login/lzu/loginIds6Valid.jsp',
    system: AcademicSystemType.urp,
  ),
]);

/// 已有的其他学校专用适配器。
final List<SchoolAdapter> otherSchoolAdapters = List.unmodifiable([
  JufeAdapter(),
  NcuAdapter(),
  SyuctAdapter(),
]);

/// 已注册的学校适配器列表（不可变）。
final List<SchoolAdapter> schoolAdapters = List.unmodifiable([
  ...eliteUniversityAdapters,
  ...otherSchoolAdapters,
]);

/// 创建通用适配器（用户自定义 URL）。
SchoolAdapter createGenericAdapter(String url) =>
    GenericAdapter(url: url.isEmpty ? 'about:blank' : url);
