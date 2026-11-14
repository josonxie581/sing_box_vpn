import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/services/auto_start_service.dart';
import 'package:gsou/services/native_library_path.dart';
import 'package:gsou/utils/linux_tun_permissions.dart';

void main() {
  test('Linux loads only the library bundled next to the executable', () {
    final checked = <String>[];
    expect(
      resolveNativeLibraryPath(
        operatingSystem: 'linux',
        executablePath: '/opt/gsou/gsou',
        workingDirectory: '/home/user/download',
        allowDevelopmentPaths: false,
        exists: (file) {
          checked.add(file);
          return file == '/opt/gsou/lib/libsingbox.so';
        },
      ),
      '/opt/gsou/lib/libsingbox.so',
    );
    expect(checked, ['/opt/gsou/lib/libsingbox.so']);
  });

  test(
    'missing Linux library fails without searching the working directory',
    () {
      expect(
        () => resolveNativeLibraryPath(
          operatingSystem: 'linux',
          executablePath: '/opt/gsou/gsou',
          workingDirectory: '/tmp',
          allowDevelopmentPaths: false,
          exists: (file) => file == '/tmp/libsingbox.so',
        ),
        throwsStateError,
      );
    },
  );

  test('Windows and Android keep their existing library locations', () {
    expect(
      resolveNativeLibraryPath(
        operatingSystem: 'windows',
        executablePath: r'C:\Gsou\Gsou.exe',
        workingDirectory: r'D:\source',
        exists: (file) => file == r'C:\Gsou\singbox.dll',
      ),
      r'C:\Gsou\singbox.dll',
    );
    expect(
      resolveNativeLibraryPath(
        operatingSystem: 'windows',
        executablePath: r'C:\Gsou\Gsou.exe',
        workingDirectory: r'D:\source',
        exists: (file) => file == r'D:\source\windows\singbox.dll',
      ),
      r'D:\source\windows\singbox.dll',
    );
    expect(
      resolveNativeLibraryPath(operatingSystem: 'android'),
      'libsingbox.so',
    );
    expect(
      () => resolveNativeLibraryPath(operatingSystem: 'ios'),
      throwsUnsupportedError,
    );
  });

  test('only debug/test loads an explicitly built development core', () {
    for (final debug in [true, false]) {
      String resolve() => resolveNativeLibraryPath(
        operatingSystem: 'linux',
        executablePath: '/sdk/flutter_tester',
        workingDirectory: '/project',
        allowDevelopmentPaths: debug,
        exists: (file) => file == '/project/build/linux-core/libsingbox.so',
      );
      if (debug) {
        expect(resolve(), '/project/build/linux-core/libsingbox.so');
      } else {
        expect(resolve, throwsStateError);
      }
    }
  });

  test(
    'TUN permission uses effective capabilities, not UID or permitted bits',
    () {
      expect(
        hasLinuxTunCapabilities('Uid:\t1000\nCapEff:\t0000000000003000\n'),
        isTrue,
      );
      expect(hasLinuxTunCapabilities('CapEff:\t000001ffffffffff\n'), isTrue);
      expect(
        hasLinuxTunCapabilities('Uid:\t0\nCapEff:\t0000000000000000\n'),
        isFalse,
      );
      expect(
        hasLinuxTunCapabilities('CapPrm:\t0000000000003000\nCapEff:\t0\n'),
        isFalse,
      );
      expect(hasLinuxTunCapabilities('CapEff:\t1000\n'), isFalse);
      expect(hasLinuxTunCapabilities('CapEff:\t2000\n'), isFalse);
      expect(hasLinuxTunCapabilities('CapEff: invalid'), isFalse);
      expect(hasLinuxTunCapabilities(''), isFalse);
    },
  );

  test('Linux auto-start reads back systemd state after each change', () async {
    var enabled = false;
    final commands = <List<String>>[];
    final service = AutoStartService(
      operatingSystem: 'linux',
      runner: (executable, arguments) async {
        expect(executable, 'systemctl');
        commands.add(arguments);
        if (arguments.contains('enable')) enabled = true;
        if (arguments.contains('disable')) enabled = false;
        if (arguments.contains('is-enabled')) {
          return ProcessResult(
            1,
            enabled ? 0 : 1,
            enabled ? 'enabled\n' : 'disabled\n',
            '',
          );
        }
        return ProcessResult(1, 0, '', '');
      },
    );
    expect(await service.isEnabled(), isFalse);
    expect(await service.setEnabled(true), isTrue);
    expect(await service.setEnabled(false), isFalse);
    expect(commands.where((args) => args.contains('daemon-reload')).length, 2);
    expect(commands.where((args) => args.contains('is-enabled')).length, 3);
  });

  test(
    'missing user bus or service is an error, not a disabled state',
    () async {
      for (final result in [
        ProcessResult(1, 1, '', 'Failed to connect to bus'),
        ProcessResult(1, 4, 'not-found\n', ''),
        ProcessResult(1, 1, 'masked\n', ''),
      ]) {
        final service = AutoStartService(
          operatingSystem: 'linux',
          runner: (_, _) async => result,
        );
        await expectLater(
          service.isEnabled(),
          throwsA(isA<AutoStartException>()),
        );
      }
    },
  );

  test(
    'Linux auto-start does not report success when read-back disagrees',
    () async {
      final service = AutoStartService(
        operatingSystem: 'linux',
        runner: (_, args) async => args.contains('is-enabled')
            ? ProcessResult(1, 1, 'disabled', '')
            : ProcessResult(1, 0, '', ''),
      );
      await expectLater(service.setEnabled(true), throwsStateError);
    },
  );
}
