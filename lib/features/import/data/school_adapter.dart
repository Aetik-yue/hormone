import 'cqu_adapter.dart';
import 'configured_school_adapter.dart';
import 'generic_adapter.dart';
import 'jgsu_adapter.dart';
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

/// 学校教务系统适配器：定义登录页 URL 及 JS 提取脚本。
///
/// 每所学校实现一个适配器，WebView 导入流程通过适配器驱动：
/// 1. 打开 [loginUrl] 让用户登录
/// 2. 用 [isSchedulePage] 检测是否已到达课表页
/// 3. 页面加载完成后注入 [extractJs] 提取课程 JSON
/// 4. 解析 JSON 为导入课程列表（校验见 `webview_course_parser.dart`）
abstract class SchoolAdapter {
  const SchoolAdapter();

  /// 学校名称（显示用）。
  String get schoolName;

  /// 校名无声调拼音，用于稳定的字母排序和拼音搜索。
  ///
  /// 目录中的学校显式给出拼音；未提供时回退到小写校名。
  String get pinyin => schoolName.toLowerCase();

  /// 教务系统登录页 URL。
  String get loginUrl;

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

  /// 用本次预览的目标学期展开没有明确范围的单双周。
  String extractForSemester(int totalWeeks) {
    if (totalWeeks < 1) throw ArgumentError.value(totalWeeks, 'totalWeeks');
    return '(function() { var recessTotalWeeks = $totalWeeks; '
        'return ${extractJs.trim()}; })()';
  }

  /// 适配方式，用于向用户准确说明当前规则的可靠程度。
  AdapterSupportLevel get supportLevel => AdapterSupportLevel.schoolVerified;

  /// 教务系统产品或抓取策略名称。
  String get systemName => '专用适配';

  /// 打开教务系统前需要告知用户的访问条件（如校外需连 VPN），无则为 null。
  String? get accessNote => null;
}

