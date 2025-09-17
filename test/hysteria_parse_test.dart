import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vpn_config.dart';

void main() {
  group('Hysteria link parsing', () {
    test('parse with options', () {
      final link =
          'hysteria://pass123@example.com:8443?up_mbps=50&down_mbps=200&alpn=h3,h2&insecure=1&sni=foo.bar#MyHY';
      final cfg = VPNConfig.fromSubscriptionLink(link);
      expect(cfg, isNotNull);
      expect(cfg!.type.toLowerCase(), 'hysteria');
      expect(cfg.server, 'example.com');
      expect(cfg.port, 8443);
      expect(cfg.settings['password'], 'pass123');
      expect(cfg.settings['up_mbps'], 50);
      expect(cfg.settings['down_mbps'], 200);
      expect(cfg.settings['skipCertVerify'], true);
      expect(cfg.settings['sni'], 'foo.bar');
      expect(cfg.settings['alpn'], ['h3', 'h2']);
    });

    test('parse defaults', () {
      final link = 'hysteria://p@hysteria.test#HY';
      final cfg = VPNConfig.fromSubscriptionLink(link);
      expect(cfg, isNotNull);
      expect(cfg!.type.toLowerCase(), 'hysteria');
      expect(cfg.server, 'hysteria.test');
      // default port 443
      expect(cfg.port, 443);
      expect(cfg.settings['password'], 'p');
      // optional fields absent
      expect(cfg.settings.containsKey('alpn'), isFalse);
      expect(cfg.settings.containsKey('up_mbps'), isFalse);
      expect(cfg.settings.containsKey('down_mbps'), isFalse);
    });
  });
}
