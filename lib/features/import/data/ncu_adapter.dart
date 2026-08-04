import 'school_adapter.dart';

/// 南昌大学（强智教务管理系统 QZSoft）适配器。
///
/// 教务系统：jwpt.ncu.edu.cn（湖南强智科技，路径 /jsxsd/）
/// 登录页：/jsxsd/（账号 + 密码 + 验证码，验证码在 WebView 中手动输入）
/// 登录成功 → 学生主页（框架集或单页布局，菜单位于左侧）
/// 课表页：/jsxsd/kbcx/xskbcx_cxXsgg.html（「学生个人课表」菜单）
/// 课表数据接口：/jsxsd/kbcx/xskbcx_cxXsKb.html?gnmkdm=N2151
///   POST xnm（学年）/ xqm（学期²×3，春=3、秋=12）→ 返回 kbList JSON
///
/// 提取流程（一次注入）：
/// 1. 同步 XHR 直调课表数据接口解析 JSON（登录态下任意页面可用，最可靠）
/// 2. 兜底：解析课表页 DOM（兼容强智/老正方「周X第Y,Z节{第A-B周}」文本格式）
/// 3. 均失败时：点击菜单中的课表链接，返回 {"__nav": true} 由 Dart 侧重试
class NcuAdapter extends SchoolAdapter {
  @override
  String get schoolName => '南昌大学';

  @override
  String get loginUrl => 'https://jwpt.ncu.edu.cn/jsxsd/';

  @override
  String get scheduleUrl =>
      'https://jwpt.ncu.edu.cn/jsxsd/kbcx/xskbcx_cxXsgg.html';

  @override
  bool isSchedulePage(String currentUrl) {
    return currentUrl.contains('xskbcx');
  }

