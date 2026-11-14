import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gsou/services/auto_start_service.dart';
import 'package:gsou/widgets/auto_start_card.dart';

String decodeScript(List<String> args) {
  final bytes = base64Decode(args.last);
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ]);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('login task carries the automatic startup marker', () async {
    final service = AutoStartService(
      operatingSystem: 'windows',
      runner: (_, args) async {
        expect(decodeScript(args), contains("-Argument '--autostart'"));
        return ProcessResult(1, 0, '{"enabled":true}', '');
      },
    );
    await service.setEnabled(true);
  });

  testWidgets('offers a separate auto-connect switch, off by default', (
    tester,
  ) async {
    final service = FakeAutoStartService()..read.complete(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AutoStartCard(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('开机后自动开始'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
  });

  test(
    'reads actual system state and safely quotes executable paths',
    () async {
      final service = AutoStartService(
        isSupported: true,
        operatingSystem: 'windows',
        executablePath: r"D:\中文 O'Brien\Gsou\gsou.exe",
        runner: (executable, args) async {
          expect(
            executable,
            endsWith(r'WindowsPowerShell\v1.0\powershell.exe'),
          );
          expect(
            args,
            containsAll(['-NoProfile', '-NonInteractive', 'Hidden']),
          );
          final script = decodeScript(args);
          expect(script, contains(r"$exe = 'D:\中文 O''Brien\Gsou\gsou.exe'"));
          expect(script, contains(r"$directory = 'D:\中文 O''Brien\Gsou'"));
          expect(script, contains(r"$operation = 'query'"));
          return ProcessResult(1, 0, '{"enabled":true}', '');
        },
      );
      expect(await service.isEnabled(), isTrue);
    },
  );

  test('failed registration surfaces an actionable error', () async {
    final service = AutoStartService(
      isSupported: true,
      operatingSystem: 'windows',
      runner: (_, _) async => ProcessResult(1, 1, '', 'Access denied'),
    );
    await expectLater(
      service.setEnabled(true),
      throwsA(isA<AutoStartException>()),
    );
  });

  test('does not report success when read-back disagrees', () async {
    final service = AutoStartService(
      isSupported: true,
      operatingSystem: 'windows',
      runner: (_, _) async => ProcessResult(1, 0, '{"enabled":false}', ''),
    );
    await expectLater(service.setEnabled(true), throwsStateError);
    expect(await service.setEnabled(false), isFalse);
  });

  test('rejects malformed system output', () async {
    final service = AutoStartService(
      isSupported: true,
      operatingSystem: 'windows',
      runner: (_, _) async => ProcessResult(1, 0, '{"enabled":"true"}', ''),
    );
    await expectLater(service.isEnabled(), throwsFormatException);
  });

  test(
    'PowerShell task logic handles absent, enabled, disabled and stale tasks',
    () async {
      // Execute the real script against in-memory ScheduledTasks cmdlets. No OS
      // tasks are created or deleted; this checks PowerShell syntax and semantics.
      for (final scenario in [
        'absent',
        'enabled',
        'legacy',
        'account-name',
        'other-user',
        'empty-user',
        'disabled',
        'stale',
      ]) {
        final service = AutoStartService(
          isSupported: true,
          operatingSystem: 'windows',
          executablePath: r"D:\中文 O'Brien\gsou.exe",
          runner: (exe, args) async {
            final script = decodeScript(args);
            final stub =
                '''
\$script:fakeTask = \$null
function Get-ScheduledTask { param(\$TaskPath) return \$script:fakeTask }
function Test-Path { param(\$LiteralPath, \$PathType) return \$true }
function New-ScheduledTaskAction { param(\$Execute, \$Argument, \$WorkingDirectory) return @{ Execute = \$Execute; Arguments = \$Argument } }
function New-ScheduledTaskTrigger { param([switch]\$AtLogOn, \$User) return @{ Enabled = \$true; UserId = \$User; CimClass = @{ CimClassName = 'MSFT_TaskLogonTrigger' } } }
function New-ScheduledTaskPrincipal { param(\$UserId, \$LogonType, \$RunLevel) }
function New-ScheduledTaskSettingsSet { param([switch]\$AllowStartIfOnBatteries, [switch]\$DontStopIfGoingOnBatteries, \$ExecutionTimeLimit, \$MultipleInstances) return @{ Enabled = \$true } }
function Register-ScheduledTask { param(\$TaskPath, \$TaskName, \$Action, \$Trigger, \$Principal, \$Settings, \$Description, [switch]\$Force)
  ${scenario == 'account-name' ? r'$Trigger.UserId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name' : ''}
  \$script:fakeTask = @{ TaskName = \$TaskName; Actions = @(\$Action); Triggers = @(\$Trigger); Settings = \$Settings }
}
function Unregister-ScheduledTask { param(\$TaskPath, \$TaskName, [switch]\$Confirm) \$script:fakeTask = \$null }
''';
            // Seed using the same script's registration, then simulate external edits.
            final seed = script.replaceFirst(
              RegExp(r"\$operation = '(query|enable|disable)'"),
              "\$operation = 'enable'",
            );
            final setup = scenario == 'absent'
                ? ''
                : '& { $seed } | Out-Null\n'
                      '${scenario == 'disabled' ? r'$script:fakeTask.Settings.Enabled = $false' : ''}\n'
                      '${scenario == 'legacy' ? r'$script:fakeTask.Actions[0].Arguments = ""' : ''}\n'
                      '${scenario == 'other-user' ? r'$script:fakeTask.Triggers[0].UserId = "S-1-5-18"' : ''}\n'
                      '${scenario == 'empty-user' ? r'$script:fakeTask.Triggers[0].UserId = ""' : ''}\n'
                      '${scenario == 'stale' ? r'$script:fakeTask.Actions[0].Execute = "D:\old\gsou.exe"' : ''}\n';
            final full = '$stub\n$setup\n$script';
            final bytes = <int>[
              for (final unit in full.codeUnits) ...[unit & 255, unit >> 8],
            ];
            return Process.run(
              exe,
              [...args.take(args.length - 1), base64Encode(bytes)],
              stdoutEncoding: utf8,
              stderrEncoding: utf8,
            );
          },
        );
        expect(
          await service.isEnabled(),
          ['enabled', 'legacy', 'account-name'].contains(scenario),
          reason: scenario,
        );
        // Registration must replace legacy arguments and verify the new marker.
        expect(await service.setEnabled(true), isTrue, reason: scenario);
        expect(await service.setEnabled(false), isFalse, reason: scenario);
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets('loads, saves and disables repeated clicks while pending', (
    tester,
  ) async {
    final service = FakeAutoStartService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AutoStartCard(service: service)),
      ),
    );
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
    service.read.complete(false);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(service.writes, [true]);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
    service.write.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });

  testWidgets('failed write preserves state and offers read-back retry', (
    tester,
  ) async {
    final service = FakeAutoStartService()..read.complete(false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AutoStartCard(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    service.write.completeError(
      const AutoStartException('请以管理员身份运行 Gsou 后重试', 'denied'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(find.textContaining('管理员'), findsOneWidget);
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Switch>(find.byType(Switch).first).onChanged,
      isNotNull,
    );
  });

  testWidgets('pending read can finish after leaving the page', (tester) async {
    final service = FakeAutoStartService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AutoStartCard(service: service)),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    service.read.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'auto-connect can enable login startup and remains off on failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(450, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakeAutoStartService()..read.complete(false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AutoStartCard(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(find.byType(Switch).last).onChanged,
        isNotNull,
      );
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      expect(service.writes, [true]);
      service.write.complete(true);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);
      await service.setAutoConnectEnabled(false);

      await tester.pumpWidget(const SizedBox());
      final enabledService = FakeAutoStartService()..read.complete(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AutoStartCard(service: enabledService)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch).last).onChanged, isNull);
      enabledService.write.completeError(StateError('无法更新开机任务'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
      expect(find.textContaining('无法更新开机任务'), findsOneWidget);
      expect(await AutoStartService().isAutoConnectEnabled(), isFalse);
    },
  );

  testWidgets(
    'auto-connect saves, reloads and can be switched off at desktop width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(450, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakeAutoStartService()..read.complete(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: AutoStartCard(service: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      expect(service.writes, [
        true,
      ]); // Updates an existing pre-marker login task.
      service.write.complete(true);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AutoStartCard(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(await AutoStartService().isAutoConnectEnabled(), isFalse);
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
      expect(service.writes, [true]);
      expect(tester.takeException(), isNull);
    },
  );
}

class FakeAutoStartService extends AutoStartService {
  FakeAutoStartService() : super(isSupported: true);

  final read = Completer<bool>();
  final write = Completer<bool>();
  final writes = <bool>[];

  @override
  Future<bool> isEnabled() => read.future;

  @override
  Future<bool> setEnabled(bool enabled) {
    writes.add(enabled);
    return write.future;
  }
}
