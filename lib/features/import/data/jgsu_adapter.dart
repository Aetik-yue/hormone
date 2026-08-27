import 'package:hormone/features/import/data/school_adapter.dart';

/// 井冈山大学（金智智慧校园 wisedu）适配器。
///
/// 校园信息化为金智生态：
/// - 统一身份认证：authserver.jgsu.edu.cn（CAS 风格登录页）
/// - 一站式办事大厅：ehall.jgsu.edu.cn（ywtb-portal）
/// - 学生服务：xsfw.jgsu.edu.cn（同样挂 authserver 登录）
/// - 新版教务「我的课表」：/jwapp/sys/wdkb/（jwapp 模块，接口返回 kbList JSON）
/// - 旧域名 jw.jgsu.edu.cn 位于深信服 aTrust 零信任网关之后，浏览器登录
///   需要客户端校验，不适合 WebView 导入，因此入口选 ehall。
///
/// 提取流程（一次注入）：
/// 1. 同步 XHR 直调 jwapp 课表接口（登录态下任意同源页面可用，最可靠）；
///    接口在 ehall 与 xsfw 两个域下各试一次，以当前页面所在域为准。
/// 2. 兜底：解析页面内课表 DOM（金智新版用 el-table / data 属性渲染，
///    直接复用通用抽取器的 data-属性与传统表格策略）。
/// 3. 找到「课表」入口链接 → 模拟点击跳转，返回 {"__nav": true} 由 Dart
///    侧延迟重试（frame 内导航不触发 onPageFinished）。
class JgsuAdapter extends SchoolAdapter {
  @override
  String get schoolName => '井冈山大学';

  @override
  String get loginUrl => 'https://ehall.jgsu.edu.cn/';

  @override
  String get scheduleUrl =>
      'https://ehall.jgsu.edu.cn/jwapp/sys/wdkb/index.do';

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
  var results = [];
  var seen = {};
  var dayMap = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':7,'天':7};

