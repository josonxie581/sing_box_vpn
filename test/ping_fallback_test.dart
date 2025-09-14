import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vpn_config.dart';
import 'package:gsou/services/ping_service.dart';

void main() {
  group('PingService fallback', () {
    late ServerSocket server;
    setUpAll(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 8089);
      // 简单回显
      server.listen((s) async {
        await s.close();
      });
    });

    tearDownAll(() async {
      await server.close();
    });

    test(
      'TCP fallback works when ICMP likely blocked (using loopback)',
      () async {
        final cfg = VPNConfig(
          name: 'LocalTest',
          type: 'shadowsocks',
          server: '127.0.0.1',
          port: 8089,
          settings: {'method': 'aes-256-gcm', 'password': 'x'},
        );
        final ping = await PingService.pingConfig(cfg);
        // 即使 ICMP 通, 结果也应该 >=0; 若 ICMP 失败则走 TCP fallback 也应 >=0
        expect(ping, greaterThanOrEqualTo(0));
      },
    );
  });

  test('VPNConfig id uniqueness for bulk creation', () {
    final ids = <String>{};
    for (int i = 0; i < 500; i++) {
      final c = VPNConfig(
        name: 'c$i',
        type: 'shadowsocks',
        server: 'example.com',
        port: 8388,
        settings: {'method': 'aes-256-gcm', 'password': 'x'},
      );
      expect(
        ids.contains(c.id),
        isFalse,
        reason: 'Duplicate id at $i: ${c.id}',
      );
      ids.add(c.id);
    }
  });
}
