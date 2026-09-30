import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/proxy_mode.dart';
import 'package:gsou/services/builtin_proxy_rules.dart';
import 'package:gsou/services/pac_file_manager.dart';

// Execute the generated JavaScript so syntax, matching, and fallback behavior
// are checked together. Node is used only by this test, never by the app.
Future<List<String>> evaluatePac(String content, List<String> hosts) async {
  final result = await Process.run('node', [
    '-e',
    r'''
const vm = require('node:vm');
const input = JSON.parse(process.argv[1]);
const context = {
  dnsDomainIs: (host, suffix) => host.endsWith(suffix),
  isPlainHostName: host => !host.includes('.'),
  isInNet: () => false,
  shExpMatch: (value, pattern) => new RegExp('^' + pattern
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\*/g, '.*').replace(/\?/g, '.') + '$').test(value)
};
vm.createContext(context);
vm.runInContext(input.content, context, {timeout: 1000});
process.stdout.write(JSON.stringify(input.hosts.map(host =>
  context.FindProxyForURL('https://' + host + '/', host))));
''',
    jsonEncode({'content': content, 'hosts': hosts}),
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return (jsonDecode(result.stdout as String) as List).cast<String>();
}

void main() {
  final manager = PacFileManager();
  const port = 18890;
  const expectedProxy = 'PROXY 127.0.0.1:$port; SOCKS5 127.0.0.1:$port';
  final serviceHosts = [
    ...BuiltinProxyRules.domainSuffixes,
    ...BuiltinProxyRules.domainSuffixes.map((domain) => 'child.$domain'),
    ...BuiltinProxyRules.domains,
    'API.OPENAI.COM.',
    'CLAUDE.AI.',
    'chatgpt-async-webps-prod-eastus-1.webpubsub.azure.com',
  ];
  final unrelatedHosts = [
    'openai.com.evil.example',
    'notopenai.com',
    'cdn.other.example',
    'other.blob.core.windows.net',
    'other.workos.com',
    'other.cloudfront.net',
    'www.baidu.com',
  ];
  late Directory originalDirectory;
  late Directory fixtureDirectory;

  setUpAll(() async {
    originalDirectory = Directory.current;
    final parent = Directory('build/singbox-core/pac-checks').absolute;
    await parent.create(recursive: true);
    fixtureDirectory = await parent.createTemp('fixture-');
  });

  setUp(() {
    Directory.current = fixtureDirectory;
    manager.invalidateCache();
  });

  tearDown(() {
    Directory.current = originalDirectory;
  });

  for (final mode in ProxyMode.values) {
    test('AI PAC ${mode.value} has no direct fallback', () async {
      final content = manager.getCurrentPacContent(port, mode);
      expect(
        await evaluatePac(content, serviceHosts),
        everyElement(expectedProxy),
      );
      expect(
        await evaluatePac(content, ['www.baidu.com']),
        mode == ProxyMode.global ? everyElement(contains('PROXY')) : ['DIRECT'],
      );
    });
  }

  test(
    'AI overrides a custom DIRECT PAC without matching unrelated hosts',
    () async {
      final file = File('${fixtureDirectory.path}/all-direct.pac');
      await file.writeAsString(
        'function FindProxyForURL(url, host) { return "DIRECT"; }',
      );
      final content = manager.loadCustomPacFile(file.path, port)!;
      expect(
        await evaluatePac(content, serviceHosts),
        everyElement(expectedProxy),
      );
      expect(
        await evaluatePac(content, unrelatedHosts),
        everyElement('DIRECT'),
      );
    },
  );

  test(
    'AI overrides automatically loaded external PAC files in every mode',
    () async {
      final externalDirectory = Directory('${fixtureDirectory.path}/pac_files');
      await externalDirectory.create();
      for (final filename in ['rule_mode.pac', 'global_mode.pac']) {
        await File('${externalDirectory.path}/$filename').writeAsString(
          'function FindProxyForURL(url, host) { return "DIRECT"; }',
        );
      }
      for (final mode in ProxyMode.values) {
        final content = manager.getCurrentPacContent(port, mode);
        expect(
          await evaluatePac(content, serviceHosts),
          everyElement(expectedProxy),
        );
        expect(
          await evaluatePac(content, unrelatedHosts),
          everyElement('DIRECT'),
        );
      }
    },
  );
}
