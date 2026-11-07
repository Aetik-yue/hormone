import 'school_extraction_runtime.dart';
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
  String get pinyin => 'shenyanghuagongdaxue';

  @override
  String get loginUrl => 'https://jws.syuct.edu.cn/';

  @override
  bool isSchedulePage(String currentUrl) {
    return currentUrl.contains('xskbcx.aspx');
  }

  @override
  String get extractJs => r'''
(function() {
''' + schoolExtractionRuntimeJs + r'''
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
      var blocks = text.split(/(?=周[一二三四五六日天]\s*第)/);
      for (var b = 0; b < blocks.length; b++) {
        var block = blocks[b];
        var m = block.match(/周([一二三四五六日天])\s*第\s*([^\n{}]*?)\s*节\s*\{第\s*([^}]+)\}/);
        if (!m) continue;
        var day = schoolDayMap[m[1]];
        if (!day) continue;
        var secs = schoolParseSections(m[2]);
        if (secs.length === 0) continue;
        var weeks = schoolParseWeeks(m[3]);
        var lines = block.split(/\n/).map(function(l) { return l.trim(); }).filter(Boolean);
        // 模式行在块内的索引
        var modeIdx = -1;
        for (var k = 0; k < lines.length; k++) {
          if (/周[一二三四五六日天]\s*第.*节.*\{第/.test(lines[k])) { modeIdx = k; break; }
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
        schoolPushCourse(out, seen, key, name, teacher, location, day,
            secs, weeks);
      }
    }
    return out;
  }

  // ═══ 汇总主文档与所有同源 frame 的文档 ═══
  var docs = schoolCollectDocuments();

  // 1. 已有课表（主文档或任一 frame）→ 直接解析
  for (var i = 0; i < docs.length; i++) {
    var r = parseDoc(docs[i]);
    if (r.length > 0) return JSON.stringify(r);
  }

  // 2. 检测到课表容器但暂无课程（页面加载中 / 本学期无课）→ 等待重试
  if (schoolAnyDoc(docs, function(doc) {
    return doc.getElementById && doc.getElementById('Table1');
  })) return JSON.stringify({ __pending: true });

  // 3. 找到「学生个人课表」链接 → 模拟点击（浏览器按 target 在对应 frame 打开）
  var nav = schoolClickEntry(docs,
      'a[href*="xskbcx.aspx"], a[href*="xskbcx"]', function(link) {
    var t = (link.textContent || '').trim();
    return t.indexOf('个人课表') >= 0 || t.indexOf('学生课表') >= 0;
  }, true);
  if (nav) return nav;

  return JSON.stringify([]);
})();
''';
}
