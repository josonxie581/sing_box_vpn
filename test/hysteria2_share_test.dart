import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vpn_config.dart';
import 'package:gsou/screens/node_qr_scanner_page.dart';
import 'package:gsou/services/hysteria2_share.dart';

void main() {
  for (final obfs in ['salamander', 'gecko']) {
    test(
      '$obfs survives sharing and camera import without losing credentials',
      () {
        final node = VPNConfig(
          name: 'HY2 test',
          type: 'hysteria2',
          server: '2001:db8::1',
          port: 20001,
          settings: {
            'password': 'p@ss:#?%word',
            'obfs': {
              'type': obfs,
              'password': 'obfs@secret?#',
              if (obfs == 'gecko') 'min_packet_size': 64,
              if (obfs == 'gecko') 'max_packet_size': 256,
            },
            'bbr_profile': 'conservative',
            'sni': 'example.com',
            'skipCertVerify': true,
            'alpn': ['h3'],
            'server_ports': ['20001', '20010:20020'],
            'hop_interval': '30s',
            'hop_interval_max': '60s',
            'disable_chrome_parrot': true,
          },
        );
        final imported = parseNodeQr(hysteria2ShareLink(node));
        expect(imported, isNotNull);
        expect(
          imported!.toSingBoxOutbound(tag: 'test'),
          node.toSingBoxOutbound(tag: 'test'),
        );
      },
    );
  }
}
