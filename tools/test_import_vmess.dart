import 'dart:convert';
import '../lib/models/vpn_config.dart';

void main() {
  // 示例 vmess 文本（来自用户提供的数据）
  const raw =
      'vmess://eyJhZGQiOiIzOC4yMDcuMTkwLjkzIiwiYWlkIjoiMCIsImhvc3QiOiJ3d3cuYmluZy5jb20iLCJpZCI6IjU4NjZmMTFhOCIsIm5ldCI6IndzIiwicGF0aCI6Ii9wYXRoIiwicG9ydCI6IjQ0MyIsInRscyI6IiIsInR5cGUiOiJub25lIiwidiI6IjIifQ==';

  print('原始输入：');
  print(raw);

  final cfg = VPNConfig.fromSubscriptionLink(raw);
  if (cfg == null) {
    print('\n解析失败：VPNConfig.fromSubscriptionLink 返回 null');
    return;
  }

  print('\n解析成功，配置 JSON:');
  final json = cfg.toJson();
  print(JsonEncoder.withIndent('  ').convert(json));
}