  function parseSections(str) {
    var out = [];
    if (!str) return out;
    var parts = String(str).split(/[,，、]+/);
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim();
      var rm = p.match(/(\d+)\s*[-–~]\s*(\d+)/);
      if (rm) {
        for (var s = parseInt(rm[1]); s <= parseInt(rm[2]); s++) out.push(s);
      } else {
        var n = parseInt(p);
        if (!isNaN(n)) out.push(n);
      }
    }
    return out;
  }

  // 周次文本："1-16周" / "1-8,11-16" / "1-15(单)" / "2-16(双)"
  function parseWeeksText(t) {
    var weeks = [];
    if (!t) return weeks;
    t = String(t);
    var odd = t.indexOf('单') >= 0 && t.indexOf('双') < 0;
    var even = t.indexOf('双') >= 0 && t.indexOf('单') < 0;
    var cleaned = t.replace(/第|周|单|双|\||[\(\)（）]/g, '');
    var parts = cleaned.split(/[,，、\s]+/);
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim();
      if (!p) continue;
      var rm = p.match(/(\d+)\s*[-–~]\s*(\d+)/);
      if (rm) {
        for (var w = parseInt(rm[1]); w <= parseInt(rm[2]); w++) weeks.push(w);
      } else {
        var n = parseInt(p);
        if (!isNaN(n)) weeks.push(n);
      }
    }
    weeks = weeks.filter(function(v, i, a) {
      if (a.indexOf(v) !== i) return false;
      if (odd) return v % 2 === 1;
      if (even) return v % 2 === 0;
      return true;
    });
    weeks.sort(function(a, b) { return a - b; });
    return weeks;
  }

  function addResult(name, teacher, location, day, secs, weeks) {
    if (!name || !day || day < 1 || day > 7 || !secs || secs.length === 0) return;
    var key = name + '|' + day + '|' + secs.join(',') + '|' +
              (location || '') + '|' + weeks.join(',');
    if (seen[key]) return;
    seen[key] = true;
    results.push({
      name: String(name).trim(),
      teacher: teacher || null,
      location: location || null,
      dayOfWeek: day,
      startSection: secs[0],
      endSection: secs[secs.length - 1],
      weeks: weeks
    });
  }

  // ═══ 策略1：jwapp 课表接口（登录态下同源 XHR 直调） ═══
  // 金智新版「我的课表」模块；学期参数 xnm-1（学年）/ xnm-4（学期：春=3、秋=12）。
  function tryApi() {
    var now = new Date();
    var m = now.getMonth() + 1;
    var y = now.getFullYear();
    var xnm = String(m >= 9 ? y : y - 1);
    var xqm = (m >= 2 && m <= 8) ? '3' : '12';
    var urls = [
      '/jwapp/sys/wdkb/modules/xskcb/xsallkb.do',
      '/jwapp/sys/wdkb/modules/xskcb/xskcb.do'
    ];
    for (var u = 0; u < urls.length; u++) {
      try {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', urls[u], false);
        xhr.setRequestHeader('Content-Type',
            'application/x-www-form-urlencoded; charset=UTF-8');
        xhr.send('xnm-1=' + encodeURIComponent(xnm) +
                 '&xnm-4=' + encodeURIComponent(xqm));
        if (xhr.status !== 200) continue;
        var data = JSON.parse(xhr.responseText);
        var list = (data.datas && data.datas.xsallkb &&
                    data.datas.xsallkb.rows) || [];
        if (!list || list.length === 0) continue;
        for (var i = 0; i < list.length; i++) {
          var it = list[i];
          var day = parseInt(it.xqj);
          if (isNaN(day) && it.xqjmc) {
            var dm = String(it.xqjmc).match(/周([一二三四五六日天])|星期([一二三四五六日天])/);
            if (dm) day = dayMap[dm[1] || dm[2]];
          }
          addResult(
            String(it.kcmc || ''),
            it.xm || it.jsxm || null,
            it.cdmc || it.jxcd || null,
            day,
            parseSections(String(it.jc || '')),
            parseWeeksText(String(it.zcd || ''))
          );
        }
        if (results.length > 0) return true;
      } catch (e) {}
    }
    return false;
  }

  // ═══ 汇总主文档与所有同源 frame ═══
  var docs = [document];
  var frames = document.querySelectorAll('frame, iframe');
  for (var f = 0; f < frames.length; f++) {
    try {
      var fd = frames[f].contentDocument;
      if (fd) docs.push(fd);
    } catch (e) {}
  }

  // 1. 接口直连
  if (tryApi()) return JSON.stringify(results);

  // 2. DOM 解析：金智 el-table 渲染的课表（含 data 属性变体）
  var containers = document.querySelectorAll(
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
        if (dm && dayMap[dm[1]]) day = dayMap[dm[1]];
        if (!day) {
          var num = parseInt(rawDay);
          if (num >= 1 && num <= 7) day = num;
          else if (rawDay !== '' && num >= 0 && num <= 6) day = num + 1;
        }
        var begin = parseInt(cell.getAttribute('data-begin-unit') ||
                             cell.getAttribute('data-start-section') || '0');
        var end = parseInt(cell.getAttribute('data-end-unit') ||
                           cell.getAttribute('data-end-section') || '0');
        if (begin < 1) continue;
        if (end < begin) end = begin;
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
            weeks = parseWeeksText(ln);
            continue;
          }
          if (!teacher && ln.length >= 2 && ln.length <= 10 && !/\d+周/.test(ln)) {
            teacher = ln;
          } else if (!location && ln.length >= 2 && ln.length <= 30) {
            location = ln;
          }
        }
        var secs = [begin];
        for (var s = begin + 1; s <= end; s++) secs.push(s);
        addResult(name, teacher, location, day || 0, secs, weeks);
      }
    }
    if (results.length > 0) return JSON.stringify(results);
  }

  // 3. 找到课表入口 → 模拟点击并让 Dart 侧延迟重试
  var links = document.querySelectorAll('a, [onclick]');
  for (var l = 0; l < links.length; l++) {
    var el = links[l];
    var t = (el.textContent || el.getAttribute('title') || '').trim();
    var href = el.getAttribute && (el.getAttribute('href') || '');
    if ((t.indexOf('课表') >= 0 && t.indexOf('课表') < 6) ||
        (href && href.indexOf('wdkb') >= 0)) {
      try { el.click(); } catch (e) {}
      return JSON.stringify({ __nav: true });
    }
  }

  return JSON.stringify(results);
})();
''';
}
