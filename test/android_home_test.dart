import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/proxy_mode.dart';
import 'package:gsou/models/vpn_config.dart';
import 'package:gsou/providers/vpn_provider_v2.dart';
import 'package:gsou/screens/simple_modern_home.dart';
import 'package:gsou/widgets/dmit_status_card.dart';
import 'package:provider/provider.dart';

class IdleVpn extends ChangeNotifier implements VPNProviderV2 {
  @override
  List<VPNConfig> get configs => [];
  @override
  VPNConfig? get currentConfig => null;
  @override
  bool get isConnected => false;
  @override
  bool get isConnecting => false;
  @override
  bool get isDisconnecting => false;
  @override
  bool get useTun => true;
  @override
  bool get autoSystemProxy => false;
  @override
  int get uploadBytes => 0;
  @override
  int get downloadBytes => 0;
  @override
  int get uploadSpeed => 0;
  @override
  int get downloadSpeed => 0;
  @override
  int get activeConnections => 0;
  @override
  Duration get connectionDuration => Duration.zero;
  @override
  ProxyMode get proxyMode => ProxyMode.rule;
  @override
  List<String> get logs => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [360.0, 393.0, 412.0]) {
    testWidgets(
      'Android home is usable at $width logical pixels',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final vpn = IdleVpn();
        addTearDown(vpn.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<VPNProviderV2>.value(
            value: vpn,
            child: const MaterialApp(home: SimpleModernHome()),
          ),
        );
        await tester.pump();
        expect(find.text('暂无配置'), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('系统代理'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'Android does not initialize or render the desktop DMIT card',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DmitStatusCard(nodeName: 'DMIT JP', serverHost: '192.0.2.2'),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(DmitStatusCard),
          matching: find.byType(ListenableBuilder),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
