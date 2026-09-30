import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vpn_config.dart';
import 'package:gsou/services/ping_service.dart';
import 'package:gsou/services/node_delay_tester.dart';

void main() {
  group('PingService server RTT', () {
    late ServerSocket server;
    setUpAll(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      // 简单回显
      server.listen((s) async {
        await s.close();
      });
    });

    tearDownAll(() async {
      await server.close();
    });

    test('TCP RTT requires a reachable server port', () async {
      final cfg = VPNConfig(
        name: 'LocalTest',
        type: 'shadowsocks',
        server: '127.0.0.1',
        port: server.port,
        settings: {'method': 'aes-256-gcm', 'password': 'x'},
      );
      final ping = await PingService.pingConfig(cfg);
      expect(ping, greaterThanOrEqualTo(0));
    });
  });

  test(
    'refused TCP is not a successful low RTT in either test mode',
    () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final node = VPNConfig(
        name: 'closed',
        type: 'vmess',
        server: '127.0.0.1',
        port: port,
        settings: {},
      );
      final tester = NodeDelayTester(timeout: 500);
      for (final result in [
        await tester.realTest(node),
        await tester.quickTest(node),
      ]) {
        expect(result.isSuccess, isFalse);
        expect(result.delay, -1);
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'QUIC failure cannot reuse another TCP service as node latency',
    () async {
      final tcp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      tcp.listen((socket) => socket.destroy());
      try {
        for (final protocol in ['tuic', 'hysteria2']) {
          final node = VPNConfig(
            name: protocol,
            type: protocol,
            server: '127.0.0.1',
            port: tcp.port,
            settings: {'skipCertVerify': true},
          );
          final result = await NodeDelayTester(timeout: 200).realTest(node);
          expect(result.isSuccess, isFalse);
          expect(result.delay, -1);
        }
      } finally {
        await tcp.close();
      }
    },
    skip: !Platform.isWindows,
  );

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