  @override
  String get extractJs => r'''
(function() {
  var results = [];
  var seen = {};
  var dayMap = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':7,'天':7};

  // ═══ 节次解析："1-2" / "1,2" / "3" ═══
  function parseSections(str) {
    var out = [];
    if (!str) return out;
    var parts = str.split(/[,，、]+/);
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim();
      var rm = p.match(/^(\d+)\s*[-–~]\s*(\d+)$/);
      if (rm) {
        for (var s = parseInt(rm[1]); s <= parseInt(rm[2]); s++) out.push(s);
      } else {
        var n = parseInt(p);
        if (!isNaN(n)) out.push(n);
      }
    }
    return out;
  }

  // ═══ 周次解析："1-16周" / "1-16" / "1-8,11-16" / "1-15(单)" / "2-16(双)" ═══
  function parseWeeksText(t) {
    var weeks = [];
    if (!t) return weeks;
    var odd = t.indexOf('单') >= 0 && t.indexOf('双') < 0;
    var even = t.indexOf('双') >= 0 && t.indexOf('单') < 0;
    var cleaned = t.replace(/第|周|单|双|\||[\(\)（）]/g, '');
    var parts = cleaned.split(/[,，、\s]+/);
    var ranges = [];
    var minW = 99, maxW = 0;
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim();
      if (!p) continue;
      var rm = p.match(/^(\d+)\s*[-–~]\s*(\d+)$/);
      if (rm) {
        var a = parseInt(rm[1]), b = parseInt(rm[2]);
        ranges.push([a, b]);
        if (a < minW) minW = a;
        if (b > maxW) maxW = b;
      } else {
        var n = parseInt(p);
        if (!isNaN(n)) {
          ranges.push([n, n]);
          if (n < minW) minW = n;
          if (n > maxW) maxW = n;
        }
      }
    }
    if (odd || even) {
      for (var w = minW; w <= maxW; w++) {
        if (odd && w % 2 === 1) weeks.push(w);
        if (even && w % 2 === 0) weeks.push(w);
      }
    } else {
      for (var j = 0; j < ranges.length; j++) {
        for (var w2 = ranges[j][0]; w2 <= ranges[j][1]; w2++) weeks.push(w2);
      }
    }
    var unique = [];
    var seenW = {};
    for (var i = 0; i < weeks.length; i++) {
      if (!seenW[weeks[i]]) { seenW[weeks[i]] = true; unique.push(weeks[i]); }
    }
    unique.sort(function(a, b) { return a - b; });
    return unique;
  }

  function addResult(name, teacher, location, day, secs, weeks) {
    if (!name) return;
    name = name.replace(/\(\d{4}[^)]*\)\s*$/, '').trim();
    if (name.length < 2 || name.length > 60) return;
    if (!secs || secs.length === 0) return;
    if (day < 1 || day > 7) return;
    var key = name + '|' + day + '|' + secs[0] + '|' +
        secs[secs.length - 1] + '|' + weeks.join(',');
    if (seen[key]) return;
    seen[key] = true;
    results.push({
      name: name,
      teacher: teacher,
      location: location,
      dayOfWeek: day,
      startSection: secs[0],
      endSection: secs[secs.length - 1],
      weeks: weeks
    });
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
    if (!xnm || !xqm) {
      // 兜底：按当前日期推算学年学期（xqm = 学期²×3：春=3、秋=12）
      var now = new Date();
      var m = now.getMonth() + 1;
      var y = now.getFullYear();
      xnm = String(y - 1);
      xqm = (m >= 2 && m <= 8) ? '3' : '12';
    }
    var urls = [
      '/jsxsd/kbcx/xskbcx_cxXsKb.html?gnmkdm=N2151',
      '/jsxsd/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151'
    ];
    for (var u = 0; u < urls.length; u++) {
      try {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', urls[u], false);
        xhr.setRequestHeader('Content-Type',
            'application/x-www-form-urlencoded; charset=UTF-8');
        xhr.send('xnm=' + encodeURIComponent(xnm) + '&xqm=' +
                 encodeURIComponent(xqm));
        if (xhr.status !== 200) continue;
        var data = JSON.parse(xhr.responseText);
        var list = data.kbList || data.items || data.rows || [];
        if (!list || list.length === 0) continue;
        for (var i = 0; i < list.length; i++) {
          var it = list[i];
          var day = parseInt(it.xqj);
          if (isNaN(day) && it.xqjmc) {
            var dm = String(it.xqjmc).match(/周([一二三四五六日天])|星期([一二三四五六日天])/);
            if (dm) day = dayMap[dm[1] || dm[2]];
          }
          var secs = parseSections(String(it.jc || ''));
          var weeks = parseWeeksText(String(it.zcd || ''));
          addResult(
            String(it.kcmc || ''),
            it.xm || it.jsxm || null,
            it.cdmc || it.jxcd || null,
            day, secs, weeks
          );
        }
        if (results.length > 0) return true;
      } catch (e) {}
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
          day = dayMap[m1[1]];
          secs = parseSections(m1[2]);
          weeks = parseWeeksText(m1[3]);
        } else {
          var m2 = line.match(/^([\d,，、\-–~\s]+?)\s*周\s*周([一二三四五六日天])\s*第\s*([\d,，、\s\-–~]+?)\s*节/);
          if (m2) {
            day = dayMap[m2[2]];
            secs = parseSections(m2[3]);
            weeks = parseWeeksText(m2[1] + '周');
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
  var docs = [document];
  var wins = [window];
  var frames = document.querySelectorAll('frame, iframe');
  for (var f = 0; f < frames.length; f++) {
    try {
      var fd = frames[f].contentDocument;
      if (fd) { docs.push(fd); wins.push(frames[f].contentWindow); }
    } catch (e) {}
  }

  // 1. 接口直连（登录态下任意页面可用）
  if (tryApi()) return JSON.stringify(results);

  // 2. DOM 解析
  for (var i = 0; i < docs.length; i++) {
    parseDoc(docs[i]);
    if (results.length > 0) return JSON.stringify(results);
  }

  // 3. 课表容器存在但暂无课程（加载中 / 本学期无课）→ 等待重试
  for (var i = 0; i < docs.length; i++) {
    if (docs[i].querySelector) {
      var kb = docs[i].querySelector('#kbTable, .kb-table, #table1, table.kbTable, .el-table__body');
      if (kb) return JSON.stringify({ __pending: true });
    }
  }

  // 4. 找到课表菜单链接 → 模拟点击
  for (var i = 0; i < docs.length; i++) {
    var links = docs[i].querySelectorAll
        ? docs[i].querySelectorAll('a[href*="xskbcx"], a[href*="kbcx"]')
        : [];
    for (var j = 0; j < links.length; j++) {
      var t = (links[j].textContent || '').trim();
      if (t.indexOf('课表') >= 0 || /xskbcx/i.test(links[j].href)) {
        try { links[j].click(); } catch (e) {}
        return JSON.stringify({ __nav: true });
      }
    }
  }

  return JSON.stringify([]);
})();
''';
}
