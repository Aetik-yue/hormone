import 'school_adapter.dart';

/// 通用教务系统适配器。
///
/// 适用于未单独适配的学校：用户自行输入教务系统 URL，适配器尝试多种
/// 常见教务系统（金智、青果、URP）的 DOM 结构进行提取。
///
/// 提取策略按优先级依次尝试：
/// 1. data-属性模式（金智/青果新版通用）
/// 2. 传统课表表格（行=节次，列=星期）
/// 3. 纯文本正则兜底
class GenericAdapter extends SchoolAdapter {
  @override
  String get schoolName => '通用教务（自定义URL）';

  @override
  String get loginUrl => _url;

  @override
  String get scheduleUrl => _url;

  @override
  bool isSchedulePage(String currentUrl) {
    // 通用适配器：任何页面都允许尝试提取（用户手动触发）
    return true;
  }

  final String _url;

  GenericAdapter({required String url}) : _url = url;

  @override
  AdapterSupportLevel get supportLevel => AdapterSupportLevel.generic;

  @override
  String get systemName => '通用抓取';

  @override
  String get extractJs => commonExtractJs;

  /// 可供按学校配置的适配器复用的通用 DOM 抽取脚本。
  static const String commonExtractJs = r'''
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
              document.querySelector('#xsKbTable') ||
              document.querySelector('.kbTable') ||
              document.querySelector('[class*="schedule"]') ||
              document.querySelector('[class*="curriculum"]') ||
              document.querySelector('[id*="kbTable"]');

  if (!table) {
    // 兜底：找 td 最多的 table
    var tables = document.querySelectorAll('table');
    var maxTd = 0;
    for (var i = 0; i < tables.length; i++) {
      var tdCount = tables[i].querySelectorAll('td').length;
      if (tdCount > maxTd) { maxTd = tdCount; table = tables[i]; }
    }
    // 仍然没有 table，尝试 div 网格
    if (!table || maxTd < 10) {
      table = document.querySelector('.course-grid') ||
              document.querySelector('[class*="course-grid"]') ||
              document.body;
    }
  }

  // ═══ 策略1：data-属性模式（金智/青果新版） ═══
  var rows = table.querySelectorAll('tbody tr, tr');
  var hasDataAttrs = false;
  rows.forEach(function(row) {
    if (row.getAttribute('data-week') || row.getAttribute('data-day') ||
        row.getAttribute('data-weekday') ||
        row.querySelector('[data-week], [data-day], [data-weekday], [data-begin-unit]')) {
      hasDataAttrs = true;
    }
  });

  if (hasDataAttrs) {
    rows.forEach(function(row) {
      var cells = row.querySelectorAll('td');
      cells.forEach(function(cell) {
        var rawDay = cell.getAttribute('data-week') ||
                     cell.getAttribute('data-day') ||
                     cell.getAttribute('data-weekday') ||
                     row.getAttribute('data-week') ||
                     row.getAttribute('data-day') ||
                     row.getAttribute('data-weekday') || '';
        var day = parseDay(rawDay);
        if (day < 1 || day > 7) return;
        var beginUnit = parseInt(cell.getAttribute('data-begin-unit') ||
                                 cell.getAttribute('data-start-section') ||
                                 row.getAttribute('data-begin-unit') || '0');
        var endUnit = parseInt(cell.getAttribute('data-end-unit') ||
                               cell.getAttribute('data-end-section') ||
                               row.getAttribute('data-end-unit') || '0');
        if (beginUnit < 1) return;
        if (endUnit < beginUnit) endUnit = beginUnit;

        // 用 cell.innerText 获取完整文本，再按行拆分解析
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
  }

  // ═══ 策略2：传统表格（行=节次，列=星期） ═══
  if (results.length === 0) {
    var grid = parseTableToGrid(table);
    var headerIndex = 0;
    var dayColumns = {};

    // 在前几行寻找真实星期表头，兼容标题行和多级表头。
    for (var hr = 0; hr < grid.length && hr < 6; hr++) {
      if (!grid[hr]) continue;
      var foundDays = 0;
      for (var hc = 0; hc < grid[hr].length; hc++) {
        var headerCell = grid[hr][hc];
        if (!headerCell) continue;
        var headerDay = parseDay(headerCell.text);
        if (headerDay > 0) {
          dayColumns[hc] = headerDay;
          foundDays++;
        }
      }
      if (foundDays >= 5) {
        headerIndex = hr;
        break;
      }
    }

    // 无可识别表头时采用最常见的第 2-8 逻辑列。
    if (Object.keys(dayColumns).length === 0) {
      for (var dc = 1; dc <= 7; dc++) dayColumns[dc] = dc;
    }

    for (var r = headerIndex + 1; r < grid.length; r++) {
      if (!grid[r]) continue;
      var sectionCell = grid[r][0];
      var sectionValues = parseRange(sectionCell ? sectionCell.text : '');
      var sectionNum = sectionValues.length > 0 ? sectionValues[0] : r - headerIndex;

      var columnKeys = Object.keys(dayColumns);
      for (var ci = 0; ci < columnKeys.length; ci++) {
        var c = parseInt(columnKeys[ci]);
        var cell = grid[r][c];
        if (!cell || !cell.isOrigin) continue;
        var dayIdx = dayColumns[c];
        var cellText = cell.text;
        if (!cellText || cellText === ' ' || cellText.length < 2) continue;

        var parsed = parseCellText(cellText);
        if (!parsed.name) continue;

        var endSection = sectionValues.length > 1
            ? sectionValues[sectionValues.length - 1]
            : sectionNum + cell.rowspan - 1;

        var key = parsed.name + '|' + dayIdx + '|' + sectionNum + '|' + (parsed.location || '') + '|' + parsed.weeks.join(',');
        if (seen[key]) continue;
        seen[key] = true;

        results.push({
          name: parsed.name,
          teacher: parsed.teacher || null,
          location: parsed.location || null,
          dayOfWeek: dayIdx,
          startSection: sectionNum,
          endSection: endSection,
          weeks: parsed.weeks
        });
      }
    }
  }

  // ═══ 策略3：纯文本正则兜底 ═══
  if (results.length === 0) {
    var bodyText = document.body ? document.body.innerText : '';
    var lines = bodyText.split(/\n/).map(function(l) { return l.trim(); }).filter(Boolean);
    var currentDay = 0;

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];

      // 检测星期标记
      var dm = line.match(/^周([一二三四五六日天])$/) || line.match(/^星期([一二三四五六日天])$/);
      if (dm && dayMap[dm[1]]) { currentDay = dayMap[dm[1]]; continue; }
      if (currentDay === 0) currentDay = 1;

      // 尝试从行中提取课程名+周次+节次
      // 常见格式：课程名 1-16周 1-2节 教室
      var courseMatch = line.match(/^(.{2,20}?)\s+([\d,\-–~、单双]+)\s*周\s*([\d,\-–~、]+)\s*节/);
      if (courseMatch) {
        var cname = courseMatch[1].trim();
        var wks = parseWeeks(courseMatch[2] + '周');
        var secs = parseRange(courseMatch[3]);
        var startSec = secs.length > 0 ? secs[0] : 1;
        var endSec = secs.length > 0 ? secs[secs.length - 1] : 1;

        // 教室：节次后面的文本
        var locMatch = line.match(/节\s*(.+)$/);
        var loc = locMatch ? locMatch[1].trim() : null;
        if (loc && loc.length > 30) loc = null;

        var key = cname + '|' + currentDay + '|' + startSec + '|' + (loc || '') + '|' + wks.join(',');
        if (seen[key]) continue;
        seen[key] = true;

        results.push({
          name: cname,
          teacher: null,
          location: loc,
          dayOfWeek: currentDay,
          startSection: startSec,
          endSection: endSec,
          weeks: wks
        });
      }
    }
  }

  return JSON.stringify(results);

  // ═══ 工具函数 ═══

  function parseDay(value) {
    var text = String(value || '').trim();
    var match = text.match(/(?:周|星期)?([一二三四五六日天])/);
    if (match && dayMap[match[1]]) return dayMap[match[1]];
    var number = parseInt(text);
    if (number >= 1 && number <= 7) return number;
    // 明确写出 0 时才按 0-indexed 处理，避免空字符串被误判为周一。
    if (text !== '' && number >= 0 && number <= 6) return number + 1;
    return 0;
  }

  function parseTableToGrid(tableNode) {
    if (!tableNode || !tableNode.querySelectorAll) return [];
    var tableRows = tableNode.querySelectorAll('tr');
    var grid = [];
    for (var rowIndex = 0; rowIndex < tableRows.length; rowIndex++) {
      var tableCells = tableRows[rowIndex].querySelectorAll('td, th');
      var columnIndex = 0;
      if (!grid[rowIndex]) grid[rowIndex] = [];
      for (var cellIndex = 0; cellIndex < tableCells.length; cellIndex++) {
        while (grid[rowIndex][columnIndex] !== undefined) columnIndex++;
        var node = tableCells[cellIndex];
        var rowspan = parseInt(node.getAttribute('rowspan')) || 1;
        var colspan = parseInt(node.getAttribute('colspan')) || 1;
        var value = {
          text: (node.innerText || node.textContent || '').replace(/\u00a0/g, ' ').trim(),
          html: node.innerHTML || '',
          rowspan: rowspan,
          colspan: colspan,
          isOrigin: true
        };
        for (var rr = 0; rr < rowspan; rr++) {
          if (!grid[rowIndex + rr]) grid[rowIndex + rr] = [];
          for (var cc = 0; cc < colspan; cc++) {
            grid[rowIndex + rr][columnIndex + cc] = rr === 0 && cc === 0
              ? value
              : {
                  text: value.text,
                  html: value.html,
                  rowspan: rowspan,
                  colspan: colspan,
                  isOrigin: false
                };
          }
        }
        columnIndex += colspan;
      }
    }
    return grid;
  }

  function parseCellText(text) {
    // 尝试从单元格文本中解析课程信息
    // 常见格式：
    //   "课程名\n教师\n教室\n1-16周"
    //   "课程名\n1-16周 1-2节\n教师 教室"
    //   "课程名 1-16周 1-2节 教室"
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

    // 清理课程名中的括号备注
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

  function parseRange(text) {
    if (!text) return [];
    var nums = [];
    var parts = text.split(/[,，、\s]+/);
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim();
      if (!p) continue;
      var m = p.match(/(\d+)\s*[-–~]\s*(\d+)/);
      if (m) {
        var a = parseInt(m[1]), b = parseInt(m[2]);
        for (var j = a; j <= b; j++) nums.push(j);
      } else {
        var n = parseInt(p);
        if (!isNaN(n)) nums.push(n);
      }
    }
    var unique = [];
    var seenN = {};
    for (var i = 0; i < nums.length; i++) {
      if (!seenN[nums[i]]) { seenN[nums[i]] = true; unique.push(nums[i]); }
    }
    unique.sort(function(a, b) { return a - b; });
    return unique;
  }
})();
''';
}
