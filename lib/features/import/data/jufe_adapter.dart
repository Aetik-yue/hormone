import 'school_adapter.dart';

/// 江西财经大学（青果教务 KINGOSOFT）适配器。
///
/// 教务系统：xk.jxufe.cn（青果软件 KINGOSOFT 高校智慧校园教学管理服务平台）
/// 登录页支持账号登录 + 扫码登录，正常情况免验证码。
/// 课表页通常为 /student/course/schedule 或 /xsjxgl/xskbcx。
///
/// 提取策略：
/// 1. data-属性模式（青果/金智新版通用）
/// 2. 传统表格模式（行=节次，列=星期）
/// 两种模式均使用 cell.innerText 文本解析，而非按索引访问子元素，
/// 避免嵌套 DOM 结构导致索引偏移。
class JufeAdapter extends SchoolAdapter {
  @override
  String get schoolName => '江西财经大学';

  @override
  String get loginUrl => 'https://xk.jxufe.cn/';

  @override
  String get scheduleUrl =>
      'https://xk.jxufe.cn/student/course/schedule';

  @override
  bool isSchedulePage(String currentUrl) {
    return currentUrl.contains('/course/schedule') ||
        currentUrl.contains('/xsjxgl/xskbcx');
  }

  @override
  String get extractJs => r'''
(function() {
  var results = [];
  var dayMap = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':7,'天':7};
  var seen = {};

  // ═══ 找课表容器 ═══
  var table = document.querySelector('#kbTable') ||
              document.querySelector('.kb-table') ||
              document.querySelector('#wdkbTable') ||
              document.querySelector('table.kbTable') ||
              document.querySelector('.el-table__body') ||
              document.querySelector('#xsKbTable');

  if (!table) {
    // 兜底：找 td 最多的 table
    var tables = document.querySelectorAll('table');
    var maxTd = 0;
    for (var i = 0; i < tables.length; i++) {
      var tdCount = tables[i].querySelectorAll('td').length;
      if (tdCount > maxTd) { maxTd = tdCount; table = tables[i]; }
    }
  }
  if (!table) return JSON.stringify([]);

  // ═══ 策略1：data-属性模式（青果/金智新版） ═══
  var rows = table.querySelectorAll('tbody tr, tr');
  var hasDataAttrs = false;
  rows.forEach(function(row) {
    if (row.getAttribute('data-week') || row.getAttribute('data-day')) hasDataAttrs = true;
  });

  if (hasDataAttrs) {
    rows.forEach(function(row) {
      var day = parseInt(row.getAttribute('data-week') || row.getAttribute('data-day') || '0');
      if (day < 1 || day > 7) {
        if (day >= 0 && day <= 6) day = day + 1;
        else return;
      }
      var cells = row.querySelectorAll('td');
      cells.forEach(function(cell) {
        var beginUnit = parseInt(cell.getAttribute('data-begin-unit') ||
                                 row.getAttribute('data-begin-unit') || '0');
        var endUnit = parseInt(cell.getAttribute('data-end-unit') ||
                               row.getAttribute('data-end-unit') || '0');
        if (beginUnit < 1) return;
        if (endUnit < beginUnit) endUnit = beginUnit;

        // 用 cell.innerText 获取完整文本再解析，避免按索引访问子元素
        var cellText = (cell.innerText || cell.textContent || '').trim();
        if (!cellText || cellText.length < 2) return;

        var parsed = parseCellText(cellText);
        if (!parsed.name) return;

        var key = parsed.name + '|' + day + '|' + beginUnit + '|' + (parsed.location || '') + '|' + parsed.weeks.join(',');
        if (seen[key]) return;
        seen[key] = true;

        results.push({
          name: parsed.name,
          teacher: parsed.teacher || null,
          location: parsed.location || null,
          dayOfWeek: day,
          startSection: beginUnit,
          endSection: endUnit,
          weeks: parsed.weeks
        });
      });
    });
  } else {
    // ═══ 策略2：传统表格模式（行=节次，列=星期） ═══
    var allRows = table.querySelectorAll('tr');
    // 检测表头行确定星期列起始位置
    var dayColStart = 1;
    if (allRows.length > 0) {
      var headerCells = allRows[0].querySelectorAll('th, td');
      for (var hi = 0; hi < headerCells.length; hi++) {
        var ht = (headerCells[hi].textContent || '').trim();
        var hdm = ht.match(/周([一二三四五六日天])/) || ht.match(/星期([一二三四五六日天])/);
        if (hdm && dayMap[hdm[1]]) { dayColStart = hi; break; }
      }
    }

    for (var r = 1; r < allRows.length; r++) {
      var cells = allRows[r].querySelectorAll('td');
      if (cells.length < 2) continue;
      var sectionText = cells[0] ? cells[0].textContent.trim() : '';
      var sectionNum = parseInt(sectionText) || r;

      for (var c = dayColStart; c < cells.length && c < dayColStart + 7; c++) {
        var dayIdx = c - dayColStart + 1;
        var cellText = cells[c] ? cells[c].textContent.trim() : '';
        if (!cellText || cellText === ' ' || cellText.length < 2) continue;

        var parsed = parseCellText(cellText);
        if (!parsed.name) continue;

        var key = parsed.name + '|' + dayIdx + '|' + sectionNum + '|' + (parsed.location || '') + '|' + parsed.weeks.join(',');
        if (seen[key]) continue;
        seen[key] = true;

        results.push({
          name: parsed.name,
          teacher: parsed.teacher || null,
          location: parsed.location || null,
          dayOfWeek: dayIdx,
          startSection: sectionNum,
          endSection: sectionNum,
          weeks: parsed.weeks
        });
      }
    }
  }

  return JSON.stringify(results);

  // ═══ 工具函数 ═══

  function parseCellText(text) {
    var lines = text.split(/[\n\r]+/).map(function(s) { return s.trim(); }).filter(Boolean);
    if (lines.length === 0) return { name: '', weeks: [], teacher: null, location: null };

    var name = '', teacher = null, location = null, weeks = [];
    var weeksText = '';

    if (lines.length >= 2) {
      name = lines[0];
      // 找周次行
      for (var li = 1; li < lines.length; li++) {
        if (/\d+.*周/.test(lines[li]) || /单周/.test(lines[li]) || /双周/.test(lines[li])) {
          weeksText = lines[li];
          weeks = parseWeeks(weeksText);
          break;
        }
      }
      // 教师和教室：其余行
      for (var li = 1; li < lines.length; li++) {
        if (lines[li] === weeksText) continue;
        if (!teacher && lines[li].length >= 2 && lines[li].length <= 10 && !/\d+周/.test(lines[li])) {
          teacher = lines[li];
        } else if (!location && lines[li].length >= 2 && lines[li].length <= 30) {
          location = lines[li];
        }
      }
    } else {
      // 单行：尝试用分隔符拆分
      var parts = text.split(/[,，;；\s]+/).filter(Boolean);
      name = parts[0] || '';
      for (var pi = 1; pi < parts.length; pi++) {
        if (/\d+.*周/.test(parts[pi]) || /单周/.test(parts[pi]) || /双周/.test(parts[pi])) {
          weeksText = parts[pi];
          weeks = parseWeeks(weeksText);
        } else if (!location && parts[pi].length >= 2) {
          location = parts[pi];
        }
      }
    }

    if (name) name = name.replace(/\([^)]*\)$/g, '').replace(/（[^）]*）$/g, '').trim();

    return { name: name, weeks: weeks, teacher: teacher, location: location };
  }

  function parseWeeks(text) {
    if (!text) return [];
    var weeks = [];
    if (/单周/.test(text)) {
      for (var i = 1; i <= 20; i += 2) weeks.push(i);
      return weeks;
    }
    if (/双周/.test(text)) {
      for (var i = 2; i <= 20; i += 2) weeks.push(i);
      return weeks;
    }
    var cleaned = text.replace(/第|周|节/g, '');
    var parts = cleaned.split(/[,，、\s]+/);
    parts.forEach(function(part) {
      part = part.trim();
      if (!part) return;
      var rangeMatch = part.match(/(\d+)\s*[-–~]\s*(\d+)/);
      if (rangeMatch) {
        var start = parseInt(rangeMatch[1]);
        var end = parseInt(rangeMatch[2]);
        for (var i = start; i <= end; i++) weeks.push(i);
      } else {
        var num = parseInt(part);
        if (!isNaN(num)) weeks.push(num);
      }
    });
    weeks = weeks.filter(function(v, i, a) { return a.indexOf(v) === i; });
    weeks.sort(function(a, b) { return a - b; });
    return weeks;
  }
})();
''';
}
