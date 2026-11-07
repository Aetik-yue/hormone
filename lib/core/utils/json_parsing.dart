/// JSON 字段的宽松解析工具（纯函数）。
///
/// 备份恢复（`backup_repository.dart`）与 JSON 文件导入（`json_importer.dart`）
/// 共用同一套容错规则；颜色回退值由调用方传入，两者各自的默认色不同。
library;

/// 把 int、double 或数字字符串解析为 int，其他情况返回 null。
int? toIntOrNull(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// 把任意值解析为去掉首尾空白的字符串；null 与空串返回 null。
String? toStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// 解析颜色：支持 "#RRGGBB" / "0xFFRRGGBB" / 纯 "RRGGBB"，失败返回 [fallback]。
int parseHexColor(String? s, {required int fallback}) {
  if (s == null) return fallback;
  var hex = s.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length == 8) return int.tryParse(hex, radix: 16) ?? fallback;
  return fallback;
}
