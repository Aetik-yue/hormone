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
    // 也支持 单周（奇数周）和 双周（偶数周）
    var weeks = [];
    if (/单周/.test(text)) {
      for (var i = 1; i <= 20; i += 2) weeks.push(i);
    } else if (/双周/.test(text)) {
      for (var i = 2; i <= 20; i += 2) weeks.push(i);
    } else {
      var weekMatch = text.match(/\[((?:\d+(?:\s*[-–~]\s*\d+)?)(?:\s*[,，、]\s*\d+(?:\s*[-–~]\s*\d+)?)*)\s*周\]/);
      if (weekMatch) {
        weeks = parseRange(weekMatch[1]);
      }
    }

    // 解析节次：[1-2节], [3-4节], [1-2,3-4节], [1、3节] 等
    var secMatch = text.match(/\[((?:\d+(?:\s*[-–~]\s*\d+)?)(?:\s*[,，、]\s*\d+(?:\s*[-–~]\s*\d+)?)*)\s*节\]/);
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
      var wm = infoLine.match(/\[((?:\d+(?:\s*[-–~]\s*\d+)?)(?:\s*[,，、]\s*\d+(?:\s*[-–~]\s*\d+)?)*)\s*周\]/);
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
    // ── 方法1：向上找 data-day / data-weekday 属性 ──
    // 不再直接 return，记录结果供后续与方法2交叉验证。
    var method1Result = 0, method1Depth = 99;
    var node = el;
    for (var d = 0; d < 12 && node; d++) {
      var val = node.getAttribute ? node.getAttribute('data-day') : null;
      if (val) {
        var n = parseInt(val);
        if (n >= 1 && n <= 7) { method1Result = n; method1Depth = d; break; }
        // 兼容 0-indexed（0=周一 … 6=周日）
        if (n >= 0 && n <= 6) { method1Result = n + 1; method1Depth = d; break; }
      }
      val = node.getAttribute ? node.getAttribute('data-weekday') : null;
      if (val) {
        var n = parseInt(val);
        if (n >= 1 && n <= 7) { method1Result = n; method1Depth = d; break; }
        var dm2 = val.match(/([一二三四五六日天])/);
        if (dm2 && dayMap[dm2[1]]) { method1Result = dayMap[dm2[1]]; method1Depth = d; break; }
      }
      node = node.parentElement;
    }

    // ── 方法2：通过 getBoundingClientRect 匹配日期表头的 x 坐标 ──
    if (!_dayHeaders) {
      _dayHeaders = [];
      var vw = window.innerWidth || 9999;
      // 全量扫描所有元素，避免 class 选择器找到干扰项后不兜底
      var allEls = document.body.querySelectorAll('*');
      for (var i = 0; i < allEls.length; i++) {
        var h = allEls[i];
        var t = (h.textContent || '').trim();
        // 用文本长度限制排除大段文本容器（替代叶子节点过滤）
        if (t.length === 0 || t.length > 20) continue;
        // 放宽正则：允许"周一 09/02"、"周一(开学)"等格式
        var dm = t.match(/^周([一二三四五六日天])/) || t.match(/^星期([一二三四五六日天])/);
        if (dm && dayMap[dm[1]]) {
          var rect = h.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            var x = rect.left + rect.width / 2;
            // 过滤屏外副本：CQU 页面存在一组定位在视口外的「周X」表头模板
            // （x 为负或远超视口宽度），不过滤会污染列宽与最近表头匹配，
            // 导致课程错配到相邻星期。
            if (x < 0 || x > vw + 2000) continue;
            // 去重：避免同一位置重复记录
            var isDup = false;
            for (var j = 0; j < _dayHeaders.length; j++) {
              if (Math.abs(_dayHeaders[j].x - x) < 2) { isDup = true; break; }
            }
            if (!isDup) {
              _dayHeaders.push({ day: dayMap[dm[1]], x: x, inferred: false });
            }
          }
        }
      }
      _dayHeaders.sort(function(a, b) { return a.x - b.x; });

      // ── 表头补全：用等距外推填补缺失的星期 ──
      // 某个星期的真实表头可能未被检测到（如「周一」表头被屏外模板遮蔽），
      // 此时按已检测表头的等距间距外推补齐 1..7，避免课程错配到相邻星期。
      if (_dayHeaders.length >= 2 && _dayHeaders.length < 7) {
        // 用相邻表头间距的中位数作为列宽（比首尾端点更抗离群点）
        var steps = [];
        for (var i = 1; i < _dayHeaders.length; i++) {
          steps.push(_dayHeaders[i].x - _dayHeaders[i - 1].x);
        }
        steps.sort(function(a, b) { return a - b; });
        var colWidth = steps[Math.floor(steps.length / 2)] || 100;
        var ref = _dayHeaders[0];
        var have = {};
        for (var i = 0; i < _dayHeaders.length; i++) have[_dayHeaders[i].day] = _dayHeaders[i].x;
        _dayHeaders = [];
        for (var d = 1; d <= 7; d++) {
          _dayHeaders.push({
            day: d,
            x: have[d] !== undefined ? have[d] : ref.x + (d - ref.day) * colWidth,
            inferred: have[d] === undefined
          });
        }
      }

      // 调试输出：表头检测结果
      console.log('[CQU] Day headers: ' + JSON.stringify(_dayHeaders.map(function(h) {
        return { day: h.day, x: Math.round(h.x), inferred: h.inferred };
      })));
    }

    // ── 位置匹配：找最近表头 ──
    var method2Result = 0, method2Dist = Infinity;
    if (_dayHeaders.length >= 1) {
      var rect = el.getBoundingClientRect();
      // 隐藏元素（display:none 等）返回全零 DOMRect，无法定位
      if (rect.width === 0 || rect.height === 0) return method1Result > 0 ? method1Result : 0;
      var cardX = rect.left + rect.width / 2;
      var colWidth = _dayHeaders.length > 1
          ? (_dayHeaders[_dayHeaders.length - 1].x - _dayHeaders[0].x) / (_dayHeaders.length - 1)
          : 100;
      var matchRadius = colWidth * 0.75;  // 提升半径，容忍更大偏移
      var bestDay = 0, bestDist = Infinity;
      for (var i = 0; i < _dayHeaders.length; i++) {
        var dist = Math.abs(_dayHeaders[i].x - cardX);
        if (dist < bestDist) { bestDist = dist; bestDay = _dayHeaders[i].day; }
      }
      method2Result = bestDay;
      method2Dist = bestDist;
    }

    // ── 交叉验证：综合两方法结果 ──
    if (method1Result > 0 && method2Result > 0) {
      if (method1Result === method2Result) {
        return method1Result;  // 一致，高置信度
      }
      // 不一致：根据置信度选择
      var withinRadius = method2Dist <= matchRadius;
      if (withinRadius && method1Depth >= 3) {
        // method2 在半径内且 method1 深度较浅（可能是远祖先的通用属性），优先 method2
        console.log('[CQU] Mismatch: m1=' + method1Result + '(depth=' + method1Depth + ') m2=' + method2Result + '(dist=' + Math.round(method2Dist) + ') → use m2');
        return method2Result;
      }
      // 默认优先 method1（DOM 属性通常更准确）
      console.log('[CQU] Mismatch: m1=' + method1Result + '(depth=' + method1Depth + ') m2=' + method2Result + '(dist=' + Math.round(method2Dist) + ') → use m1');
      return method1Result;
    }
    // 只有一个方法有结果，直接返回
    if (method1Result > 0) return method1Result;
    if (method2Result > 0) return method2Result;
    return 0; // 两方法都失败
  }
})();
''';
}
