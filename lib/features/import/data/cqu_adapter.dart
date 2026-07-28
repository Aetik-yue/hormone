import 'school_adapter.dart';

/// 重庆大学（金智教务 XCampus）适配器。
///
/// 教务系统：my.cqu.edu.cn
/// 课表页 URL：/workspace/curriculum
/// 页面为 div 网格布局，每个课程卡片文本格式：
///   [课程编号]\n[周次周] [节次节] 教室\n本科 - 课程名
/// 星期信息来自网格列位置或父级 data 属性。
class CquAdapter extends SchoolAdapter {
  @override
  String get schoolName => '重庆大学';

  @override
  String get loginUrl => 'https://my.cqu.edu.cn/workspace/home';

  @override
  String get scheduleUrl => 'https://my.cqu.edu.cn/workspace/curriculum';

  @override
  bool isSchedulePage(String currentUrl) {
    return currentUrl.contains('/workspace/curriculum');
  }

  @override
  String get extractJs => r'''
(function() {
  var results = [];
  var dayMap = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':7,'天':7};
  var _dayHeaders = null; // 日期表头缓存（闭包变量，每次提取刷新）

  // ═══ 策略1：找所有包含课程编号+周次信息的元素 ═══
  // 课程卡片文本特征：包含 [数字-数字] 和 X周 和 X节
  var allEls = document.body.querySelectorAll('*');
  var candidates = [];

  for (var i = 0; i < allEls.length; i++) {
    var el = allEls[i];
    // 只看直接文本内容较长的元素（课程卡片）
    var t = (el.innerText || el.textContent || '').trim();
    if (t.length < 10 || t.length > 500) continue;
    // 必须包含课程编号格式 [数字-数字]
    if (!/\[\d{4,}-\d{2,}/.test(t)) continue;
    // 必须包含周次信息
    if (!/\d+.*周/.test(t)) continue;
    // 必须包含节次信息
    if (!/\d+.*节/.test(t)) continue;
    // 排除包含多个课程编号的父容器（保留最内层匹配元素）
    var codeMatches = t.match(/\[\d{4,}-\d{2,}[^\]]*\]/g);
    if (codeMatches && codeMatches.length > 1) continue;
    candidates.push(el);
  }

  // 去重：如果一个元素是另一个候选元素的子元素，移除子元素
  var filtered = [];
  for (var i = 0; i < candidates.length; i++) {
    var isChild = false;
    for (var j = 0; j < candidates.length; j++) {
      if (i !== j && candidates[j].contains(candidates[i]) && candidates[j] !== candidates[i]) {
        isChild = true;
        break;
      }
    }
    if (!isChild) {
      filtered.push(candidates[i]);
    }
  }

  // 对每个候选元素解析课程信息
  var seen = {};
  filtered.forEach(function(el) {
    var text = (el.innerText || el.textContent || '').trim();

    // 解析课程编号
    var codeMatch = text.match(/\[(\d{4,}-\d{2,}(?:-\w+)?)\]/);
    if (!codeMatch) return;
    var code = codeMatch[1];

    // 解析周次：支持 [1-7周], [1-3,5-14周], [5、7-9、11-15周] 等
    var weekMatch = text.match(/\[((?:\d+(?:\s*[-–~]\s*\d+)?)(?:\s*[,，、]\s*\d+(?:\s*[-–~]\s*\d+)?)*)\s*周\]/);
    var weeks = [];
    if (weekMatch) {
      weeks = parseRange(weekMatch[1]);
    }

    // 解析节次：[1-2节], [3-4节], [6-7节]
    var secMatch = text.match(/\[(\d+(?:\s*[-–~]\s*\d+)?)\s*节\]/);
    var startSec = 1, endSec = 1;
    if (secMatch) {
      var secs = parseRange(secMatch[1]);
      if (secs.length > 0) {
        startSec = secs[0];
        endSec = secs[secs.length - 1];
      }
    }

    // 解析教室：节次后面、换行前的文本
    var locMatch = text.match(/\d+\s*节\]\s*([^\n\[]+)/);
    var location = locMatch ? locMatch[1].trim() : null;
    // 清理教室名（去掉尾部空格和特殊字符）
    if (location && location.length > 30) location = null;

    // 解析课程名：「本科 - XXX」或「研究生 - XXX」
    var nameMatch = text.match(/(?:本科|研究生|专科)\s*[-–—]\s*([^\n\[]+)/);
    var name = '';
    if (nameMatch) {
      name = nameMatch[1].trim();
    } else {
      // 兜底：取最后一个非编号、非周次节次的行
      var lines = text.split(/\n/).map(function(l){return l.trim();}).filter(Boolean);
      for (var k = lines.length - 1; k >= 0; k--) {
        var l = lines[k];
        if (/^\[/.test(l)) continue;
        if (/\d+\s*[-–~]\s*\d+\s*[周节]/.test(l)) continue;
        if (/^还有\d+条/.test(l)) continue;
        if (l === '收起' || l === '展开') continue;
        if (l.length >= 2 && l.length <= 40) {
          name = l.replace(/^(本科|研究生|专科)\s*[-–—]\s*/, '');
          break;
        }
      }
    }
    if (!name || name.length < 2) return;
    // 去掉课程名中的括号备注（如 "体育自选项目（花样跳绳3）" 保留，但 "高等数学(2024秋)" 去掉）
    name = name.replace(/\(\d{4}[^\)]*\)\s*$/, '').trim();

    // 推断星期
    var day = findDay(el);

    // 去重 key（含教室，避免同名同学期同学时不同教室的课程被合并）
    var key = name + '|' + day + '|' + startSec + '|' + (location || '') + '|' + weeks.join(',');
    if (seen[key]) return;
    seen[key] = true;

    results.push({
      name: name,
      teacher: null,
      location: location,
      dayOfWeek: day,
      startSection: startSec,
      endSection: endSec,
      weeks: weeks
    });
  });

  // ═══ 策略2：纯文本逐行解析（兜底）═══
  if (results.length === 0) {
    var bodyText = document.body ? document.body.innerText : '';
    var lines = bodyText.split(/\n/).map(function(l){return l.trim();}).filter(Boolean);
    var currentDay = 1;

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];

      // 检测星期标记
      var dm = line.match(/^周([一二三四五六日天])$/) || line.match(/^星期([一二三四五六日天])$/);
      if (dm && dayMap[dm[1]]) { currentDay = dayMap[dm[1]]; continue; }

      // 匹配课程编号行
      if (!/^\[\d{4,}-\d{2,}/.test(line)) continue;

      // 下一行：周次 + 节次 + 教室
      if (i + 1 >= lines.length) continue;
      var infoLine = lines[i + 1];
      var wm = infoLine.match(/\[((?:\d+(?:\s*[-–~]\s*\d+)?)(?:\s*[,，]\s*\d+(?:\s*[-–~]\s*\d+)?)*)\s*周\]/);
      var sm = infoLine.match(/\[(\d+(?:\s*[-–~]\s*\d+)?)\s*节\]/);
      if (!wm || !sm) continue;

      // 再下一行：课程名
      if (i + 2 >= lines.length) continue;
      var nameLine = lines[i + 2];
      var nm = nameLine.replace(/^(本科|研究生|专科)\s*[-–—]\s*/, '').trim();
      if (!nm || nm.length < 2 || nm.length > 50) continue;

      var locM = infoLine.match(/\d+\s*节\]\s*([^\n\[]+)/);
      var loc = locM ? locM[1].trim() : null;

      var wks = parseRange(wm[1]);
      var scs = parseRange(sm[1]);

      var key2 = nm + '|' + currentDay + '|' + (scs[0]||1) + '|' + wks.join(',');
      if (seen[key2]) { i += 2; continue; }
      seen[key2] = true;

      results.push({
        name: nm,
        teacher: null,
        location: loc,
        dayOfWeek: currentDay,
        startSection: scs.length > 0 ? scs[0] : 1,
        endSection: scs.length > 0 ? scs[scs.length - 1] : 1,
        weeks: wks
      });
      i += 2;
    }
  }

  return JSON.stringify(results);

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
    // 去重排序
    var unique = [];
    var seenN = {};
    for (var i = 0; i < nums.length; i++) {
      if (!seenN[nums[i]]) { seenN[nums[i]] = true; unique.push(nums[i]); }
    }
    unique.sort(function(a,b){return a-b;});
    return unique;
  }

  function findDay(el) {
    // 方法1：向上找 data-day / data-weekday 属性（仅这两个属性表示星期）
    var node = el;
    for (var d = 0; d < 12 && node; d++) {
      var val = node.getAttribute ? node.getAttribute('data-day') : null;
      if (val) {
        var n = parseInt(val);
        if (n >= 1 && n <= 7) return n;
      }
      val = node.getAttribute ? node.getAttribute('data-weekday') : null;
      if (val) {
        var n = parseInt(val);
        if (n >= 1 && n <= 7) return n;
        var dm2 = val.match(/([一二三四五六日天])/);
        if (dm2 && dayMap[dm2[1]]) return dayMap[dm2[1]];
      }
      node = node.parentElement;
    }

    // 方法2：通过 getBoundingClientRect 匹配日期表头的 x 坐标
    if (!_dayHeaders) {
      _dayHeaders = [];
      // 优先检查常见表头元素，避免全量扫描
      var headerEls = document.querySelectorAll(
        'th, [class*="week"], [class*="day"], [class*="header"], [class*="head"]'
      );
      if (headerEls.length === 0) {
        headerEls = document.body.querySelectorAll('*');
      }
      for (var i = 0; i < headerEls.length; i++) {
        var h = headerEls[i];
        // 只取叶子节点或只有一个文本子节点的元素，避免重复
        if (h.children.length > 0) continue;
        var t = (h.textContent || '').trim();
        var dm = t.match(/^周([一二三四五六日天])$/) || t.match(/^星期([一二三四五六日天])$/);
        if (dm && dayMap[dm[1]]) {
          var rect = h.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            var x = rect.left + rect.width / 2;
            // 去重：避免父子元素都匹配时重复记录同一位置
            var isDup = false;
            for (var j = 0; j < _dayHeaders.length; j++) {
              if (Math.abs(_dayHeaders[j].x - x) < 2) { isDup = true; break; }
            }
            if (!isDup) {
              _dayHeaders.push({ day: dayMap[dm[1]], x: x });
            }
          }
        }
      }
      _dayHeaders.sort(function(a, b) { return a.x - b.x; });
    }

    if (_dayHeaders.length >= 1) {
      var rect = el.getBoundingClientRect();
      // 隐藏元素（display:none 等）返回全零 DOMRect，无法定位
      if (rect.width === 0 || rect.height === 0) return 0;
      var cardX = rect.left + rect.width / 2;
      // 匹配到最近的表头
      var bestDay = 0, bestDist = Infinity;
      for (var i = 0; i < _dayHeaders.length; i++) {
        var dist = Math.abs(_dayHeaders[i].x - cardX);
        if (dist < bestDist) { bestDist = dist; bestDay = _dayHeaders[i].day; }
      }
      if (bestDay > 0) return bestDay;
    }

    return 0; // 未知（无法从 DOM 推断星期）
  }
})();
''';
}
