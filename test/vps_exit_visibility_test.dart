import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vpn_config.dart';
import 'package:gsou/providers/vpn_provider_v2.dart';
import 'package:gsou/utils/dmit_nodes.dart';
import 'package:gsou/widgets/vps_exit_entry.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

VPNConfig node(String name, String host) => VPNConfig(
  name: name,
  type: 'vmess',
  server: host,
  port: 443,
  settings: const {},
);

// Implement the interface without starting VPNProviderV2's native initialization.
class NodeList extends ChangeNotifier implements VPNProviderV2 {
  @override
  List<VPNConfig> configs = [];
  @override
  VPNConfig? currentConfig;
  void replace(List<VPNConfig> value) {
    configs = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget home(NodeList nodes) => ChangeNotifierProvider<VPNProviderV2>.value(
  value: nodes,
  child: const MaterialApp(home: Scaffold(body: VpsExitEntry())),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'recognizes explicit DMIT names without confusing admit with the provider',
    () {
      for (final name in [
        'DMIT',
        'dmit-jp',
        '日本 DMIT 节点',
        'DMIT日本',
        '🇯🇵 DMIT_JP',
      ]) {
        expect(isDmitNode(node(name, '192.0.2.1')), isTrue, reason: name);
      }
      for (final name in ['', '普通日本节点', 'Admit server', 'notdmitnode']) {
        expect(isDmitNode(node(name, '192.0.2.1')), isFalse, reason: name);
      }
    },
  );

  test('prefers the selected DMIT node, otherwise the first DMIT node', () {
    final other = node('Other', '192.0.2.1');
    final first = node('DMIT JP', '192.0.2.2');
    final second = node('DMIT SG', '192.0.2.3');
    expect(findDmitNode([other]), isNull);
    expect(findDmitNode([other, first, second], preferred: other), same(first));
    expect(
      findDmitNode([other, first, second], preferred: second),
      same(second),
    );
  });

  testWidgets(
    'empty and non-DMIT node lists hide the entry; adding DMIT shows it',
    (tester) async {
      final nodes = NodeList();
      addTearDown(nodes.dispose);
      await tester.pumpWidget(home(nodes));
      expect(find.text('VPS 出口管控'), findsNothing);
      nodes.replace([node('Other server', '192.0.2.1')]);
      await tester.pump();
      expect(find.text('VPS 出口管控'), findsNothing);
      nodes.replace([node('dmit-jp', '192.0.2.2')]);
      await tester.pump();
      expect(find.text('VPS 出口管控'), findsOneWidget);
    },
  );

  testWidgets(
    'opens the DMIT target even if another provider is selected; removal closes it',
    (tester) async {
      final other = node('Other server', '192.0.2.1');
      final nodes = NodeList()..currentConfig = other;
      nodes.replace([other, node('DMIT JP', '192.0.2.2')]);
      addTearDown(nodes.dispose);
      await tester.pumpWidget(home(nodes));
      await tester.tap(find.text('VPS 出口管控'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '192.0.2.2',
      );
      nodes.replace([other]);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('VPS 出口管控'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
