/// 各学校脚本共用的周次语义；无范围的单双周须由宿主提供学期周数。
const schoolWeekParserJs = r'''
  function schoolInteger(value) {
    var raw = String(value == null ? '' : value).trim();
    return /^\d+$/.test(raw) && Number.isSafeInteger(Number(raw)) ? Number(raw) : NaN;
  }
  function schoolWeekNumbers(text, sections) {
    var raw = String(text == null ? '' : text).trim();
    var odd = /单|奇/.test(raw), even = /双|偶/.test(raw);
    // 保留无效标记供 Dart 逐条统计，不让前端解析静默丢课或只接受部分数字。
    if (!raw || (odd && even) || (sections && (odd || even))) return [null];
    // 通用单元格的周次行可能还带节次和教室，后者不属于周次内容。
    if (!sections) raw = raw.replace(/\s+\d[\d,，、\s\-–~至]*节.*$/, '');
    var cleaned = raw.replace(/第|周|节|单|双|奇|偶|[()（）\[\]{}|]/g, '')
        .replace(/\s*([-–~至])\s*/g, '$1').trim()
        .replace(/^[,，、\s]+|[,，、\s]+$/g, '');
    var values = [];
    if (!cleaned && !sections && (odd || even)) {
      if (typeof recessTotalWeeks !== 'number' || recessTotalWeeks < 1) return [null];
      for (var n = 1; n <= recessTotalWeeks; n++) values.push(n);
    } else {
      if (!cleaned) return [null];
      var parts = cleaned.split(/[,，、\s]+/);
      for (var i = 0; i < parts.length; i++) {
        var match = parts[i].match(/^(\d+)(?:[-–~至](\d+))?$/);
        if (!match) return [null];
        var a = Number(match[1]), b = match[2] ? Number(match[2]) : a;
        if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) || a < 1) return [null];
        if (b < a) return sections ? [a, b] : [null];
        for (var n = a; n <= b; n++) values.push(n);
      }
    }
    return values.filter(function(v, i, all) {
      return all.indexOf(v) === i && (!odd || v % 2 === 1) && (!even || v % 2 === 0);
    }).sort(function(a, b) { return a - b; });
  }
''';

/// 各学校提取脚本共用的 runtime。
///
/// 只放结构一致、可以逐字共享的机械步骤；各校的链接文字正则、href 正则、
/// 选择器、去重 key 公式和表格/单元格解析仍留在各自 adapter 里。所有标识符
/// 沿用 `school` 前缀，避免与脚本内部的局部变量重名。
const schoolExtractionRuntimeJs = schoolWeekParserJs + r'''
  // 星期文本 → 序号（1=周一 … 7=周日）。
  var schoolDayMap = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':7,'天':7};

  // 透传的周次/节次解析。节次必须排序去重：乱序输入（"5,1-2"）若不排序会
  // 导致 startSection > endSection，release 构建下（assert 关闭）带着负高度
  // 进课表布局直接崩溃。
  function schoolParseWeeks(text) {
    return schoolWeekNumbers(text);
  }
  function schoolParseSections(text) {
    return schoolWeekNumbers(text, true);
  }

  // 主文档与全部同源 frame 的文档；跨域或不可访问的 frame 静默跳过。
  function schoolCollectDocuments() {
    var docs = [document];
    try {
      var frames = document.querySelectorAll
          ? document.querySelectorAll('frame, iframe') : [];
      for (var f = 0; f < frames.length; f++) {
        try {
          var frameDocument = frames[f].contentDocument;
          if (frameDocument) docs.push(frameDocument);
        } catch (e) {}
      }
    } catch (e) {}
    return docs;
  }

  // docs 中任一文档满足 test 即返回 true。test 由调用方提供（各校课表容器
  // 选择器不同），用于「容器已出现但课程尚未渲染」的 __pending 探测。
  function schoolAnyDoc(docs, test) {
    for (var d = 0; d < docs.length; d++) {
      if (test(docs[d])) return true;
    }
    return false;
  }

  // 在 docs 中按选择器找到第一个满足 matches 的入口并点击，返回 __nav 信号。
  // useFallback 为真且没有入口命中时点击所在文档的第一个链接（正方老版入口
  // 文字不固定）。没有入口时返回 null。
  function schoolClickEntry(docs, selector, matches, useFallback) {
    for (var d = 0; d < docs.length; d++) {
      var doc = docs[d];
      if (!doc || !doc.querySelectorAll) continue;
      var links = doc.querySelectorAll(selector);
      var fallback = null;
      for (var l = 0; l < links.length; l++) {
        if (matches(links[l])) {
          try { links[l].click(); } catch (e) {}
          return JSON.stringify({ __nav: true });
        }
        if (!fallback) fallback = links[l];
      }
      if (useFallback && fallback) {
        try { fallback.click(); } catch (e) {}
        return JSON.stringify({ __nav: true });
      }
    }
    return null;
  }

  // 按调用方给出的 key 去重后写入一条课程记录，返回是否新增。
  function schoolPushCourse(results, seen, key, name, teacher, location, day,
      secs, weeks) {
    if (seen[key]) return false;
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
    return true;
  }
''';
