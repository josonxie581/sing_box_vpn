import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gsou/models/custom_rule.dart' as custom;
import 'package:gsou/models/proxy_mode.dart';
import 'package:gsou/models/routing_rule_config.dart';
import 'package:gsou/models/vpn_config.dart';
import 'package:gsou/services/dns_manager.dart';
import 'package:gsou/services/ruleset_manager.dart';
import 'package:gsou/services/builtin_proxy_rules.dart';
import 'package:gsou/services/custom_rules_service.dart';
import 'package:gsou/services/outbound_binding_service.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.directory);
  final String directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
  @override
  Future<String?> getExternalStoragePath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dns = DnsManager();
  final fixtureDir = Directory('build/singbox-core/config-checks').absolute;
  final dllFile = File('windows/singbox.dll').absolute;
  final canCheckCore = Platform.isWindows && dllFile.existsSync();
  String takeNativeLogs() {
    final library = DynamicLibrary.open(dllFile.path);
    final drain = library
        .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'SbDrainLogs',
        );
    final free = library
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('FreeCString');
    final pointer = drain();
    try {
      return pointer.toDartString();
    } finally {
      free(pointer);
    }
  }

  void validateNativeConfig(Map<String, dynamic> config) {
    final library = DynamicLibrary.open(dllFile.path);
    final check = library
        .lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)
        >('TestConfig');
    final error = library
        .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'SbGetLastError',
        );
    final free = library
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('FreeCString');
    final input = jsonEncode(config).toNativeUtf8();
    try {
      final result = check(input);
      final message = error();
      final detail = message.toDartString();
      free(message);
      expect(result, 0, reason: detail);
    } finally {
      calloc.free(input);
    }
  }

  Future<void> startAndStopNativeConfig(
    Map<String, dynamic> config, {
    Future<void> Function()? whileRunning,
  }) async {
    takeNativeLogs();
    final library = DynamicLibrary.open(dllFile.path);
    final start = library
        .lookupFunction<
          Int64 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)
        >('StartSingBox');
    final stop = library.lookupFunction<Int64 Function(), int Function()>(
      'StopSingBox',
    );
    final running = library.lookupFunction<Int64 Function(), int Function()>(
      'IsRunning',
    );
    final error = library
        .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'SbGetLastError',
        );
    final free = library
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('FreeCString');
    final input = jsonEncode(config).toNativeUtf8();
    var started = false;
    try {
      final result = start(input);
      started = result == 0;
      final message = error();
      final detail = message.toDartString();
      free(message);
      expect(result, 0, reason: detail);
      expect(running(), 1);
      if (whileRunning != null) await whileRunning();
    } finally {
      calloc.free(input);
      if (started) {
        expect(stop(), 0);
        expect(running(), 0);
      }
      expect(takeNativeLogs(), isNot(contains('[NATIVE]')));
    }
  }

  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    await fixtureDir.create(recursive: true);
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(fixtureDir.path);
    // Make real bundled rule sets available to the config assembler.
    for (final type in ['geosite', 'geoip']) {
      final target = Directory('${fixtureDir.path}/rulesets/$type');
      await target.create(recursive: true);
      for (final file in Directory(
        'assets/rulesets/geo/$type',
      ).listSync().whereType<File>()) {
        await file.copy('${target.path}/${file.uri.pathSegments.last}');
      }
    }
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await dns.init();
  });

  test(
    'latency inbound bypasses sniff before the remote TCP handshake',
    () async {
      final config = await RulesetManager.generateSingBoxConfig(
        proxyConfig: {'type': 'socks', 'server': '127.0.0.1', 'server_port': 9},
        mode: ProxyMode.rule,
        useTun: true,
      );
      final rules = (config['route'] as Map)['rules'] as List;
      final first = rules.first as Map;
      expect(first['inbound'], ['latency-test-in']);
      expect(first['outbound'], 'direct');
      for (final rule in rules.where((r) => r['action'] == 'sniff')) {
        expect(rule['inbound'], isNot(contains('latency-test-in')));
      }
    },
  );

  test('startup errors remain visible without native debug logs', () {
    takeNativeLogs();
    final library = DynamicLibrary.open(dllFile.path);
    final start = library
        .lookupFunction<
          Int64 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)
        >('StartSingBox');
    final input = jsonEncode({
      'inbounds': [
        {'type': 'invalid-test-protocol'},
      ],
    }).toNativeUtf8();
    try {
      expect(start(input), -2);
      final logs = takeNativeLogs();
      expect(logs, contains('配置解析失败'));
      expect(logs, isNot(contains('[NATIVE]')));
    } finally {
      calloc.free(input);
    }
  }, skip: !canCheckCore);

  test('block actions survive the removal of special outbounds', () {
    final configured = RoutingRuleConfig(
      id: 'test',
      name: 'test',
      type: RuleType.domainSuffix,
      ruleset: 'example.com',
      outbound: OutboundAction.block,
      priority: 1,
    ).toSingBoxRule();
    final manual = custom.CustomRule(
      id: 'manual',
      name: 'manual',
      description: 'test',
      createdAt: DateTime.utc(2026),
      type: custom.RuleType.domain,
      value: 'example.com',
      outbound: 'block',
    ).toSingBoxRule();
    for (final rule in [configured, manual]) {
      expect(rule['action'], 'reject');
      expect(rule.containsKey('outbound'), isFalse);
    }
  });

  test(
    'DNS migration preserves custom ports, paths, and bootstrap resolution',
    () async {
      SharedPreferences.setMockInitialValues({
        'dns_servers': [
          const DnsServer(
            name: 'DoH',
            address: 'https://dns.example.com:8443/custom',
            type: DnsServerType.doh,
            detour: 'proxy',
          ).toJsonString(),
          const DnsServer(
            name: 'IPv6',
            address: '[2001:db8::1]:5353',
            type: DnsServerType.udp,
            detour: 'direct',
          ).toJsonString(),
        ],
      });
      await dns.init();
      final servers = dns.generateDnsConfig()['servers'] as List;
      final doh = servers.firstWhere((s) => s['tag'] == 'doh') as Map;
      expect(doh['type'], 'https');
      expect(doh['server'], 'dns.example.com');
      expect(doh['server_port'], 8443);
      expect(doh['path'], '/custom');
      expect(doh['detour'], 'proxy');
      expect((doh['domain_resolver'] as Map)['server'], 'local');
      final ipv6 = servers.firstWhere((s) => s['tag'] == 'ipv6') as Map;
      expect(ipv6['server'], '2001:db8::1');
      expect(ipv6['server_port'], 5353);
      expect(ipv6.containsKey('detour'), isFalse);
      expect(dns.generateDnsConfig()['final'], 'ipv6');
      for (final useTun in [false, true]) {
        final routed = dns.generateDnsConfig(
          preferRuleRouting: true,
          useTun: useTun,
        );
        expect(routed['final'], 'ipv6');
        final cnRule = (routed['rules'] as List).firstWhere(
          (rule) =>
              (rule['rule_set'] as List?)?.contains('geosite-cn') ?? false,
        );
        expect(cnRule['server'], 'ipv6');
      }
    },
  );

  final protocolSettings = <String, Map<String, dynamic>>{
    'shadowsocks': {'password': 'test'},
    'shadowsocks-2022': {'password': 'AAAAAAAAAAAAAAAAAAAAAA=='},
    'vmess': {'uuid': '00000000-0000-4000-8000-000000000001'},
    'vless': {'uuid': '00000000-0000-4000-8000-000000000001'},
    'trojan': {'password': 'test'},
    'hysteria': {'password': 'test', 'up_mbps': 10, 'down_mbps': 20},
    'hysteria2': {'password': 'test', 'up': '10 Mbps', 'down': '20 Mbps'},
    'tuic': {
      'uuid': '00000000-0000-4000-8000-000000000001',
      'password': 'test',
    },
    'anytls': {'password': 'test'},
    'shadowtls': {'password': 'test', 'version': 3},
    'socks': {},
    'http': {},
    'wireguard': {
      'privateKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'peerPublicKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'localAddress': ['10.0.0.2/32'],
    },
  };

  test(
    'AI DNS cannot fall back to direct or static mappings in any mode',
    () async {
      SharedPreferences.setMockInitialValues({
        'dns_servers': [
          const DnsServer(
            name: 'Direct only',
            address: '223.5.5.5',
            type: DnsServerType.udp,
            detour: 'direct',
          ).toJsonString(),
        ],
        'static_ip_mappings': [
          jsonEncode({
            'domain': 'api.openai.com',
            'ipAddress': '127.0.0.1',
            'enabled': true,
          }),
        ],
      });
      await dns.init();
      for (final mode in ProxyMode.values) {
        for (final useTun in [false, true]) {
          final config = RulesetManager.getDnsConfig(mode, useTun: useTun);
          final rules = config['rules'] as List;
          final aiRules = rules
              .where(
                (rule) =>
                    (rule['domain_suffix'] as List?)?.contains('openai.com') ??
                    false,
              )
              .toList();
          expect(aiRules, isNotEmpty);
          expect(rules.indexOf(aiRules.first), 0);
          final proxyRule = aiRules.firstWhere(
            (rule) => rule['query_type'] == null,
          );
          final resolver = (config['servers'] as List).firstWhere(
            (server) => server['tag'] == proxyRule['server'],
          );
          expect(resolver['detour'], 'proxy');
          if (useTun) expect(aiRules.first['server'], 'fakeip');
          expect(
            aiRules.first['domain_suffix'],
            contains('claudeusercontent.com'),
          );
        }
      }
    },
  );

  test(
    'AI connections override custom blocking and a direct final outbound',
    () async {
      await CustomRulesService.instance.initialize();
      await OutboundBindingService.instance.initialize();
      await OutboundBindingService.instance.setFinalOutboundTag('direct');
      await CustomRulesService.instance.addRule(
        custom.CustomRule(
          id: 'ai-conflict',
          name: 'block all',
          description: 'fixture',
          createdAt: DateTime.utc(2026),
          type: custom.RuleType.domainRegex,
          value: '.*',
          outbound: 'block',
        ),
      );
      final sockets = <Socket>[];
      final destinations = <String>[];
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      proxy.listen((socket) {
        sockets.add(socket);
        final buffer = <int>[];
        var stage = 0;
        socket.listen((bytes) {
          buffer.addAll(bytes);
          if (stage == 0) {
            if (buffer.length < 2 || buffer.length < 2 + buffer[1]) return;
            buffer.removeRange(0, 2 + buffer[1]);
            socket.add([5, 0]);
            stage = 1;
          }
          if (stage == 1) {
            if (buffer.length < 5) return;
            final addressLength = switch (buffer[3]) {
              1 => 4,
              3 => 1 + buffer[4],
              4 => 16,
              _ => 0,
            };
            final length = 4 + addressLength + 2;
            if (buffer.length < length) return;
            expect(
              buffer[3],
              3,
              reason: 'Destination domains should reach the proxy',
            );
            destinations.add(utf8.decode(buffer.sublist(5, 4 + addressLength)));
            buffer.removeRange(0, length);
            socket.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
            stage = 2;
          }
          if (stage == 2 && utf8.decode(buffer).contains('\r\n\r\n')) {
            socket.add(
              utf8.encode(
                'HTTP/1.1 200 OK\r\nContent-Length: 7\r\nConnection: close\r\n\r\nproxied',
              ),
            );
            socket.close();
            stage = 3;
          }
        });
      });
      try {
        final reservation = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final port = reservation.port;
        await reservation.close();
        final config = await RulesetManager.generateSingBoxConfig(
          proxyConfig: {
            'type': 'socks',
            'server': '127.0.0.1',
            'server_port': proxy.port,
          },
          mode: ProxyMode.custom,
        );
        expect((config['route'] as Map)['final'], 'direct');
        config['inbounds'] = [
          {
            'type': 'mixed',
            'tag': 'mixed-in',
            'listen': '127.0.0.1',
            'listen_port': port,
          },
        ];
        Future<String> requestThroughMixed(String host) async {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            port,
            timeout: const Duration(seconds: 5),
          );
          try {
            socket.write(
              'GET http://$host/ HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
            );
            return await utf8.decoder
                .bind(socket)
                .join()
                .timeout(const Duration(seconds: 5));
          } finally {
            socket.destroy();
          }
        }

        await startAndStopNativeConfig(
          config,
          whileRunning: () async {
            for (final host in [
              'api.openai.com',
              'chatgpt.com',
              'api.anthropic.com',
              'claude.ai',
              'files.oaiusercontent.com',
              'bridge.claudeusercontent.com',
              'challenges.cloudflare.com',
              'chatgpt-async-webps-prod-eastus-1.webpubsub.azure.com',
            ]) {
              expect(await requestThroughMixed(host), contains('proxied'));
              expect(destinations.last, host);
            }
            final count = destinations.length;
            expect(
              await requestThroughMixed('unrelated.example'),
              isNot(contains('proxied')),
            );
            expect(destinations.length, count);
          },
        );
      } finally {
        for (final socket in sockets) {
          socket.destroy();
        }
        await proxy.close();
        await CustomRulesService.instance.clearAllRules();
        await OutboundBindingService.instance.setFinalOutboundTag('proxy');
      }
    },
    skip: !canCheckCore,
  );

  for (final mode in ProxyMode.values) {
    for (final useTun in [false, true]) {
      test(
        'v1.14 core starts ${mode.value} with ${useTun ? 'TUN' : 'mixed'} DNS settings',
        () async {
          SharedPreferences.setMockInitialValues({
            'dns_servers': [
              const DnsServer(
                name: 'Google',
                address: '8.8.8.8',
                type: DnsServerType.udp,
                detour: 'proxy',
              ).toJsonString(),
              const DnsServer(
                name: '阿里DNS',
                address: '223.5.5.5',
                type: DnsServerType.udp,
                detour: 'direct',
              ).toJsonString(),
            ],
          });
          await dns.init();
          final config = await RulesetManager.generateSingBoxConfig(
            proxyConfig: {
              'type': 'socks',
              'server': '127.0.0.1',
              'server_port': 9,
            },
            mode: mode,
            useTun: useTun,
            enableClashApi: false,
          );
          // Exercise instance.Start without changing the host's TUN or routes.
          // Loopback port 0 lets Windows choose unused listener ports.
          config['inbounds'] = (config['inbounds'] as List)
              .where((inbound) => inbound['type'] != 'tun')
              .map(
                (inbound) => {
                  ...inbound as Map<String, dynamic>,
                  'listen': '127.0.0.1',
                  'listen_port': 0,
                },
              )
              .toList();
          await startAndStopNativeConfig(config);
        },
        skip: !canCheckCore,
      );
    }
  }
  for (final entry in protocolSettings.entries) {
    test('v1.14 core accepts ${entry.key} node configuration', () async {
      final node = VPNConfig(
        id: entry.key,
        name: entry.key,
        type: entry.key,
        server: '192.0.2.2',
        port: 443,
        settings: entry.value,
      );
      final config = await node.toSingBoxConfig(mode: ProxyMode.global);
      validateNativeConfig(config);
    }, skip: !canCheckCore);
  }

  for (final mode in ProxyMode.values) {
    for (final useTun in [false, true]) {
      for (final ipv6 in [false, true]) {
        final name =
            '${mode.value}-${useTun ? 'tun' : 'mixed'}-${ipv6 ? 'ipv6' : 'ipv4'}';
        test(
          'v1.14 core accepts $name including static DNS mappings',
          () async {
            SharedPreferences.setMockInitialValues({
              'dns_servers': [
                const DnsServer(
                  name: 'Google',
                  address: '8.8.8.8',
                  type: DnsServerType.udp,
                  detour: 'proxy',
                ).toJsonString(),
                const DnsServer(
                  name: 'Ali',
                  address: '223.5.5.5',
                  type: DnsServerType.udp,
                  detour: 'direct',
                ).toJsonString(),
              ],
              'static_ip_mappings': [
                jsonEncode({
                  'domain': 'static.example.com',
                  'ipAddress': '192.0.2.1',
                  'enabled': true,
                }),
              ],
            });
            await dns.init();
            final config = await RulesetManager.generateSingBoxConfig(
              proxyConfig: {
                'type': 'socks',
                'server': 'proxy.example.com',
                'server_port': 1080,
              },
              mode: mode,
              useTun: useTun,
              enableIpv6: ipv6,
              enableClashApi: true,
            );
            final routeRules = (config['route'] as Map)['rules'] as List;
            final aiRuleIndex = routeRules.indexWhere(
              (rule) =>
                  (rule['domain_suffix'] as List?)?.contains('openai.com') ??
                  false,
            );
            expect(aiRuleIndex, greaterThanOrEqualTo(0));
            final aiRule = routeRules[aiRuleIndex] as Map;
            expect(aiRule['outbound'], 'proxy');
            expect(
              aiRule['domain_suffix'],
              containsAll(BuiltinProxyRules.domainSuffixes),
            );
            expect(aiRule['domain'], containsAll(BuiltinProxyRules.domains));
            final conflictingIndex = routeRules.indexWhere(
              (rule) =>
                  // The local diagnostic inbound is deliberately isolated.
                  // AI traffic from mixed/TUN must still precede direct rules.
                  !((rule['inbound'] as List?)?.contains('latency-test-in') ??
                      false) &&
                  (rule['outbound'] == 'direct' || rule['action'] == 'reject'),
            );
            expect(aiRuleIndex, lessThan(conflictingIndex));
            final voiceRule = routeRules.firstWhere(
              (rule) => rule['port'] == 3478,
            );
            expect(voiceRule['network'], 'udp');
            expect(voiceRule['outbound'], 'proxy');
            expect(routeRules.indexOf(voiceRule), lessThan(conflictingIndex));
            if (useTun) {
              final tun = (config['inbounds'] as List).firstWhere(
                (inbound) => inbound['type'] == 'tun',
              );
              expect(
                tun['route_address'],
                ipv6
                    ? containsAll(['::/1', '8000::/1'])
                    : isNot(contains('::/1')),
              );
            }
            final file = File('${fixtureDir.path}/$name.json');
            await file.writeAsString(jsonEncode(config));
            final library = DynamicLibrary.open(dllFile.path);
            final version = library
                .lookupFunction<
                  Pointer<Utf8> Function(),
                  Pointer<Utf8> Function()
                >('GetVersion');
            final free = library
                .lookupFunction<
                  Void Function(Pointer<Utf8>),
                  void Function(Pointer<Utf8>)
                >('FreeCString');
            final versionString = version();
            expect(versionString.toDartString(), 'sing-box 1.14.2');
            free(versionString);
            final check = library
                .lookupFunction<
                  Int32 Function(Pointer<Utf8>),
                  int Function(Pointer<Utf8>)
                >('TestConfig');
            final error = library
                .lookupFunction<
                  Pointer<Utf8> Function(),
                  Pointer<Utf8> Function()
                >('SbGetLastError');
            final input = jsonEncode(config).toNativeUtf8();
            try {
              final result = check(input);
              final lastError = error();
              final message = lastError.toDartString();
              free(lastError);
              expect(result, 0, reason: '$name: $message');
            } finally {
              calloc.free(input);
            }
          },
          skip: !canCheckCore,
        );
      }
    }
  }
}
