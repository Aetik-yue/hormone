import 'generic_adapter.dart';
import 'school_adapter.dart';

/// 国内高校常见教务产品类型。
enum AcademicSystemType {
  zhengfang,
  qiangzhi,
  urp,
  kingosoft,
  wisedu,
  southSoft,
  generic,
}

/// 由学校入口和教务产品类型驱动的适配器。
///
/// 此类用于同一商业教务产品的多校复用。新版正方系统优先读取其登录态
/// JSON 课表接口，其余系统使用能够处理表格、rowspan/colspan 和常见
/// data 属性的通用 DOM 抽取器。
class ConfiguredSchoolAdapter extends SchoolAdapter {
  @override
  final String schoolName;

  @override
  final String loginUrl;

  final AcademicSystemType system;
  final String? _scheduleUrl;
  final List<String> scheduleMarkers;

  const ConfiguredSchoolAdapter({
    required this.schoolName,
    required this.loginUrl,
    required this.system,
    String? scheduleUrl,
    this.scheduleMarkers = const [],
  }) : _scheduleUrl = scheduleUrl;

  @override
  String get scheduleUrl => _scheduleUrl ?? loginUrl;

  @override
  bool isSchedulePage(String currentUrl) {
    return scheduleMarkers.any(currentUrl.contains);
  }

  @override
  AdapterSupportLevel get supportLevel => system == AcademicSystemType.generic
      ? AdapterSupportLevel.generic
      : AdapterSupportLevel.systemCompatible;

  @override
  String get systemName => switch (system) {
        AcademicSystemType.zhengfang => '正方教务',
        AcademicSystemType.qiangzhi => '强智教务',
        AcademicSystemType.urp => 'URP 教务',
        AcademicSystemType.kingosoft => '青果/金智教务',
        AcademicSystemType.wisedu => '金智智慧校园',
        AcademicSystemType.southSoft => '南软教务',
        AcademicSystemType.generic => '通用抓取',
      };

  @override
  String get extractJs => system == AcademicSystemType.zhengfang
      ? _zhengfangExtractor
      : GenericAdapter.commonExtractJs;

  /// 新版正方 `jwglxt` 的学生个人课表接口抽取器。
  ///
  /// 接口调用与页面同源并沿用 WebView 登录态；接口不可用时自动回退到
  /// 通用 DOM 抽取器。
  String get _zhengfangExtractor =>
      r'''
(function() {
  var results = [];
  var seen = {};

  function range(text) {
    var values = [];
    var raw = String(text || '');
    var odd = /单|奇/.test(raw);
    var even = /双|偶/.test(raw);
    raw.replace(/第|周|节/g, '').split(/[,，、\s]+/)
      .forEach(function(part) {
        var match = part.match(/(\d+)\s*[-–~]\s*(\d+)/);
        if (match) {
          for (var n = parseInt(match[1]); n <= parseInt(match[2]); n++) {
            values.push(n);
          }
        } else {
          var value = parseInt(part);
          if (!isNaN(value)) values.push(value);
        }
      });
    return values.filter(function(value, index, all) {
      if (all.indexOf(value) !== index) return false;
      if (odd) return value % 2 === 1;
      if (even) return value % 2 === 0;
      return true;
    }).sort(function(a, b) { return a - b; });
  }

  function add(item) {
    var name = String(item.kcmc || item.courseName || '').trim();
    var day = parseInt(item.xqj || item.dayOfWeek || item.weekDay);
    var sections = range(item.jcs || item.jc || item.sections || '');
    var weeks = range(item.zcd || item.weeks || item.weekDescription || '');
    if (!name || day < 1 || day > 7 || sections.length === 0) return;
    var key = name + '|' + day + '|' + sections.join(',') + '|' + weeks.join(',');
    if (seen[key]) return;
    seen[key] = true;
    results.push({
      name: name,
      teacher: item.xm || item.jsxm || item.teacherName || null,
      location: item.cdmc || item.jxcd || item.classroomName || null,
      dayOfWeek: day,
      startSection: sections[0],
      endSection: sections[sections.length - 1],
      weeks: weeks
    });
  }

  try {
    var yearSelect = document.querySelector('#xnm, select[name="xnm"]');
    var termSelect = document.querySelector('#xqm, select[name="xqm"]');
    var now = new Date();
    var month = now.getMonth() + 1;
    var year = yearSelect && yearSelect.value
      ? yearSelect.value
      : String(month >= 9 ? now.getFullYear() : now.getFullYear() - 1);
    var term = termSelect && termSelect.value
      ? termSelect.value
      : (month >= 2 && month <= 8 ? '12' : '3');
    var pathname = window.location.pathname || '/';
    var marker = pathname.indexOf('/jwglxt/');
    var root = marker >= 0 ? pathname.substring(0, marker) + '/jwglxt' : '/jwglxt';
    var endpoints = [
      root + '/kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N253508',
      root + '/kbcx/xskbcx_cxXsKb.html?gnmkdm=N2151'
    ];
    for (var i = 0; i < endpoints.length && results.length === 0; i++) {
      try {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', endpoints[i], false);
        xhr.setRequestHeader('Content-Type',
          'application/x-www-form-urlencoded; charset=UTF-8');
        xhr.send('xnm=' + encodeURIComponent(year) + '&xqm=' + encodeURIComponent(term));
        if (xhr.status !== 200) continue;
        var payload = JSON.parse(xhr.responseText);
        var list = payload.kbList || payload.items || payload.rows || [];
        for (var j = 0; j < list.length; j++) add(list[j]);
      } catch (_) {}
    }
  } catch (_) {}

  if (results.length > 0) return JSON.stringify(results);
  return ''' +
      GenericAdapter.commonExtractJs +
      r''';
})()
''';
}
