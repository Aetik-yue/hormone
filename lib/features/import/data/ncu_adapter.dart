import 'school_extraction_runtime.dart';
import 'generic_adapter.dart';
import 'school_adapter.dart';

/// 南昌大学本科教学综合管理服务平台专用适配器。
///
/// 当前入口：jwpt.ncu.edu.cn/jsxsd/sso.jsp（南昌大学门户统一认证）
/// 教务系统：jwpt.ncu.edu.cn/jsxsd/（强智 QZSoft）
///
/// 提取流程（一次注入）：
/// 1. 在旧系统域名下读取登录态课表接口，兼容过渡期账号
/// 2. 解析新旧课表页 DOM，并使用通用逻辑处理 data 属性/rowspan 表格
/// 3. 均失败时点击课表菜单，返回 {"__nav": true} 由 Dart 侧重试
class NcuAdapter extends SchoolAdapter {
  @override
  String get schoolName => '南昌大学';

  @override
  String get pinyin => 'nanchangdaxue';

  @override
  String get loginUrl => 'https://jwpt.ncu.edu.cn/jsxsd/sso.jsp';

  @override
  bool isSchedulePage(String currentUrl) {
    final url = currentUrl.toLowerCase();
    return url.contains('xskbcx') ||
        url.contains('wdkb') ||
        url.contains('schedule') ||
        url.contains('student-timetable');
  }

