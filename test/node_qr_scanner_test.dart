import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vpn_config.dart';
import 'package:gsou/providers/vpn_provider_v2.dart';
import 'package:gsou/screens/node_qr_scanner_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

class RecordingVpn extends ChangeNotifier implements VPNProviderV2 {
  final added = <VPNConfig>[];
  @override
  Future<void> addConfig(VPNConfig config) async => added.add(config);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const link = 'trojan://test-password@192.0.2.1:443#TestNode';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses existing node parsers for QR share links', () {
    final vmess =
        'vmess://${base64Encode(utf8.encode(jsonEncode({'v': '2', 'ps': 'VMess', 'add': '192.0.2.2', 'port': '443', 'id': '00000000-0000-4000-8000-000000000001', 'aid': '0', 'net': 'tcp', 'type': 'none', 'tls': ''})))}';
    for (final uri in [
      link,
      vmess,
      'vless://00000000-0000-4000-8000-000000000001@192.0.2.2:443#VLESS',
      'hy2://test-password@192.0.2.2:443#HY2',
      'ss://${base64Encode(utf8.encode('aes-256-gcm:test-password'))}@192.0.2.2:8388#SS',
    ]) {
      expect(parseNodeQr('  $uri  '), isNotNull);
    }
  });

  test(
    'SS preserves encoded credentials and accepts unpadded URL-safe userinfo',
    () {
      const credentials = 'aes-256-gcm:pass:word@?';
      for (final userInfo in [
        Uri.encodeComponent(credentials),
        base64Url.encode(utf8.encode(credentials)).replaceAll('=', ''),
      ]) {
        final node = parseNodeQr('ss://$userInfo@192.0.2.2:8388#SS');
        expect(node?.settings['method'], 'aes-256-gcm');
        expect(node?.settings['password'], 'pass:word@?');
      }
    },
  );

  test(
    'rejects unrelated URLs, missing hosts, invalid ports and oversized input',
    () {
      for (final value in [
        null,
        '',
        'https://example.com',
        'hello',
        'trojan://test-password@:443',
        'trojan://test-password@192.0.2.1:70000',
        'x' * 16385,
        '$link\n$link',
        '$link\r$link',
      ]) {
        expect(parseNodeQr(value), isNull);
      }
    },
  );

  test('malformed QR payloads cannot leak credentials through parser logs', () {
    final logs = <String>[];
    runZoned(
      () => parseNodeQr('vmess://private-not-base64'),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => logs.add(line),
      ),
    );
    expect(logs, isEmpty);
  });

  testWidgets('denied camera permission supports retry and leaving scanner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const NodeQrScannerPage()),
              ),
              child: const Text('Open camera'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需要相机权限'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需要相机权限'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MobileScanner), findsNothing);
    expect(tester.takeException(), isNull);
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
          (call) async {
            if (call.method == 'state') return 0;
            if (call.method == 'request') return false;
            return null;
          },
        );
  });

  for (final confirm in [false, true]) {
    testWidgets(
      'scan requires confirmation ($confirm) and saves at most once',
      (tester) async {
        final vpn = RecordingVpn();
        addTearDown(vpn.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<VPNProviderV2>.value(
            value: vpn,
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: FilledButton(
                    onPressed: () => scanAndAddNode(context),
                    child: const Text('Scan'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Scan'));
        await tester.pumpAndSettle();
        final scanner = tester.widget<MobileScanner>(
          find.byType(MobileScanner),
        );
        scanner.onDetect!(
          BarcodeCapture(
            barcodes: [
              const Barcode(
                rawValue: 'https://example.com',
                format: BarcodeFormat.qrCode,
              ),
            ],
          ),
        );
        await tester.pump();
        expect(find.text('未识别到有效节点，请扫描节点分享二维码'), findsOneWidget);
        expect(vpn.added, isEmpty);
        final capture = BarcodeCapture(
          barcodes: [
            const Barcode(rawValue: link, format: BarcodeFormat.qrCode),
          ],
        );
        scanner.onDetect!(capture);
        scanner.onDetect!(capture);
        await tester.pumpAndSettle();
        expect(find.text('添加扫描到的节点？'), findsOneWidget);
        expect(find.textContaining('test-password'), findsNothing);
        expect(vpn.added, isEmpty);
        await tester.tap(find.text(confirm ? '添加节点' : '取消'));
        await tester.pumpAndSettle();
        expect(vpn.added.length, confirm ? 1 : 0);
        if (confirm) expect(vpn.added.single.server, '192.0.2.1');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
