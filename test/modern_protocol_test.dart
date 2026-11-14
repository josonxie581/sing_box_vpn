import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gsou/models/vpn_config.dart';
import 'package:gsou/services/config_manager.dart';
import 'package:gsou/widgets/modern_protocol_fields.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Naive URI credentials decode once and TLS verifies by default', () {
    final node = VPNConfig.fromSubscriptionLink(
      'naive+https://a%40b:p%3Ass@example.com:443#Naive',
    )!;
    final out = node.toSingBoxOutbound(tag: 'a');
    expect(out['username'], 'a@b');
    expect(out['password'], 'p:ss');
    expect(out['quic'], false);
    expect(out['tls']['insecure'], isNull);
    expect(VPNConfig.fromJson(node.toJson()).toSingBoxOutbound(tag: 'a'), out);
  });

  test('Snell v6 roundtrip preserves shaping and authentication', () {
    final node = VPNConfig.fromSubscriptionLink(
      'snell://abcdefghijkl@example.com:443?version=6&mode=unshaped&userkey=user&reuse=1',
    )!;
    final out = node.toSingBoxOutbound(tag: 'test');
    expect(out['version'], 6);
    expect(out['mode'], 'unshaped');
    expect(out['userkey'], 'user');
    expect(out['reuse'], true);
    expect(out.containsKey('tls'), false);
    expect(
      VPNConfig.fromSubscriptionLink('snell://short@example.com?version=6'),
      isNull,
    );
    expect(
      VPNConfig.fromSubscriptionLink(
        'snell://abcdefghijkl@example.com?version=5',
      ),
      isNull,
    );
  });

  test('HY2 retains gecko, hopping and congestion settings', () {
    final node = VPNConfig.fromSubscriptionLink(
      'hy2://p%40ss@example.com:443?obfs=gecko&obfs-password=secret&min_packet_size=64&max_packet_size=256&mport=443,20000:30000&hop_interval=30s&hop_interval_max=60s&bbr_profile=conservative',
    )!;
    final out = node.toSingBoxOutbound(tag: 'test');
    expect(out['password'], 'p@ss');
    expect(out['obfs'], {
      'type': 'gecko',
      'password': 'secret',
      'min_packet_size': 64,
      'max_packet_size': 256,
    });
    expect(out['server_ports'], ['443', '20000:30000']);
    expect(out.containsKey('server_port'), false);
    expect(out['hop_interval_max'], '60s');
    expect(out['bbr_profile'], 'conservative');
    expect(out.containsKey('up_mbps'), false);
  });

  test('bulk import recognizes plus schemes and existing aliases', () async {
    final manager = ConfigManager();
    final count = await manager.importFromSubscription(
      '''naive+https://u:p@example.com:443
snell://abcdefghijkl@example.com:443?version=6
anytls://secret@example.com:443
hy2://secret@example.com:443
shadowtls://secret@example.com:443?version=3''',
    );
    expect(count, 5);
  });

  testWidgets('Snell form saves version and PSK', (tester) async {
    final values = <String, dynamic>{'psk': 'abcdefghijkl', 'version': 6};
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              key: form,
              child: ModernProtocolFields(type: 'snell', values: values),
            ),
          ),
        ),
      ),
    );
    expect(find.text('预共享密钥 PSK'), findsOneWidget);
    expect(form.currentState!.validate(), true);
    form.currentState!.save();
    expect(values['version'], '6');
    expect(values['psk'], 'abcdefghijkl');
  });
}
