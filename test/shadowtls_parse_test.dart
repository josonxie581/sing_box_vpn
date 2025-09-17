import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vpn_config.dart';

void main() {
  group('ShadowTLS subscription parsing', () {
    test('parses full shadowtls link with v3 and options', () {
      const raw =
          'shadowtls://mypwd@example.com:443?version=3&alpn=h2,h3&sni=example.com&insecure=1#MyST';

      final cfg = VPNConfig.fromSubscriptionLink(raw);
      expect(cfg, isNotNull);
      expect(cfg!.type, 'shadowtls');
      expect(cfg.server, 'example.com');
      expect(cfg.port, 443);

      // settings
      expect(cfg.settings['version'], 3);
      expect(cfg.settings['password'], 'mypwd');
      expect(cfg.settings['sni'], 'example.com');
      expect(cfg.settings['skipCertVerify'], isTrue);
      expect(cfg.settings['alpn'], isA<List>());
      expect((cfg.settings['alpn'] as List), containsAll(<String>['h2', 'h3']));
    });

    test('defaults: version=1, no password, sni optional', () {
      const raw = 'shadowtls://@st.example.org:8443#NoPwd';
      final cfg = VPNConfig.fromSubscriptionLink(raw);
      expect(cfg, isNotNull);
      expect(cfg!.type, 'shadowtls');
      expect(cfg.server, 'st.example.org');
      expect(cfg.port, 8443);

      expect(cfg.settings['version'], 1);
      // password omitted
      expect(cfg.settings.containsKey('password'), isFalse);
      // sni omitted -> not set in settings (tls uses server as fallback at build time)
      expect(cfg.settings['sni'], isNull);
      expect(cfg.settings['alpn'], isNull);
      expect(cfg.settings['skipCertVerify'], isNot(isTrue));
    });
  });
}
