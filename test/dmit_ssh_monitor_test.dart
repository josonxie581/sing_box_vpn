import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/dmit_ssh_monitor.dart';

Map<String, dynamic> sample([Map<String, dynamic> overrides = const {}]) => {
  'version': 1,
  'cpuPercent': 12.5,
  'memoryTotalBytes': 1073741824,
  'memoryAvailableBytes': 671088640,
  'diskTotalBytes': 21474836480,
  'diskAvailableBytes': 12884901888,
  'load1': 0.25,
  'uptimeSeconds': 90061,
  'rxBytesPerSecond': 1536.0,
  'txBytesPerSecond': 1048576.0,
  'networkInterface': 'eth0',
  ...overrides,
};

void main() {
  test('parses and derives a valid runtime sample', () {
    final received = DateTime.parse('2026-10-17T06:00:00+00:00');
    final info = DmitRuntimeInfo.fromMonitorJson(
      sample(),
      serviceId: '159947',
      receivedAt: received,
    );

    expect(info.serviceId, '159947');
    expect(info.receivedAt, received);
    expect(info.cpuPercent, 12.5);
    expect(info.memoryUsedBytes, 402653184);
    expect(info.memoryFraction, 0.375);
    expect(info.diskUsedBytes, 8589934592);
    expect(info.diskFraction, 0.4);
    expect(info.networkInterface, 'eth0');
  });

  test('rejects impossible or unsafe runtime values', () {
    for (final overrides in [
      {'version': 2},
      {'cpuPercent': -1},
      {'cpuPercent': 101},
      {'memoryAvailableBytes': 2147483648},
      {'diskTotalBytes': 0},
      {'load1': -0.1},
      {'uptimeSeconds': -1},
      {'rxBytesPerSecond': -1},
      {'networkInterface': 'eth0;whoami'},
    ]) {
      expect(
        () => DmitRuntimeInfo.fromMonitorJson(
          sample(overrides),
          serviceId: '159947',
          receivedAt: DateTime.utc(2026),
        ),
        throwsFormatException,
        reason: '$overrides',
      );
    }
  });

  test('formats bytes, rates and uptime', () {
    expect(DmitRuntimeInfo.formatBytes(0), '0 B');
    expect(DmitRuntimeInfo.formatBytes(1024), '1.00 KB');
    expect(DmitRuntimeInfo.formatBytes(1073741824), '1.00 GB');
    expect(DmitRuntimeInfo.formatRate(1536), '1.50 KB/s');
    expect(DmitRuntimeInfo.formatUptime(59), '0分钟');
    expect(DmitRuntimeInfo.formatUptime(3660), '1小时 1分钟');
    expect(DmitRuntimeInfo.formatUptime(90061), '1天 1小时');
  });

  test('validates the SSH configuration without exposing key content', () {
    final config = DmitSshMonitorConfig.fromJson({
      'version': 1,
      'serviceId': '159947',
      'host': '154.31.116.184',
      'port': 22,
      'user': 'gsou-monitor',
      'identityFile': r'C:\Users\xiejo\AppData\Local\Gsou\dmit\ssh\id_ed25519',
      'knownHostsFile':
          r'C:\Users\xiejo\AppData\Local\Gsou\dmit\ssh\known_hosts',
    });

    expect(config.user, 'gsou-monitor');
    expect(config.port, 22);
    expect(config.toJson()['identityFile'], endsWith('id_ed25519'));
  });

  test('rejects option injection and invalid identifiers in SSH config', () {
    Map<String, dynamic> config([Map<String, dynamic> overrides = const {}]) =>
        {
          'version': 1,
          'serviceId': '159947',
          'host': '154.31.116.184',
          'port': 22,
          'user': 'gsou-monitor',
          'identityFile': r'C:\key',
          'knownHostsFile': r'C:\known_hosts',
          ...overrides,
        };

    for (final overrides in [
      {'serviceId': 'server-1'},
      {'host': '-Fbad'},
      {'host': 'host name'},
      {'port': 0},
      {'port': 65536},
      {'user': 'root@host'},
    ]) {
      expect(
        () => DmitSshMonitorConfig.fromJson(config(overrides)),
        throwsFormatException,
        reason: '$overrides',
      );
    }
  });
}
