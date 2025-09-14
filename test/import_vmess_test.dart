import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vpn_config.dart';

void main() {
  test('parse sample vmess', () {
    const raw =
        'vmess://eyJhZGQiOiIzOC4yMDcuMTkwLjkzIiwiYWlkIjoiMCIsImhvc3QiOiJ3d3cuYmluZy5jb20iLCJpZCI6IjU4NjZmMTFhOCIsIm5ldCI6IndzIiwicGF0aCI6Ii9wYXRoIiwicG9ydCI6IjQ0MyIsInRscyI6IiIsInR5cGUiOiJub25lIiwidiI6IjIifQ==';

    final cfg = VPNConfig.fromSubscriptionLink(raw);

    expect(cfg, isNotNull, reason: '解析应返回非空的 VPNConfig');
    expect(cfg!.type, 'vmess');
    expect(cfg.server, '38.207.190.93');
    expect(cfg.port, 443);
    expect(cfg.uuid, isNotEmpty);
  });
}
