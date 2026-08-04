import 'school_adapter.dart';

/// 沈阳化工大学（正方教务管理系统 ZFSoft）适配器。
///
/// 教务系统：jws.syuct.edu.cn（学生入口，老版 ASP.NET WebForms）
/// 登录页：/(安全码)/default2.aspx（学号 + 密码 + 验证码，验证码在 WebView 中手动输入）
/// 登录成功 → xs_main.aspx?xh=学号（框架集页面，菜单位于左侧 frame）
/// 课表页：xskbcx.aspx?xh=…&xm=…&gnmkdm=N121603
/// 课表结构：<table id="Table1">，课程单元格 4 行文本：
///   课程名 / 教师 / 周X第Y,Z节{第A-B周} / 教室
///
/// 提取流程：extractJs 一次注入完成「导航 + 提取」——
/// 1. 若主文档或任一 frame 已渲染课表，直接解析返回
/// 2. 否则找到「学生个人课表」链接并模拟点击（frame 内导航不触发
///    onPageFinished，故返回 {"__nav": true} 占位）
/// 3. Dart 侧延迟后自动重试注入，直到解析成功
class SyuctAdapter extends SchoolAdapter {
  @override
  String get schoolName => '沈阳化工大学';

  @override
  String get loginUrl => 'https://jws.syuct.edu.cn/';

  @override
  String get scheduleUrl => 'https://jws.syuct.edu.cn/xskbcx.aspx';

  @override
  bool isSchedulePage(String currentUrl) {
    return currentUrl.contains('xskbcx.aspx');
  }

  @override
  String get extractJs => r'''
(function() {
  var dayMap = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':7,'天':7};

  // ═══ 解析周次文本（如 "第1-16周"、"第1-8周|单周"、"第2-16周|双周"、"第1-2周,第5-16周"）═══
  function parseWeeks(t) {
    var weeks = [];
    if (!t) return weeks;
    var odd = t.indexOf('单周') >= 0;
    var even = t.indexOf('双周') >= 0;
    var cleaned = t.replace(/第|周|单|双|\|/g, '');
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
    // 去重排序
    var unique = [];
    var seenW = {};
    for (var i = 0; i < weeks.length; i++) {
      if (!seenW[weeks[i]]) { seenW[weeks[i]] = true; unique.push(weeks[i]); }
    }
    unique.sort(function(a, b) { return a - b; });
    return unique;
  }

  // ═══ 解析节次文本（如 "1,2"、"3"、"1-2"）═══
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

  // ═══ 解析单个文档中的课表 ═══
  function parseDoc(doc) {
    var out = [];
    var table = doc.getElementById ? doc.getElementById('Table1') : null;
    if (!table) table = doc.querySelector && doc.querySelector('table.blacktab');
    var tds = table ? table.querySelectorAll('td')
                    : (doc.querySelectorAll ? doc.querySelectorAll('td') : []);
    var seen = {};
    for (var i = 0; i < tds.length; i++) {
      var text = (tds[i].innerText || tds[i].textContent || '')
          .replace(/\u00a0/g, ' ').trim();
      if (!text) continue;
      // 以「周X第…节{第…}」模式把同一单元格内并排的多门课切分为独立块
      var blocks = text.split(/(?=周[一二三四五六日天]\s*第\s*\d)/);
      for (var b = 0; b < blocks.length; b++) {
        var block = blocks[b];
        var m = block.match(/周([一二三四五六日天])\s*第\s*([\d,，、\s\-–~]+?)\s*节\s*\{第\s*([^}]+)\}/);
        if (!m) continue;
        var day = dayMap[m[1]];
        if (!day) continue;
        var secs = parseSections(m[2]);
        if (secs.length === 0) continue;
        var weeks = parseWeeks(m[3]);
        var lines = block.split(/\n/).map(function(l) { return l.trim(); }).filter(Boolean);
        // 模式行在块内的索引
        var modeIdx = -1;
        for (var k = 0; k < lines.length; k++) {
          if (/周[一二三四五六日天]\s*第\s*\d.*节.*\{第/.test(lines[k])) { modeIdx = k; break; }
        }
        if (modeIdx < 0) continue;
        // 名称：模式行之前的第一行；若模式行在第一行则取其后的第一行
        var name = '';
        for (var k2 = 0; k2 < modeIdx; k2++) {
          var ln = lines[k2];
          if (ln.length >= 2 && ln.length <= 60) { name = ln; break; }
        }
        if (!name) {
          for (var k3 = modeIdx + 1; k3 < lines.length; k3++) {
            var ln3 = lines[k3];
            if (ln3.length >= 2 && ln3.length <= 60) { name = ln3; break; }
          }
        }
        if (name.length < 2) continue;
        // 教师：模式行之前的第二行（名称之后）
        var teacher = null;
        var tCount = 0;
        for (var k4 = 0; k4 < modeIdx; k4++) {
          if (lines[k4].length >= 2) {
            tCount++;
            if (tCount === 2) { teacher = lines[k4]; break; }
          }
        }
        // 教室：模式行之后的第一行
        var location = null;
        for (var k5 = modeIdx + 1; k5 < lines.length; k5++) {
          var ln5 = lines[k5];
          if (ln5.length >= 1 && ln5.length <= 40) { location = ln5; break; }
        }
        // 去掉课程名尾部的学年备注（如 "高等数学(2024-2025-1)"）
        name = name.replace(/\(\d{4}[^)]*\)\s*$/, '').trim();
        var key = name + '|' + day + '|' + secs[0] + '|' +
            secs[secs.length - 1] + '|' + weeks.join(',');
        if (seen[key]) continue;
        seen[key] = true;
        out.push({
          name: name,
          teacher: teacher,
          location: location,
          dayOfWeek: day,
          startSection: secs[0],
          endSection: secs[secs.length - 1],
          weeks: weeks
        });
      }
    }
    return out;
  }

  // ═══ 汇总主文档与所有同源 frame 的文档 ═══
  var docs = [document];
  var wins = [window];
  var frames = document.querySelectorAll('frame, iframe');
  for (var f = 0; f < frames.length; f++) {
    try {
      var fd = frames[f].contentDocument;
      if (fd) { docs.push(fd); wins.push(frames[f].contentWindow); }
    } catch (e) {}
  }

  // 1. 已有课表（主文档或任一 frame）→ 直接解析
  for (var i = 0; i < docs.length; i++) {
    var r = parseDoc(docs[i]);
    if (r.length > 0) return JSON.stringify(r);
  }

  // 2. 检测到课表容器但暂无课程（页面加载中 / 本学期无课）→ 等待重试
  for (var i = 0; i < docs.length; i++) {
    if (docs[i].getElementById && docs[i].getElementById('Table1')) {
      return JSON.stringify({ __pending: true });
    }
  }

  // 3. 找到「学生个人课表」链接 → 模拟点击（浏览器按 target 在对应 frame 打开）
  for (var i = 0; i < docs.length; i++) {
    var links = docs[i].querySelectorAll
        ? docs[i].querySelectorAll('a[href*="xskbcx.aspx"], a[href*="xskbcx"]')
        : [];
    var fallback = null;
    for (var j = 0; j < links.length; j++) {
      var t = (links[j].textContent || '').trim();
      if (t.indexOf('个人课表') >= 0 || t.indexOf('学生课表') >= 0) {
        try { links[j].click(); } catch (e) {}
        return JSON.stringify({ __nav: true });
      }
      if (!fallback) fallback = links[j];
    }
    if (fallback) {
      try { fallback.click(); } catch (e) {}
      return JSON.stringify({ __nav: true });
    }
  }

  return JSON.stringify([]);
})();
''';
}
