import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/dmit_billing_info.dart';
import 'package:gsou/services/dmit_billing_service.dart';
import 'package:gsou/services/dmit_ssh_monitor_service.dart';

void main() {
  late Directory temporary;
  late File config;
  late DmitSshMonitorService monitor;
  late List<List<String>> starts;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('gsou-monitor-recovery-');
    config = File('${temporary.path}/ssh-monitor.json');
    starts = [];
    monitor = DmitSshMonitorService.forTesting(
      configPath: config.path,
      startProcess: (arguments) async {
        starts.add(arguments);
        throw const ProcessException('ssh.exe', [], 'test runner');
      },
    );
  });
  tearDown(() async {
    monitor.dispose();
    await temporary.delete(recursive: true);
  });

  Future<void> writeConfig([String host = '192.0.2.1']) async {
    final key = await File('${temporary.path}/key').writeAsString('test-only');
    final hosts = await File('${temporary.path}/known_hosts').writeAsString('');
    await config.writeAsString(
      jsonEncode({
        'version': 1,
        'serviceId': '123',
        'host': host,
        'port': 22,
        'user': 'gsou-monitor',
        'identityFile': key.path,
        'knownHostsFile': hosts.path,
      }),
    );
  }

  test('reconnect reads configuration restored after startup', () async {
    await monitor.initialize();
    expect(monitor.configured, isFalse);
    expect(starts, isEmpty);
    await writeConfig();
    await monitor.reconnect();
    expect(monitor.configured, isTrue);
    expect(monitor.monitoredHost, '192.0.2.1');
    expect(starts.single.last, 'gsou-monitor@192.0.2.1');
    expect(starts.single, contains('StrictHostKeyChecking=yes'));
  });

  test('reconnect rereads corrected and changed configuration', () async {
    await config.writeAsString('{broken');
    await monitor.initialize();
    expect(monitor.configured, isFalse);
    await writeConfig();
    await monitor.reconnect();
    await writeConfig('192.0.2.2');
    await Future.wait([monitor.reconnect(), monitor.reconnect()]);
    expect(starts.length, 2);
    expect(monitor.monitorsHost('192.0.2.1'), isFalse);
    expect(monitor.monitorsHost('192.0.2.2'), isTrue);
    expect(starts.last.last, 'gsou-monitor@192.0.2.2');
  });

  test(
    'removed config clears old host instead of reconnecting to it',
    () async {
      await writeConfig();
      await monitor.initialize();
      await config.delete();
      await monitor.reconnect();
      expect(monitor.configured, isFalse);
      expect(monitor.monitoredHost, isNull);
      expect(starts.length, 1);
    },
  );

  test('billing matches unique host independently of SSH configuration', () {
    final billing = DmitBillingService.instance;
    final previous = billing.servers;
    addTearDown(() => billing.servers = previous);
    DmitBillingInfo server(String id, String host) => DmitBillingInfo(
      serviceId: id,
      name: 'DMIT',
      addresses: [host],
      usedMb: 10,
      limitMb: 100,
      transferMethod: 'both',
      suspendWhenExceeded: true,
      resetDisabled: false,
      nextDueDate: null,
    );
    billing.servers = [
      server('123', 'dmit.example'),
      server('456', '192.0.2.2'),
    ];
    expect(billing.infoFor(null), isNull);
    expect(billing.infoForHost(' DMIT.EXAMPLE. ')?.serviceId, '123');
    expect(billing.infoForHost('192.0.2.2')?.serviceId, '456');
    expect(billing.infoForHost('192.0.2.3'), isNull);
    billing.servers = [server('123', '192.0.2.1'), server('456', '192.0.2.1')];
    expect(billing.infoForHost('192.0.2.1'), isNull);
  });
}