/// 内置学校目录：名称、拼音、登录入口与教务产品类型合成一张表。
///
/// 配置型学校直接构造 [ConfiguredSchoolAdapter]；写了专用提取脚本的学校
/// 在表里放它的适配器实例，名称、拼音与登录入口由该适配器自身提供。
final List<SchoolAdapter> _schoolCatalog = List.unmodifiable([
  CquAdapter(),
  const ConfiguredSchoolAdapter(schoolName: '北京大学', pinyin: 'beijingdaxue', loginUrl: 'https://elective.pku.edu.cn/', system: AcademicSystemType.urp),
  const ConfiguredSchoolAdapter(schoolName: '清华大学', pinyin: 'qinghuadaxue', loginUrl: 'http://zhjw.cic.tsinghua.edu.cn/', system: AcademicSystemType.urp),
  const ConfiguredSchoolAdapter(schoolName: '中国人民大学', pinyin: 'zhongguorenmindaxue', loginUrl: 'https://jw.ruc.edu.cn/Njw2017/login.html', system: AcademicSystemType.wisedu),
  const ConfiguredSchoolAdapter(schoolName: '北京航空航天大学', pinyin: 'beijinghangkonghangtiandaxue', loginUrl: 'http://bhjwc.buaa.edu.cn/', system: AcademicSystemType.zhengfang),
  const ConfiguredSchoolAdapter(schoolName: '北京理工大学', pinyin: 'beijingligongdaxue', loginUrl: 'http://jwms.bit.edu.cn/', system: AcademicSystemType.wisedu),
  const ConfiguredSchoolAdapter(schoolName: '中国农业大学', pinyin: 'zhongguonongyedaxue', loginUrl: 'http://newjw.cau.edu.cn/', system: AcademicSystemType.qiangzhi),
  const ConfiguredSchoolAdapter(schoolName: '北京师范大学', pinyin: 'beijingshifandaxue', loginUrl: 'http://zyfw.prsc.bnu.edu.cn/cas/login.action', system: AcademicSystemType.kingosoft),
  const ConfiguredSchoolAdapter(schoolName: '中央民族大学', pinyin: 'zhongyangminzudaxue', loginUrl: 'https://jwxs.muc.edu.cn/login', system: AcademicSystemType.urp),
  const ConfiguredSchoolAdapter(schoolName: '南开大学', pinyin: 'nankaidaxue', loginUrl: 'http://eamis.nankai.edu.cn/', system: AcademicSystemType.qiangzhi),
  const ConfiguredSchoolAdapter(schoolName: '天津大学', pinyin: 'tianjindaxue', loginUrl: 'http://eam.tju.edu.cn/', system: AcademicSystemType.urp),
  const ConfiguredSchoolAdapter(schoolName: '大连理工大学', pinyin: 'dalianligongdaxue', loginUrl: 'http://teach.dlut.edu.cn/', system: AcademicSystemType.qiangzhi),
  const ConfiguredSchoolAdapter(schoolName: '东北大学', pinyin: 'dongbeidaxue', loginUrl: 'https://jwxt.neu.edu.cn/', system: AcademicSystemType.generic),
  const ConfiguredSchoolAdapter(schoolName: '吉林大学', pinyin: 'jilindaxue', loginUrl: 'http://uims.jlu.edu.cn/', system: AcademicSystemType.kingosoft),
  const ConfiguredSchoolAdapter(schoolName: '哈尔滨工业大学', pinyin: 'haerbingongyedaxue', loginUrl: 'http://jwts.hit.edu.cn/', system: AcademicSystemType.kingosoft),
  const ConfiguredSchoolAdapter(schoolName: '复旦大学', pinyin: 'fudandaxue', loginUrl: 'http://xk.fudan.edu.cn/', system: AcademicSystemType.urp),
  const ConfiguredSchoolAdapter(schoolName: '同济大学', pinyin: 'tongjidaxue', loginUrl: 'http://1.tongji.edu.cn/', system: AcademicSystemType.generic),
  const ConfiguredSchoolAdapter(schoolName: '上海交通大学', pinyin: 'shanghaijiaotongdaxue', loginUrl: 'http://i.sjtu.edu.cn/', system: AcademicSystemType.kingosoft),
  const ConfiguredSchoolAdapter(schoolName: '华东师范大学', pinyin: 'huadongshifandaxue', loginUrl: 'http://www.idc.ecnu.edu.cn/', system: AcademicSystemType.kingosoft),
  const ConfiguredSchoolAdapter(schoolName: '南京大学', pinyin: 'nanjingdaxue', loginUrl: 'http://jw.nju.edu.cn/', system: AcademicSystemType.kingosoft),
  const ConfiguredSchoolAdapter(schoolName: '东南大学', pinyin: 'dongnandaxue', loginUrl: 'http://ehall.seu.edu.cn/', system: AcademicSystemType.urp),
  const ConfiguredSchoolAdapter(schoolName: '浙江大学', pinyin: 'zhejiangdaxue', loginUrl: 'https://jwbinfosys.zju.edu.cn/', system: AcademicSystemType.zhengfang),
  const ConfiguredSchoolAdapter(schoolName: '中国科学技术大学', pinyin: 'zhongguokexuejishudaxue', loginUrl: 'https://jw.ustc.edu.cn/', system: AcademicSystemType.zhengfang),
  const ConfiguredSchoolAdapter(schoolName: '厦门大学', pinyin: 'xiamendaxue', loginUrl: 'http://jw.xmu.edu.cn/', system: AcademicSystemType.kingosoft),
  const ConfiguredSchoolAdapter(schoolName: '山东大学', pinyin: 'shandongdaxue', loginUrl: 'http://bkjw.sdu.edu.cn/', system: AcademicSystemType.zhengfang),
  const ConfiguredSchoolAdapter(schoolName: '中国海洋大学', pinyin: 'zhongguohaiyangdaxue', loginUrl: 'https://id.ouc.edu.cn/sso/login', system: AcademicSystemType.kingosoft),
  const ConfiguredSchoolAdapter(schoolName: '武汉大学', pinyin: 'wuhandaxue', loginUrl: 'http://jwgl.whu.edu.cn/', system: AcademicSystemType.qiangzhi),
  const ConfiguredSchoolAdapter(schoolName: '华中科技大学', pinyin: 'huazhongkejidaxue', loginUrl: 'http://hub.hust.edu.cn/', system: AcademicSystemType.urp),
  const ConfiguredSchoolAdapter(schoolName: '湖南大学', pinyin: 'hunandaxue', loginUrl: 'http://hdjw.hnu.edu.cn/', system: AcademicSystemType.southSoft),
  const ConfiguredSchoolAdapter(schoolName: '中南大学', pinyin: 'zhongnandaxue', loginUrl: 'http://csujwc.its.csu.edu.cn/', system: AcademicSystemType.zhengfang),
  const ConfiguredSchoolAdapter(schoolName: '国防科技大学', pinyin: 'guofangkejidaxue', loginUrl: 'https://www.nudt.edu.cn/', system: AcademicSystemType.generic),
  const ConfiguredSchoolAdapter(schoolName: '中山大学', pinyin: 'zhongshandaxue', loginUrl: 'http://uems.sysu.edu.cn/', system: AcademicSystemType.zhengfang),
  const ConfiguredSchoolAdapter(schoolName: '华南理工大学', pinyin: 'huananligongdaxue', loginUrl: 'http://xsjw2018.jw.scut.edu.cn/', system: AcademicSystemType.zhengfang),
  const ConfiguredSchoolAdapter(schoolName: '四川大学', pinyin: 'sichuandaxue', loginUrl: 'http://zhjw.scu.edu.cn/index', system: AcademicSystemType.urp),
  const ConfiguredSchoolAdapter(schoolName: '电子科技大学', pinyin: 'dianzikejidaxue', loginUrl: 'https://eportal.uestc.edu.cn/', system: AcademicSystemType.generic),
  const ConfiguredSchoolAdapter(schoolName: '西安交通大学', pinyin: 'xianjiaotongdaxue', loginUrl: 'http://ehall.xjtu.edu.cn/', system: AcademicSystemType.qiangzhi),
  const ConfiguredSchoolAdapter(schoolName: '西北工业大学', pinyin: 'xibeigongyedaxue', loginUrl: 'https://uis.nwpu.edu.cn/', system: AcademicSystemType.urp),
  const ConfiguredSchoolAdapter(schoolName: '西北农林科技大学', pinyin: 'xibeinonglinkejidaxue', loginUrl: 'https://newehall.nwafu.edu.cn/', system: AcademicSystemType.wisedu),
  const ConfiguredSchoolAdapter(schoolName: '兰州大学', pinyin: 'lanzhoudaxue', loginUrl: 'http://jwk.lzu.edu.cn/academic/login/lzu/loginIds6Valid.jsp', system: AcademicSystemType.urp),
  JgsuAdapter(),
  JufeAdapter(),
  NcuAdapter(),
  SyuctAdapter(),
]);

/// 已注册的学校适配器列表，按校名拼音字母顺序排列且不可变。
final List<SchoolAdapter> schoolAdapters = List.unmodifiable(
  [..._schoolCatalog]..sort((a, b) {
      final byPinyin = a.pinyin.compareTo(b.pinyin);
      return byPinyin != 0 ? byPinyin : a.schoolName.compareTo(b.schoolName);
    }),
);

/// 创建通用适配器（用户自定义 URL）。
SchoolAdapter createGenericAdapter(String url) =>
    GenericAdapter(url: url.isEmpty ? 'about:blank' : url);