  @override
  String get extractJs =>
      r'''
(function() {
''' + schoolExtractionRuntimeJs + r'''
  var results = [];
  var seen = {};

  function addResult(name, teacher, location, day, secs, weeks) {

    name = name.replace(/\(\d{4}[^)]*\)\s*$/, '').trim();



    var key = name + '|' + day + '|' + secs[0] + '|' +
        secs[secs.length - 1] + '|' + weeks.join(',');
    schoolPushCourse(results, seen, key, name, teacher, location, day, secs, weeks);
  }

  // ═══ 策略1：同步 XHR 直调课表数据接口 ═══
  function tryApi() {
    var xnm = '', xqm = '';
    var selXnm = document.querySelector('#xnm') ||
                 document.querySelector('select[name="xnm"]');
    var selXqm = document.querySelector('#xqm') ||
                 document.querySelector('select[name="xqm"]');
    if (selXnm && selXnm.value) xnm = selXnm.value;
    if (selXqm && selXqm.value) xqm = selXqm.value;
    var termCandidates = [];
    if (!xnm || !xqm) {
      // 兜底：9月起属于当年秋季学期，1—8月属于上一学年。
      // 强智部署的学期编码存在 3/12 和 1/2 两类，依次尝试。
      var now = new Date();
      var m = now.getMonth() + 1;
      var y = now.getFullYear();
      xnm = String(m >= 9 ? y : y - 1);
      termCandidates = (m >= 2 && m <= 8)
          ? ['3', '12', '2', '1']
          : ['12', '3', '1', '2'];
    } else {
      termCandidates = [xqm];
    }
    var urls = [
      '/jsxsd/kbcx/xskbcx_cxXsKb.html?gnmkdm=N2151',
      '/jsxsd/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151'
    ];
    for (var u = 0; u < urls.length; u++) {
      for (var tc = 0; tc < termCandidates.length; tc++) {
        try {
          var xhr = new XMLHttpRequest();
          xhr.open('POST', urls[u], false);
          xhr.setRequestHeader('Content-Type',
              'application/x-www-form-urlencoded; charset=UTF-8');
          xhr.send('xnm=' + encodeURIComponent(xnm) + '&xqm=' +
                   encodeURIComponent(termCandidates[tc]));
          if (xhr.status !== 200) continue;
          var data = JSON.parse(xhr.responseText);
          var list = data.kbList || data.items || data.rows ||
              (data.datas && (data.datas.kbList || data.datas.items ||
               data.datas.rows)) || (Array.isArray(data) ? data : []);
          if (!list || list.length === 0) continue;
          for (var i = 0; i < list.length; i++) {
            var it = list[i];
            if (!it || typeof it !== 'object') { results.push(null); continue; }
            var day = schoolInteger(it.xqj || it.dayOfWeek || it.weekDay);
            if (isNaN(day) && (it.xqjmc || it.weekDayName)) {
              var dm = String(it.xqjmc || it.weekDayName)
                  .match(/周([一二三四五六日天])|星期([一二三四五六日天])/);
              if (dm) day = schoolDayMap[dm[1] || dm[2]];
            }
            var secs = schoolParseSections(String(
                it.jcs || it.jc || it.sections || ''));
            var weeks = schoolParseWeeks(String(
                it.zcd || it.zc || it.weeks || it.weekDescription || ''));
            addResult(
              String(it.kcmc || it.courseName || it.name || ''),
              it.xm || it.jsxm || it.teacherName || it.teacher || null,
              it.cdmc || it.jxcd || it.classroomName || it.location || null,
              day, secs, weeks
            );
          }
          if (results.length > 0) return true;
        } catch (e) {}
      }
    }
    return false;
  }

  // ═══ 策略2：DOM 文本解析（强智/老正方课表单元格格式）═══
  function parseDoc(doc) {
    var tds = doc.querySelectorAll ? doc.querySelectorAll('td, .kbtd, .kb-td, [class*="kbtd"]') : [];
    for (var i = 0; i < tds.length; i++) {
      var text = (tds[i].innerText || tds[i].textContent || '')
          .replace(/\u00a0/g, ' ').trim();
      if (!text || text.length > 800) continue;
      var lines = text.split(/\n/).map(function(l){return l.trim();}).filter(Boolean);
      var modeRe = /周[一二三四五六日天]\s*第\s*\d/;
      for (var j = 0; j < lines.length; j++) {
        var line = lines[j];
        var day = 0, secs = null, weeks = null;
        var m1 = line.match(/周([一二三四五六日天])\s*第\s*([\d,，、\s\-–~]+?)\s*节\s*\{第\s*([^}]+)\}/);
        if (m1) {
          day = schoolDayMap[m1[1]];
          secs = schoolParseSections(m1[2]);
          weeks = schoolParseWeeks(m1[3]);
        } else {
          var m2 = line.match(/^([\d,，、\-–~\s]+?)\s*周\s*周([一二三四五六日天])\s*第\s*([\d,，、\s\-–~]+?)\s*节/);
          if (m2) {
            day = schoolDayMap[m2[2]];
            secs = schoolParseSections(m2[3]);
            weeks = schoolParseWeeks(m2[1] + '周');
          }
        }
        if (!day || !secs || secs.length === 0) continue;
        // 课程名：模式行前最近的非模式行；若无则取模式行后的第一行
        var name = '';
        for (var k = j - 1; k >= Math.max(0, j - 2); k--) {
          if (!modeRe.test(lines[k])) { name = lines[k]; break; }
        }
        if (name.length < 2) {
          for (var k2 = j + 1; k2 < Math.min(lines.length, j + 3); k2++) {
            if (!modeRe.test(lines[k2]) && lines[k2].length >= 2) { name = lines[k2]; break; }
          }
        }
        if (name.length < 2) continue;
        // 教师：模式行前最近的第二个非模式行
        var teacher = null;
        for (var k3 = j - 1; k3 >= Math.max(0, j - 3); k3--) {
          if (modeRe.test(lines[k3])) break;
          if (lines[k3] !== name && lines[k3].length >= 2) { teacher = lines[k3]; break; }
        }
        // 教室：模式行后最近的第一个非模式行
        var location = null;
        for (var k4 = j + 1; k4 < Math.min(lines.length, j + 3); k4++) {
          if (modeRe.test(lines[k4])) break;
          if (lines[k4] !== name && lines[k4].length >= 1 && lines[k4].length <= 40) { location = lines[k4]; break; }
        }
        addResult(name, teacher, location, day, secs, weeks);
      }
    }
  }

  // ═══ 汇总主文档与所有同源 frame ═══
  var docs = schoolCollectDocuments();

  // 1. 旧强智系统接口直连；新平台不发送无意义的旧接口请求。
  var legacyLocation = !window.location ||
      /jwpt\.ncu\.edu\.cn|\/jsxsd\//i.test(
          (window.location.hostname || '') + (window.location.pathname || ''));
  if (legacyLocation && tryApi()) return JSON.stringify(results);

  // 2. DOM 解析
  for (var i = 0; i < docs.length; i++) {
    parseDoc(docs[i]);
    if (results.length > 0) return JSON.stringify(results);
  }

  // 3. 新平台及其他表格形态使用通用 data 属性/rowspan 解析器兜底。
  var genericResult = '[]';
  try {
    genericResult = ''' +
      GenericAdapter.commonExtractJs +
      r''';
    var genericCourses = JSON.parse(genericResult);
    if (Array.isArray(genericCourses) && genericCourses.length > 0) {
      return genericResult;
    }
  } catch (e) {}

  // 4. 课表容器存在但暂无课程（加载中 / 本学期无课）→ 等待重试
  if (schoolAnyDoc(docs, function(doc) {
    return doc.querySelector && doc.querySelector('#kbTable, .kb-table, #table1, table.kbTable, .el-table__body');
  })) return JSON.stringify({ __pending: true });

  // 5. 找到课表菜单链接 → 模拟点击
  var nav = schoolClickEntry(docs,
      'a, [role="menuitem"], .menu-item, .el-menu-item', function(link) {
    var t = ((link.textContent || '') + ' ' +
        ((link.getAttribute && link.getAttribute('title')) || '')).trim();
    var href = (link.getAttribute && link.getAttribute('href')) ||
        link.href || '';
    return /个人课表|我的课表|学生课表|课程表/.test(t) ||
        /xskbcx|kbcx|wdkb|schedule|timetable/i.test(href);
  });
  if (nav) return nav;

  return JSON.stringify([]);
})();
''';
}
