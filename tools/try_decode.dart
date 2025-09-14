import 'dart:convert';

String? decodeFlexible(String s) {
  String cleaned = s.replaceAll('\r', '').replaceAll('\n', '').trim();
  String? tryDecode(String content, {bool urlSafe = false}) {
    try {
      final bytes = (urlSafe ? base64Url : base64).decode(content);
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  // try normal
  var out = tryDecode(cleaned);
  if (out != null) return out;
  // try normalized + padding
  String normalized = cleaned.replaceAll('-', '+').replaceAll('_', '/');
  final mod = normalized.length % 4;
  if (mod != 0)
    normalized = normalized.padRight(normalized.length + (4 - mod), '=');
  out = tryDecode(normalized);
  if (out != null) return out;
  // try base64Url
  final mod2 = cleaned.length % 4;
  final padded = mod2 == 0
      ? cleaned
      : cleaned.padRight(cleaned.length + (4 - mod2), '=');
  out = tryDecode(padded, urlSafe: true);
  return out;
}

void main() {
  const link =
      'vmess://eyJhZGQiOiIzOC4yMDcuMTkwLjkzIiwiYWlkIjoiMCIsImhvc3QiOiJ3d3cuYmluZy5jb20iLCJpZCI6IjU4NjZm1MTlhOCIsIm5ldCI6IndzIiwicGF0aCI6IjU4NjZmYzBlLWU2YzYtNDExMC1iNGEyLTAwZGViZjQ1MTlhOC12bSIsInBvcnQhDMDNBNDU1QjY0MiIsInRscyI6IiIsInR5cGUiOiJub25lIiwidiI6IjIifQo=';
  final payload = link.startsWith('vmess://') ? link.substring(8) : link;
  final decoded = decodeFlexible(payload);
  if (decoded == null) {
    print('DECODE_FAIL: base64 无法解码');
    return;
  }
  print('DECODED STRING:');
  print(decoded);
  try {
    final obj = json.decode(decoded);
    print('\nAS JSON:');
    print(const JsonEncoder.withIndent('  ').convert(obj));
  } catch (e) {
    print('\nJSON_FAIL: 不是合法 JSON: $e');
  }
}
