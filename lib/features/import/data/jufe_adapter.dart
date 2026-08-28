import 'school_adapter.dart';

/// 江西财经大学教务管理系统专用适配器。
///
/// 学校当前公布的入口为 xk.jxufe.edu.cn；登录后可从「公共查询」或
/// 「网上选课 → 课程安排明细」进入课表。系统存在新版 data 属性表格、
/// 传统节次表格以及 iframe 三种页面形态，因此提取器会逐级尝试。
class JufeAdapter extends SchoolAdapter {
  @override
  String get schoolName => '江西财经大学';

  @override
  String get loginUrl => 'http://xk.jxufe.edu.cn/';

  @override
  String get scheduleUrl => 'http://xk.jxufe.edu.cn/';

  @override
  bool isSchedulePage(String currentUrl) {
    final url = currentUrl.toLowerCase();
    return url.contains('/course/schedule') ||
        url.contains('/xsjxgl/xskbcx') ||
        url.contains('kbcx') ||
        url.contains('coursearrange') ||
        url.contains('course-arrange');
  }

  @override
  String get extractJs => r'''
(function() {
  var results = [];
  var seen = {};
  var dayMap = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':7,'天':7};

  function attr(el, names) {
    if (!el || !el.getAttribute) return '';
    for (var i = 0; i < names.length; i++) {
      var value = el.getAttribute(names[i]);
      if (value !== null && value !== '') return value;
    }
    return '';
  }

  function parseWeeks(text) {
    if (!text) return [];
    var raw = String(text);
    var odd = /单|奇/.test(raw) && !/双|偶/.test(raw);
    var even = /双|偶/.test(raw) && !/单|奇/.test(raw);
    var weeks = [];
    raw.replace(/第|周|节|单|双|奇|偶|[()（）]/g, '')
      .split(/[,，、\s]+/)
      .forEach(function(part) {
        var match = part.match(/(\d+)\s*[-–~至]\s*(\d+)/);
        if (match) {
          for (var w = parseInt(match[1]); w <= parseInt(match[2]); w++) {
            weeks.push(w);
          }
        } else {
          var value = parseInt(part);
          if (!isNaN(value)) weeks.push(value);
        }
      });
    return weeks.filter(function(value, index, all) {
      if (value < 1 || value > 30 || all.indexOf(value) !== index) return false;
      if (odd) return value % 2 === 1;
      if (even) return value % 2 === 0;
      return true;
    }).sort(function(a, b) { return a - b; });
  }

  function parseSections(text) {
    var match = String(text || '').match(
        /第?\s*(\d+)\s*[-–~至]\s*(\d+)\s*节/);
    if (match) return [parseInt(match[1]), parseInt(match[2])];
    match = String(text || '').match(/第?\s*(\d+)\s*节/);
    return match ? [parseInt(match[1]), parseInt(match[1])] : [];
  }

  function parseDay(text) {
    var value = parseInt(text);
    if (!isNaN(value)) {
      if (value === 0) return 1;
      if (value >= 1 && value <= 7) return value;
    }
    var match = String(text || '').match(
        /周([一二三四五六日天])|星期([一二三四五六日天])/);
    return match ? dayMap[match[1] || match[2]] : 0;
  }

  function parseCellText(text) {
    var lines = String(text || '').replace(/\u00a0/g, ' ')
      .split(/[\n\r]+/)
      .map(function(line) { return line.trim(); })
      .filter(Boolean);
    if (lines.length === 0) {
      return {name:'', teacher:null, location:null, weeks:[]};
    }

    var name = '';
    var teacher = null;
    var location = null;
    var weeks = [];
    var other = [];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (/\d+.*周|单周|双周|奇周|偶周/.test(line)) {
        weeks = parseWeeks(line);
      } else if (/^(任课)?教师[：:]/.test(line)) {
        teacher = line.replace(/^(任课)?教师[：:]\s*/, '') || null;
      } else if (/^(上课)?(地点|教室)[：:]/.test(line)) {
        location = line.replace(/^(上课)?(地点|教室)[：:]\s*/, '') || null;
      } else if (!name && !/^第?\d+.*节$/.test(line)) {
        name = line;
      } else if (!/^第?\d+.*节$/.test(line)) {
        other.push(line);
      }
    }
    if (!teacher && other.length > 0 &&
        other[0].length >= 2 && other[0].length <= 16) {
      teacher = other.shift();
    }
    if (!location && other.length > 0) location = other.shift();
    name = name.replace(/\([^)]*\)\s*$/g, '')
      .replace(/（[^）]*）\s*$/g, '').trim();
    return {name:name, teacher:teacher, location:location, weeks:weeks};
  }

  function add(parsed, day, start, end) {
    if (!parsed.name || parsed.name.length < 2 || parsed.name.length > 80) return;
    if (day < 1 || day > 7 || start < 1 || start > 20) return;
    if (end < start) end = start;
    if (end > 20) end = 20;
    var key = parsed.name + '|' + day + '|' + start + '|' + end + '|' +
        (parsed.location || '') + '|' + parsed.weeks.join(',');
    if (seen[key]) return;
    seen[key] = true;
    results.push({
      name: parsed.name,
      teacher: parsed.teacher || null,
      location: parsed.location || null,
      dayOfWeek: day,
      startSection: start,
      endSection: end,
      weeks: parsed.weeks
    });
  }

  function findTable(doc) {
    if (!doc || !doc.querySelector) return null;
    var table = doc.querySelector('#kbTable, .kb-table, #wdkbTable, ' +
        'table.kbTable, .el-table__body, #xsKbTable, ' +
        '[data-course-table], [class*="schedule-table"]');
    if (table) return table;
    var tables = doc.querySelectorAll ? doc.querySelectorAll('table') : [];
    var maxCells = 0;
    for (var i = 0; i < tables.length; i++) {
      var count = tables[i].querySelectorAll('td').length;
      if (count > maxCells && count >= 7) {
        maxCells = count;
        table = tables[i];
      }
    }
    return table;
  }

  function parseTable(table) {
    var rows = table.querySelectorAll('tbody tr, tr');

    // 新版页面：星期和节次通常位于 row/cell 的 data 属性。
    for (var r = 0; r < rows.length; r++) {
      var row = rows[r];
      var cells = row.querySelectorAll('td, [data-begin-unit], ' +
          '[data-start-section]');
      for (var c = 0; c < cells.length; c++) {
        var cell = cells[c];
        var day = parseDay(attr(cell, ['data-week', 'data-day', 'data-weekday']) ||
            attr(row, ['data-week', 'data-day', 'data-weekday']));
        var start = parseInt(attr(cell, ['data-begin-unit', 'data-start-section',
            'data-section-start']) || attr(row, ['data-begin-unit',
            'data-start-section', 'data-section-start']));
        var end = parseInt(attr(cell, ['data-end-unit', 'data-end-section',
            'data-section-end']) || attr(row, ['data-end-unit',
            'data-end-section', 'data-section-end']));
        var text = (cell.innerText || cell.textContent || '').trim();
        var sectionPair = parseSections(
            attr(cell, ['data-section', 'data-sections']) || text);
        if (isNaN(start) && sectionPair.length > 0) start = sectionPair[0];
        if (isNaN(end) && sectionPair.length > 0) end = sectionPair[1];
        if (!day || isNaN(start) || !text) continue;
        if (isNaN(end)) end = start;
        add(parseCellText(text), day, start, end);
      }
    }
    if (results.length > 0) return;

    // 传统页面：首列为节次，后续七列对应周一至周日。
    var tableRows = table.querySelectorAll('tr');
    if (tableRows.length < 2) return;
    var dayColumn = 1;
    var header = tableRows[0].querySelectorAll('th, td');
    for (var h = 0; h < header.length; h++) {
      if (/周[一二三四五六日天]|星期[一二三四五六日天]/
          .test((header[h].textContent || '').trim())) {
        dayColumn = h;
        break;
      }
    }
    for (var tr = 1; tr < tableRows.length; tr++) {
      var traditionalCells = tableRows[tr].querySelectorAll('td');
      if (traditionalCells.length < 2) continue;
      var section = parseInt((traditionalCells[0].textContent || '').trim()) || tr;
      for (var col = dayColumn;
          col < traditionalCells.length && col < dayColumn + 7; col++) {
        var traditionalCell = traditionalCells[col];
        var cellText = (traditionalCell.innerText ||
            traditionalCell.textContent || '').trim();
        if (cellText.length < 2) continue;
        var rowSpan = parseInt(attr(traditionalCell, ['rowspan'])) || 1;
        add(parseCellText(cellText), col - dayColumn + 1,
            section, section + rowSpan - 1);
      }
    }
  }

  // 主文档和同源 iframe 都参与解析。
  var docs = [document];
  var frames = document.querySelectorAll
      ? document.querySelectorAll('frame, iframe') : [];
  for (var f = 0; f < frames.length; f++) {
    try {
      if (frames[f].contentDocument) docs.push(frames[f].contentDocument);
    } catch (_) {}
  }
  for (var d = 0; d < docs.length; d++) {
    var table = findTable(docs[d]);
    if (table) parseTable(table);
  }
  if (results.length > 0) return JSON.stringify(results);

  // 页面已经出现课表容器但课程仍在异步渲染时，通知宿主稍后重试。
  for (var p = 0; p < docs.length; p++) {
    if (findTable(docs[p])) return JSON.stringify({__pending:true});
  }

  // 官方指引中的入口名称：公共查询 / 网上选课 → 课程安排明细。
  for (var n = 0; n < docs.length; n++) {
    var links = docs[n].querySelectorAll
        ? docs[n].querySelectorAll('a, [role="menuitem"], .menu-item, .el-menu-item')
        : [];
    for (var l = 0; l < links.length; l++) {
      var text = ((links[l].textContent || '') + ' ' +
          (attr(links[l], ['title']) || '')).trim();
      var href = attr(links[l], ['href']);
      if (/课程安排明细|学生个人课表|个人课表|我的课表/.test(text) ||
          /xskbcx|kbcx|course.?schedule|course.?arrange/i.test(href)) {
        try { links[l].click(); } catch (_) {}
        return JSON.stringify({__nav:true});
      }
    }
  }

  return JSON.stringify([]);
})();
''';
}
