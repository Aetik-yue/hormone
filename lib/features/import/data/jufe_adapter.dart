import 'school_adapter.dart';

/// 江西财经大学（青果教务 KINGOSOFT）适配器。
///
/// 教务系统：xk.jxufe.cn（青果软件 KINGOSOFT 高校智慧校园教学管理服务平台）
/// 登录页支持账号登录 + 扫码登录，正常情况免验证码。
/// 课表页通常为 /student/course/schedule 或 /xsjxgl/xskbcx。
///
/// 注意：由于没有实际账号验证，extractJs 基于青果教务通用 DOM 结构编写，
/// 首次实测后可能需要微调选择器。
class JufeAdapter extends SchoolAdapter {
  @override
  String get schoolName => '江西财经大学';

  @override
  String get loginUrl => 'http://xk.jxufe.cn/';

  @override
  String get scheduleUrl =>
      'http://xk.jxufe.cn/student/course/schedule';

  @override
  bool isSchedulePage(String currentUrl) {
    return currentUrl.contains('/course/schedule') ||
        currentUrl.contains('/xsjxgl/xskbcx') ||
        currentUrl.contains('/student/course');
  }

  @override
  String get extractJs => r'''
(function() {
  var results = [];

  // 青果教务课表常见容器：#kbTable, .kb-table, #wdkbTable, table.kbTable
  var table = document.querySelector('#kbTable') ||
              document.querySelector('.kb-table') ||
              document.querySelector('#wdkbTable') ||
              document.querySelector('table.kbTable') ||
              document.querySelector('.el-table__body');

  if (!table) {
    // 尝试找任何包含课程信息的大表格
    var tables = document.querySelectorAll('table');
    for (var i = 0; i < tables.length; i++) {
      if (tables[i].querySelectorAll('td').length > 20) {
        table = tables[i];
        break;
      }
    }
  }
  if (!table) return JSON.stringify([]);

  // 方式一：data 属性模式（新版青果/金智通用）
  var rows = table.querySelectorAll('tbody tr, tr');
  var hasDataAttrs = false;
  rows.forEach(function(row) {
    if (row.getAttribute('data-week')) hasDataAttrs = true;
  });

  if (hasDataAttrs) {
    rows.forEach(function(row) {
      var day = parseInt(row.getAttribute('data-week') || '0');
      if (day < 1 || day > 7) return;
      var cells = row.querySelectorAll('td');
      cells.forEach(function(cell) {
        var divs = cell.querySelectorAll('div, span, p');
        if (divs.length < 2) return;
        var beginUnit = parseInt(cell.getAttribute('data-begin-unit') ||
                                 row.getAttribute('data-begin-unit') || '0');
        var endUnit = parseInt(cell.getAttribute('data-end-unit') ||
                               row.getAttribute('data-end-unit') || '0');
        if (beginUnit < 1) return;
        if (endUnit < beginUnit) endUnit = beginUnit;

        var weeksText = divs[0] ? divs[0].textContent.trim() : '';
        var name = divs[1] ? divs[1].textContent.trim() : '';
        var teacher = divs[2] ? divs[2].textContent.trim() : '';
        var location = divs[3] ? divs[3].textContent.trim() : '';
        if (!name) return;
        name = name.replace(/\([^)]*\)$/g, '').trim();

        results.push({
          name: name,
          teacher: teacher || null,
          location: location || null,
          dayOfWeek: day,
          startSection: beginUnit,
          endSection: endUnit,
          weeks: parseWeeks(weeksText)
        });
      });
    });
  } else {
    // 方式二：传统表格模式（行=节次，列=星期）
    // 青果老版：第一列是节次，后续7列是周一到周日
    var allRows = table.querySelectorAll('tr');
    for (var r = 1; r < allRows.length; r++) {
      var cells = allRows[r].querySelectorAll('td');
      if (cells.length < 2) continue;
      // 第一列通常是节次编号
      var sectionText = cells[0] ? cells[0].textContent.trim() : '';
      var sectionNum = parseInt(sectionText) || r;

      for (var c = 1; c < cells.length && c <= 7; c++) {
        var cellText = cells[c] ? cells[c].textContent.trim() : '';
        if (!cellText || cellText === '' || cellText === '\u00a0') continue;

        // 尝试从单元格文本中解析课程信息
        // 常见格式："课程名\n教师\n教室\n1-16周"
        var lines = cellText.split(/[\n\r]+/).map(function(s) { return s.trim(); }).filter(Boolean);
        if (lines.length < 1) continue;

        var cName = lines[0] || '';
        var cTeacher = lines.length > 1 ? lines[1] : null;
        var cLocation = lines.length > 2 ? lines[2] : null;
        var cWeeksText = lines.length > 3 ? lines[lines.length - 1] : '';

        // 如果只有一行，尝试用分隔符拆分
        if (lines.length === 1) {
          var parts = cellText.split(/[,，;；]/);
          cName = parts[0] || '';
          cTeacher = parts.length > 1 ? parts[1] : null;
          cLocation = parts.length > 2 ? parts[2] : null;
        }

        if (!cName) continue;
        cName = cName.replace(/\([^)]*\)$/g, '').trim();

        results.push({
          name: cName,
          teacher: cTeacher,
          location: cLocation,
          dayOfWeek: c,
          startSection: sectionNum,
          endSection: sectionNum,
          weeks: parseWeeks(cWeeksText)
        });
      }
    }
  }

  // 去重
  var seen = {};
  var unique = [];
  results.forEach(function(c) {
    var key = c.name + '|' + c.dayOfWeek + '|' + c.startSection + '|' + c.weeks.join(',');
    if (!seen[key]) { seen[key] = true; unique.push(c); }
  });
  return JSON.stringify(unique);

  function parseWeeks(text) {
    if (!text) return [];
    var weeks = [];
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
