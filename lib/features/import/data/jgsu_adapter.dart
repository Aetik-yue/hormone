import 'school_extraction_runtime.dart';
import 'package:recess/features/import/data/school_adapter.dart';

/// 井冈山大学（金智智慧校园 wisedu）适配器。
///
/// 校园信息化为金智生态：
/// - 统一身份认证：authserver.jgsu.edu.cn（CAS 风格登录页）
/// - 一站式办事大厅：ehall.jgsu.edu.cn（ywtb-portal）
/// - 学生服务：xsfw.jgsu.edu.cn（同样挂 authserver 登录）
/// - 新版教务「我的课表」：/jwapp/sys/wdkb/（jwapp 模块）
/// - 旧域名 jw.jgsu.edu.cn 位于深信服 aTrust 零信任网关之后，浏览器登录
///   需要客户端校验，不适合 WebView 导入，因此入口选 ehall。
///
/// 提取流程（一次注入）：
/// 1. 同步 XHR 直调 jwapp 课表接口（登录态下任意同源页面可用，最可靠）。
///    接口参数（参数名大小写、学期编码）无法在无账号时实机确认，因此按
///    多种写法依次尝试，首个返回数据的生效；响应 JSON 的行数据 key 同样
///    自适应（遍历 datas 下首个非空 rows）。
///    接口 URL 为相对路径，始终命中当前页面所在域（ehall 或 xsfw 均部署）。
/// 2. 兜底：解析主文档与所有同源 iframe 中的课表 DOM（金智新版用
///    el-table / data 属性渲染），课表应用可能嵌在 frame 内。
/// 3. 找到课表入口链接（href 含 wdkb 或文本含「课表」）-> 模拟点击跳转，
///    返回 {"__nav": true} 由 Dart 侧延迟重试（frame 内导航不触发
///    onPageFinished）。
class JgsuAdapter extends SchoolAdapter {
  @override
  String get schoolName => '井冈山大学';

  @override
  String get pinyin => 'jinggangshandaxue';

  @override
  String get loginUrl => 'https://ehall.jgsu.edu.cn/';

  @override
  bool isSchedulePage(String currentUrl) {
    // 课表应用页与其数据接口同前缀；大厅门户页不算课表页。
    return currentUrl.contains('/jwapp/sys/wdkb');
  }

  @override
  AdapterSupportLevel get supportLevel => AdapterSupportLevel.systemCompatible;

  @override
  String get systemName => '金智智慧校园';

