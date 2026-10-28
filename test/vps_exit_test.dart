import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vps_exit_config.dart';
import 'package:gsou/services/vps_exit_controller.dart';
import 'package:gsou/services/vps_exit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vps_exit_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'polling timeout leaves an unknown result and never replays apply',
    () async {
      final fake = FakeVpsTransport()..transientFailures = 100;
      final controller = VpsExitController(
        fake,
        pollInterval: Duration.zero,
        maxPolls: 2,
      );
      await controller.connect(exitProfile);
      await controller.apply(const VpsExitPolicy());
      expect(controller.error, contains('暂时无法确认应用结果'));
      expect(fake.calls.where((v) => v['action'] == 'apply').length, 1);
      expect(controller.busy, isFalse);
      controller.dispose();
    },
  );
  test(
    'profile rejects command injection and stores only connection metadata',
    () {
      exitProfile.validate();
      final encoded = exitProfile.toJson();
      expect(
        encoded.keys,
        unorderedEquals([
          'version',
          'host',
          'port',
          'user',
          'identityFile',
          'knownHostsFile',
        ]),
      );
      for (final change in [
        {'host': '-oProxyCommand=x'},
        {'host': 'x;id'},
        {'user': 'root && id'},
        {'port': 0},
        {'port': 65536},
        {'identityFile': 'relative.pem'},
        {'knownHostsFile': 'C:\\keys\nattack'},
        {'password': 'no-secret-storage'},
      ]) {
        expect(
          () => VpsExitProfile.fromJson({...encoded, ...change}),
          throwsFormatException,
        );
      }
    },
  );
  test('domain rules normalize and reject conflicting parents', () {
    final policy = const VpsExitPolicy(
      australiaDomains: [' *.Example.COM. ', 'example.com'],
    ).normalized();
    expect(policy.australiaDomains, ['example.com']);
    for (final value in [
      'https://x.com',
      'x.com/path',
      'x.com:443',
      '127.0.0.1',
      'x..com',
      r'$(id).com',
      'x;id.com',
    ]) {
      expect(
        () => VpsExitPolicy(australiaDomains: [value]).normalized(),
        throwsFormatException,
      );
    }
    expect(
      () => const VpsExitPolicy(
        australiaDomains: ['example.com'],
        directDomains: ['a.example.com'],
      ).normalized(),
      throwsFormatException,
    );
  });
  test('rejects invalid server revisions and unknown task states', () {
    expect(
      () => VpsExitStatus.fromJson({...exitStatus(), 'revision': 'stale'}),
      throwsFormatException,
    );
    expect(
      () => VpsExitJob.fromJson({'id': repeat('b', 32), 'state': 'unknown'}),
      throwsFormatException,
    );
    expect(
      VpsExitStatus.fromJson(exitStatus()).policy.claude,
      VpsExitTarget.australia,
    );
  });
  test(
    'saved profile never includes private key contents or passwords',
    () async {
      SharedPreferences.setMockInitialValues({});
      await VpsExitService.saveProfile(exitProfile);
      final loaded = await VpsExitService.loadProfile();
      expect(loaded!.toJson(), exitProfile.toJson());
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('vps_exit_management_profile_v1')!) as Map;
      expect(stored.containsKey('password'), isFalse);
      expect(stored.containsKey('privateKey'), isFalse);
    },
  );
  test(
    'SSH keeps strict verification and sends policy via stdin only',
    () async {
      final runner = RecordingVpsRunner();
      final service = VpsExitService(
        runner: runner,
        windows: true,
        fileExists: (_) async => true,
      );
      const domain = 'unique-private-rule.example';
      await service.call(exitProfile, 'validate', {
        'policy': const VpsExitPolicy(australiaDomains: [domain]).toJson(),
        'expected_revision': repeat('a', 64),
      });
      final call = runner.calls.single,
          args = (runner.calls.single['arguments'] as List<String>);
      expect(args, contains('StrictHostKeyChecking=yes'));
      expect(
        args,
        containsAll(['-F', 'NUL', 'BatchMode=yes', 'GlobalKnownHostsFile=NUL']),
      );
      expect(args.last, isNot(contains(domain)));
      expect(
        jsonDecode(call['input'] as String)['policy']['australia_domains'],
        [domain],
      );
      expect(args[args.indexOf('-i') + 1], exitProfile.identityFile);
    },
  );
  test('missing key files block before SSH is started', () async {
    final runner = RecordingVpsRunner();
    final service = VpsExitService(
      runner: runner,
      windows: true,
      fileExists: (_) async => false,
    );
    await expectLater(
      service.call(exitProfile, 'status'),
      throwsFormatException,
    );
    expect(runner.calls, isEmpty);
  });
  test('raw SSH stderr and unsupported operations are not exposed', () async {
    final runner = RecordingVpsRunner()
      ..result = const VpsSshResult(255, '', 'DO_NOT_LEAK_SERVER_SECRET');
    final service = VpsExitService(
      runner: runner,
      windows: true,
      fileExists: (_) async => true,
    );
    await expectLater(
      service.call(exitProfile, 'status'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          isNot(contains('DO_NOT_LEAK')),
        ),
      ),
    );
    expect(() => service.call(exitProfile, 'shell'), throwsFormatException);
    expect(
      () => service.call(exitProfile, 'status', {'command': 'id'}),
      throwsFormatException,
    );
  });
  test('deployment packages only the fixed versioned service files', () async {
    final runner = RecordingVpsRunner()
      ..result = VpsSshResult(
        0,
        jsonEncode({
          'ok': true,
          'result': {'installed': true, 'policy_preserved': true},
        }),
        '',
      );
    final service = VpsExitService(
      runner: runner,
      windows: true,
      fileExists: (_) async => true,
    );
    await service.deploy(exitProfile);
    final payload = jsonDecode(runner.calls.single['input'] as String) as Map;
    expect(
      (payload['files'] as Map).keys,
      unorderedEquals(VpsExitService.bundleFiles),
    );
    expect(
      (payload['sha256'] as Map).keys,
      unorderedEquals(VpsExitService.bundleFiles),
    );
    expect(payload.containsKey('config'), isFalse);
    expect(
      (await rootBundle.loadString('assets/vps_exit/install.py')),
      contains('CONFIG.read_bytes() != before'),
    );
  });
  test('opening and refreshing only read current server state', () async {
    final transport = FakeVpsTransport();
    final c = VpsExitController(transport);
    await c.connect(exitProfile);
    await c.refresh();
    expect(transport.calls.map((c) => c['action']), ['status', 'status']);
    expect(c.status!.revision, repeat('a', 64));
    c.dispose();
  });
  test(
    'optimistic revision is preserved and conflicts are never retried',
    () async {
      final fake = FakeVpsTransport()..validateThrows = true;
      final c = VpsExitController(fake);
      await c.connect(exitProfile);
      await c.validate(const VpsExitPolicy(openai: VpsExitTarget.australia));
      expect(c.error, contains('配置已更新'));
      expect(fake.calls.last['data']['expected_revision'], repeat('a', 64));
      expect(fake.calls.where((v) => v['action'] == 'apply'), isEmpty);
      c.dispose();
    },
  );
  test('transient disconnect after acceptance only retries status', () async {
    final fake = FakeVpsTransport()..transientFailures = 1;
    final c = VpsExitController(fake, pollInterval: Duration.zero, maxPolls: 5);
    await c.connect(exitProfile);
    await c.apply(const VpsExitPolicy());
    expect(c.error, isNull);
    expect(c.busy, isFalse);
    expect(fake.calls.where((v) => v['action'] == 'apply').length, 1);
    expect(c.status!.job!.state, 'succeeded');
    c.dispose();
  });
  test(
    'lost submission reply is not replayed and can be reconciled by refresh',
    () async {
      final fake = FakeVpsTransport()..applyThrows = true;
      final c = VpsExitController(fake, pollInterval: Duration.zero);
      await c.connect(exitProfile);
      await c.apply(const VpsExitPolicy());
      expect(c.error, isNotNull);
      await c.refresh();
      expect(c.error, isNull);
      expect(fake.calls.where((v) => v['action'] == 'apply').length, 1);
      c.dispose();
    },
  );
  test(
    'server rollback failure result is shown without success claim',
    () async {
      final fake = FakeVpsTransport()..failJob = true;
      final c = VpsExitController(fake, pollInterval: Duration.zero);
      await c.connect(exitProfile);
      await c.apply(const VpsExitPolicy());
      expect(c.error, '应用失败，已恢复旧规则');
      c.dispose();
    },
  );
  test(
    'rollback ignores an invalid local draft and omits policy from request',
    () async {
      final fake = FakeVpsTransport();
      final c = VpsExitController(fake, pollInterval: Duration.zero);
      await c.connect(exitProfile);
      await c.apply(
        const VpsExitPolicy(australiaDomains: ['invalid url']),
        rollback: true,
      );
      final action = fake.calls.firstWhere((v) => v['action'] == 'rollback');
      expect((action['data'] as Map).containsKey('policy'), isFalse);
      c.dispose();
    },
  );
  test('external unsupported rules cannot be mutated', () async {
    final fake = FakeVpsTransport()..external = true;
    final c = VpsExitController(fake);
    await c.connect(exitProfile);
    await c.apply(const VpsExitPolicy());
    expect(fake.calls.map((v) => v['action']), ['status']);
    c.dispose();
  });
  test('disposing while reading does not notify a closed page', () async {
    final gate = Completer<void>(), fake = FakeVpsTransport();
    fake.statusGate = gate.future;
    final c = VpsExitController(fake);
    final future = c.connect(exitProfile);
    c.dispose();
    gate.complete();
    await future;
    expect(fake.calls.map((v) => v['action']), ['status']);
  });
}
