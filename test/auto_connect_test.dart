import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vpn_config.dart';
import 'package:gsou/providers/vpn_provider_v2.dart';
import 'package:gsou/services/auto_start_service.dart';
import 'package:gsou/services/config_manager.dart';
import 'package:gsou/services/connection_manager.dart';
import 'package:gsou/services/singbox_native_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String scriptOf(List<String> args) {
  final bytes = base64Decode(args.last);
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8,
  ]);
}

VPNConfig node(String id) => VPNConfig(
  id: id,
  name: id,
  type: 'shadowsocks',
  server: '192.0.2.1',
  port: 443,
  settings: {},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'auto-connect defaults off and migrates the existing login task',
    () async {
      final operations = <String>[];
      final service = AutoStartService(
        operatingSystem: 'windows',
        runner: (_, args) async {
          final script = scriptOf(args);
          operations.add(
            script.contains("\$operation = 'enable'") ? 'enable' : 'query',
          );
          expect(script, contains("-Argument '--autostart'"));
          return ProcessResult(1, 0, '{"enabled":true}', '');
        },
      );
      expect(await service.isAutoConnectEnabled(), isFalse);
      expect(await service.setAutoConnectEnabled(true), isTrue);
      expect(operations, ['enable']);
      expect(await AutoStartService().isAutoConnectEnabled(), isTrue);
      operations.clear();
      expect(await service.setAutoConnectEnabled(false), isFalse);
      expect(await AutoStartService().isAutoConnectEnabled(), isFalse);
      expect(operations, isEmpty); // Disabling never changes the login task.
    },
  );

  test('auto-connect enables a disabled login task before saving', () async {
    var enabled = false;
    final service = AutoStartService(
      operatingSystem: 'windows',
      runner: (_, args) async {
        if (scriptOf(args).contains("\$operation = 'enable'")) enabled = true;
        return ProcessResult(1, 0, jsonEncode({'enabled': enabled}), '');
      },
    );
    expect(await service.setAutoConnectEnabled(true), isTrue);
    expect(enabled, isTrue);
    expect(await service.isAutoConnectEnabled(), isTrue);
  });

  test('failed login task read-back does not save auto-connect', () async {
    final service = AutoStartService(
      operatingSystem: 'windows',
      runner: (_, _) async => ProcessResult(1, 0, '{"enabled":false}', ''),
    );
    await expectLater(service.setAutoConnectEnabled(true), throwsStateError);
    expect(await service.isAutoConnectEnabled(), isFalse);
  });

  test('failed task migration does not persist auto-connect', () async {
    final service = AutoStartService(
      operatingSystem: 'windows',
      runner: (_, args) async =>
          scriptOf(args).contains("\$operation = 'query'")
          ? ProcessResult(1, 0, '{"enabled":true}', '')
          : ProcessResult(1, 1, '', 'denied'),
    );
    await expectLater(
      service.setAutoConnectEnabled(true),
      throwsA(isA<AutoStartException>()),
    );
    expect(await service.isAutoConnectEnabled(), isFalse);
  });

  test(
    'Windows launch marker distinguishes automatic and manual launch',
    () async {
      final service = AutoStartService(
        operatingSystem: 'windows',
        runner: (_, _) async => throw StateError('no system query needed'),
      );
      expect(await service.isAutoStartLaunch([]), isFalse);
      expect(await service.isAutoStartLaunch(['--autostart']), isTrue);
      expect(await service.isAutoStartLaunch(['--autostart=false']), isFalse);
    },
  );

  test('old Linux service only identifies its own main process', () async {
    for (final mainPid in ['$pid', '0', '${pid + 1}', 'invalid']) {
      final service = AutoStartService(
        operatingSystem: 'linux',
        runner: (exe, args) async {
          expect(exe, 'systemctl');
          expect(args, [
            '--user',
            'show',
            'gsou.service',
            '--property=MainPID',
            '--value',
          ]);
          return ProcessResult(1, 0, mainPid, '');
        },
      );
      expect(await service.isAutoStartLaunch([]), mainPid == '$pid');
      expect(await service.isAutoStartLaunch(['--autostart']), isTrue);
    }
  });

  test(
    'unavailable Linux service is not mistaken for automatic launch',
    () async {
      final service = AutoStartService(
        operatingSystem: 'linux',
        runner: (_, _) async => ProcessResult(1, 1, '', 'no user bus'),
      );
      expect(await service.isAutoStartLaunch([]), isFalse);
    },
  );

  for (final scenario in [
    'saved node',
    'missing saved node',
    'no saved node',
    'empty',
    'manual launch',
    'disabled',
    'connected',
    'connecting',
    'disconnecting',
  ]) {
    testWidgets('startup connection: $scenario', (tester) async {
      SharedPreferences.setMockInitialValues({
        'auto_connect_on_startup': scenario != 'disabled',
        if (scenario != 'no saved node')
          'current_config_id': scenario == 'missing saved node'
              ? 'removed'
              : 'second',
        'first_run_done': true,
        'use_tun': true,
        'auto_refresh_enabled': false,
      });
      final configs = FakeConfigs(
        scenario == 'empty' ? [] : [node('first'), node('second')],
      );
      final connection = FakeConnection()
        ..isConnected = scenario == 'connected'
        ..isConnecting = scenario == 'connecting'
        ..isDisconnecting = scenario == 'disconnecting';
      final native = FakeNative();
      final provider = VPNProviderV2(
        launchedAtStartup: scenario != 'manual launch',
        configManager: configs,
        connectionManager: connection,
        singboxService: native,
      );
      await tester.pump();
      expect(native.calls, 0);
      expect(connection.attempts, isEmpty);
      configs.loaded.complete();
      await tester.pump();
      expect(native.calls, 1);
      expect(
        connection.attempts,
        isEmpty,
      ); // Native initialization still pending.
      expect(
        connection.useTun,
        isTrue,
      ); // Preferences applied before connecting.
      native.ready.complete(true);
      await tester.pump();
      await provider.initialized;
      final expected = switch (scenario) {
        'saved node' => ['second'],
        'missing saved node' || 'no saved node' => ['first'],
        _ => <String>[],
      };
      expect(connection.attempts, expected);
      // Drain the existing startup-ping delay without probing any real nodes.
      configs.configs.clear();
      await tester.pump(const Duration(seconds: 2));
      expect(
        connection.attempts,
        expected,
      ); // No retries after a failed attempt.
      provider.dispose();
    });
  }
}

class FakeConfigs implements ConfigManager {
  FakeConfigs(this.configs);
  final loaded = Completer<void>();
  @override
  final List<VPNConfig> configs;
  @override
  VPNConfig? currentConfig;
  @override
  Future<void> loadConfigs() => loaded.future;
  @override
  void setCurrentConfig(VPNConfig? config) => currentConfig = config;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeConnection implements ConnectionManager {
  final attempts = <String>[];
  @override
  bool isConnected = false;
  @override
  bool isConnecting = false;
  @override
  bool isDisconnecting = false;
  @override
  bool useTun = false;
  @override
  VPNConfig? get currentConfig => null;
  @override
  int get clashApiPort => 9090;
  @override
  Future<void> init() async {}
  @override
  void setUseTun(bool value) => useTun = value;
  @override
  Future<bool> connect(VPNConfig config) async {
    attempts.add(config.id);
    return false; // Exercise the failure path without starting a real VPN.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName.toString().contains('set')) return null;
    return super.noSuchMethod(invocation);
  }
}

class FakeNative extends SingBoxNativeService {
  final ready = Completer<bool>();
  int calls = 0;
  @override
  Future<bool> initialize() {
    calls++;
    return ready.future;
  }
}