  @override
  String get extractJs => r'''
(function() {
''' + schoolExtractionRuntimeJs + r'''
  var results = [];
  var seen = {};

  function addResult(name, teacher, location, day, secs, weeks) {

    var key = name + '|' + day + '|' + secs.join(',') + '|' +
              (location || '') + '|' + weeks.join(',');
    schoolPushCourse(results, seen, key, name, teacher, location, day, secs, weeks);
  }

  // ═══ 策略1：jwapp 课表接口（登录态下同源 XHR 直调） ═══
  // 参数写法无法离线实机确认，按以下顺序扫描，首个返回行数据的生效：
  //   1) xnm/xqm（小写，按日期推算的当前学期，两种学期编码都试）
  //   2) XNM/XQM（大写变体）
  //   3) 无参数（部分实现默认返回当前学期）
  function tryApi() {
    var now = new Date();
    var m = now.getMonth() + 1;
    var y = now.getFullYear();
    // 学年：9-12 月为 y 级秋季学期；1-8 月属于上一年开学的学年。
    var xnm = String(m >= 9 ? y : y - 1);
    // 当前逻辑学期在两种常见编码下的取值（正方系 秋=3/春=12，强智系反之）。
    var isFall = (m >= 9 || m === 1);
    var codes = isFall ? ['3', '12'] : ['12', '3'];
    var bodies = [
      'xnm=' + xnm + '&xqm=' + codes[0],
      'xnm=' + xnm + '&xqm=' + codes[1],
      'XNM=' + xnm + '&XQM=' + codes[0],
      'XNM=' + xnm + '&XQM=' + codes[1],
      ''
    ];
    var urls = [
      '/jwapp/sys/wdkb/modules/xskcb/xsallkb.do',
      '/jwapp/sys/wdkb/modules/xskcb/xskcb.do'
    ];
    for (var u = 0; u < urls.length; u++) {
      for (var b = 0; b < bodies.length; b++) {
        try {
          var xhr = new XMLHttpRequest();
          xhr.open('POST', urls[u], false);
          xhr.setRequestHeader('Content-Type',
              'application/x-www-form-urlencoded; charset=UTF-8');
          xhr.send(bodies[b]);
          if (xhr.status !== 200) continue;
          var data = JSON.parse(xhr.responseText);
          var list = extractRows(data);
          if (!list || list.length === 0) continue;
          for (var i = 0; i < list.length; i++) {
            var it = list[i];
            if (!it || typeof it !== 'object') { results.push(null); continue; }
            var day = schoolInteger(it.xqj);
            if (isNaN(day) && it.xqjmc) {
              var dm = String(it.xqjmc).match(/周([一二三四五六日天])|星期([一二三四五六日天])/);
              if (dm) day = schoolDayMap[dm[1] || dm[2]];
            }
            addResult(
              String(it.kcmc || it.kcName || it.courseName || ''),
              it.xm || it.jsxm || it.teacherName || null,
              it.cdmc || it.jxcdmc || it.jxcd || null,
              day,
              schoolParseSections(String(it.jc || it.jcs || '')),
              schoolParseWeeks(String(it.zcd || ''))
            );
          }
          if (results.length > 0) return true;
        } catch (e) {}
      }
    }
    return false;
  }

  // 从金智响应中取出行数据：遍历 datas 下首个非空 rows（不同接口/版本
  // 的 key 名不一致），并兼容 kbList / rows / 顶层数组等形状。
  function extractRows(data) {
    if (Object.prototype.toString.call(data) === '[object Array]') {
      return data;
    }
    if (!data) return [];
    if (Object.prototype.toString.call(data.datas) === '[object Array]') {
      return data.datas;
    }
    if (data.datas && typeof data.datas === 'object') {
      for (var key in data.datas) {
        if (!Object.prototype.hasOwnProperty.call(data.datas, key)) continue;
        var node = data.datas[key];
        if (node && Object.prototype.toString.call(node.rows) ===
            '[object Array]' && node.rows.length > 0) {
          return node.rows;
        }
      }
    }
    if (Object.prototype.toString.call(data.rows) === '[object Array]' &&
        data.rows.length > 0) {
      return data.rows;
    }
    if (Object.prototype.toString.call(data.kbList) === '[object Array]' &&
        data.kbList.length > 0) {
      return data.kbList;
    }
    return [];
  }

  // ═══ 汇总主文档与所有同源 frame（课表应用可能嵌在 iframe 内） ═══
  var docs = schoolCollectDocuments();

  // 1. 接口直连
  if (tryApi()) return JSON.stringify(results);

  // 2. DOM 解析：金智 el-table 渲染的课表（含 data 属性变体），遍历所有文档
  for (var d = 0; d < docs.length; d++) {
    var doc = docs[d];
    if (!doc || !doc.querySelectorAll) continue;
    var containers = doc.querySelectorAll(
        '#kbTable, .kb-table, .el-table__body, [class*="kbTable"], [class*="course"]');
    for (var c = 0; c < containers.length; c++) {
      var rows = containers[c].querySelectorAll('tbody tr, tr');
      for (var r = 0; r < rows.length; r++) {
        var cells = rows[r].querySelectorAll('td');
        for (var k = 0; k < cells.length; k++) {
          var cell = cells[k];
          var rawDay = cell.getAttribute('data-week') ||
                       cell.getAttribute('data-day') ||
                       cell.getAttribute('data-weekday') || '';
          var day = 0;
          var dm = String(rawDay).match(/(?:周|星期)?([一二三四五六日天])/);
          if (dm && schoolDayMap[dm[1]]) day = schoolDayMap[dm[1]];
          if (!day) {
            var num = schoolInteger(rawDay);
            if (num >= 1 && num <= 7) day = num;
            else if (rawDay !== '' && num >= 0 && num <= 6) day = num + 1;
          }
          var begin = schoolInteger(cell.getAttribute('data-begin-unit') ||
                               cell.getAttribute('data-start-section') || '0');
          var end = schoolInteger(cell.getAttribute('data-end-unit') ||
                             cell.getAttribute('data-end-section') || '0');


          var text = (cell.innerText || cell.textContent || '').trim();
          if (!text || text.length < 2) continue;
          // 单元格文本首行=课程名，其余行找 周次/教师/教室
          var lines = text.split(/[\n\r]+/).map(function(s){return s.trim();})
              .filter(Boolean);
          if (lines.length === 0) continue;
          var name = lines[0].replace(/\([^)]*\)$/g, '').replace(/（[^）]*）$/g, '');
          var weeks = [];
          var teacher = null, location = null;
          for (var li = 1; li < lines.length; li++) {
            var ln = lines[li];
            if (!weeks.length && (/\d+.*周/.test(ln) || /单周/.test(ln) || /双周/.test(ln))) {
              weeks = schoolParseWeeks(ln);
              continue;
            }
            if (!teacher && ln.length >= 2 && ln.length <= 10 && !/\d+周/.test(ln)) {
              teacher = ln;
            } else if (!location && ln.length >= 2 && ln.length <= 30) {
              location = ln;
            }
          }
          var secs = [begin, end];
          addResult(name, teacher, location, day || 0, secs, weeks);
        }
      }
      if (results.length > 0) return JSON.stringify(results);
    }
  }

  // 3. 找到课表入口 -> 模拟点击并让 Dart 侧延迟重试。
  //    两轮匹配：先命中 href 指向 wdkb 应用，再看文本含「课表」
  //    （兼容「我的课表」「学生个人课表」等各种长度的入口名）。
  var nav = schoolClickEntry(docs, 'a, [onclick]', function(el) {
    var href = el.getAttribute ? (el.getAttribute('href') || '') : '';
    return !!(href && href.indexOf('wdkb') >= 0);
  }) || schoolClickEntry(docs, 'a, [onclick]', function(el) {
    var text = (el.textContent || el.getAttribute('title') || '').trim();
    var href = el.getAttribute ? (el.getAttribute('href') || '') : '';
    return text.indexOf('课表') >= 0 || href.indexOf('kbcx') >= 0;
  });
  if (nav) return nav;

  return JSON.stringify(results);
})();
''';
}
