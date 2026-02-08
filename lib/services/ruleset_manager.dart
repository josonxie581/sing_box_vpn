import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

import '../models/proxy_mode.dart';
import 'dns_manager.dart';
import 'custom_rules_service.dart';
import 'routing_config_service.dart';
import 'geosite_manager.dart';
import 'outbound_binding_service.dart';
import 'config_manager.dart';

/// 规则与配置组装（兼容 sing-box v1.8.0 及以上）
/// 符合官方迁移指南：https://sing-box.sagernet.org/zh/migration/#geoip
class RulesetManager {
  /// 路由规则（规则模式）
  static Future<List<Map<String, dynamic>>> getRuleModeRoutes() async {
    final rules = <Map<String, dynamic>>[
      // 系统 DNS 给内网 DNS 处理，避免被导入代理
      {"network": "udp", "port": 53, "outbound": "dns-out"},
      {"network": "tcp", "port": 53, "outbound": "dns-out"},

      // 私有地址直连（硬编码，无需规则集文件）
      {
        "ip_cidr": [
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "224.0.0.0/4",
          "::1/128",
          "fc00::/7",
          "fe80::/10",
        ],
        "outbound": "direct",
      },
    ];

    // 插入自定义规则（优先级高于路由配置规则）
    try {
      final customRules = CustomRulesService.instance.generateSingBoxRules();
      rules.addAll(customRules);
    } catch (e) {
      print('[ERROR] 加载自定义规则失败: $e');
    }

    // 插入路由配置服务的规则（用户配置的 geosite/geoIP 规则）
    try {
      final routingService = RoutingConfigService.instance;
      if (!routingService.isInitialized) {
        await routingService.initialize();
      }
      final configuredRules = routingService.generateSingBoxRules();
      rules.addAll(configuredRules);
      print('[DEBUG] 规则模式：加载了 ${configuredRules.length} 条路由配置规则');
    } catch (e) {
      print('[ERROR] 加载路由配置规则失败: $e');
      // 降级到默认规则
      rules.addAll([
        {
          "rule_set": ["geoip-private"],
          "outbound": "direct",
        },
        {
          "rule_set": ["geosite-cn"],
          "outbound": "direct",
        },
        {
          "rule_set": ["geoip-cn"],
          "outbound": "direct",
        },
        {
          "rule_set": ["geosite-ads"],
          "outbound": "block",
        },
      ]);
    }

    // 其余流量走 route.final（见 getRouteConfig）
    return rules;
  }

  /// 路由规则（全局模式）
  static List<Map<String, dynamic>> getGlobalModeRoutes() {
    final rules = <Map<String, dynamic>>[
      {"network": "udp", "port": 53, "outbound": "dns-out"},
      {"network": "tcp", "port": 53, "outbound": "dns-out"},

      // 私有地址直连（硬编码，无需规则集文件）
      {
        "ip_cidr": [
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "224.0.0.0/4",
          "::1/128",
          "fc00::/7",
          "fe80::/10",
        ],
        "outbound": "direct",
      },
    ];

    // 在全局模式下，不应用自定义规则，所有流量都走代理
    // 如果用户需要特定规则，应该切换到规则模式或自定义规则模式

    // 添加广告拦截（即使全局模式也保留广告拦截）
    rules.add({
      "rule_set": ["geosite-ads"],
      "outbound": "block",
    });

    // 其余流量走 route.final（proxy）
    return rules;
  }

  /// 路由规则（自定义规则模式）
  static List<Map<String, dynamic>> getCustomModeRoutes() {
    final rules = <Map<String, dynamic>>[
      // 系统 DNS 给内网 DNS 处理，避免被导入代理
      {"network": "udp", "port": 53, "outbound": "dns-out"},
      {"network": "tcp", "port": 53, "outbound": "dns-out"},

      // 私有地址直连（硬编码，无需规则集文件）
      {
        "ip_cidr": [
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "224.0.0.0/4",
          "::1/128",
          "fc00::/7",
          "fe80::/10",
        ],
        "outbound": "direct",
      },
    ];

    // 仅插入自定义规则（不包含默认地理规则）
    try {
      final customRules = CustomRulesService.instance.generateSingBoxRules();
      rules.addAll(customRules);
      print('[DEBUG] 自定义规则模式：加载了 ${customRules.length} 条自定义规则');
    } catch (e) {
      print('[ERROR] 自定义规则模式加载规则失败: $e');
    }

    // 其余流量走 route.final（在自定义模式下通常是proxy）
    return rules;
  }

  /// 根据模式生成 route 配置
  static Future<Map<String, dynamic>> getRouteConfig(ProxyMode mode) async {
    final base = {"auto_detect_interface": true, "final": "proxy"};

    switch (mode) {
      case ProxyMode.rule:
        // 获取基础规则集
        final baseRulesets = [
          "geosite-cn.srs",
          "geoip-cn.srs",
          "geosite-ads.srs",
          "geosite-geolocation-!cn.srs",
        ];

        // 获取用户配置的规则集
        final userRulesets = await _getUserConfiguredRulesets();

        // 合并并去重
        final allRulesets = {...baseRulesets, ...userRulesets}.toList();
        final validRulesets = await _getValidRulesets(allRulesets);

        return {
          ...base,
          "rule_set": validRulesets,
          "rules": await getRuleModeRoutes(),
        };
      case ProxyMode.global:
        // 全局模式只使用基础规则集
        final baseRulesets = [
          "geosite-cn.srs",
          "geosite-ads.srs",
          "geosite-geolocation-!cn.srs",
        ];
        final validRulesets = await _getValidRulesets(baseRulesets);

        return {
          ...base,
          "rule_set": validRulesets,
          "rules": getGlobalModeRoutes(),
        };
      case ProxyMode.custom:
        // 自定义模式包含基础规则集 + 用户配置的规则集
        final baseRulesets = ["geosite-ads.srs"];

        // 获取用户配置的规则集
        final userRulesets = await _getUserConfiguredRulesets();

        // 合并并去重
        final allRulesets = {...baseRulesets, ...userRulesets}.toList();
        final validRulesets = await _getValidRulesets(allRulesets);

        return {
          ...base,
          "rule_set": validRulesets,
          "rules": getCustomModeRoutes(),
        };
    }
  }

  /// 获取有效的规则集配置（仅包含存在的文件）
  static Future<List<Map<String, dynamic>>> _getValidRulesets(
    List<String> filenames,
  ) async {
    final validRulesets = <Map<String, dynamic>>[];

    for (final filename in filenames) {
      try {
        final path = await _getRulesetPath(filename);
        var exists = File(path).existsSync();
        // 若目标文件不存在，尝试从打包的 assets 复制一份到应用数据目录
        if (!exists) {
          try {
            final assetRelPath = filename.startsWith('geoip')
                ? 'assets/rulesets/geo/geoip/$filename'
                : 'assets/rulesets/geo/geosite/$filename';
            final bytes = await rootBundle.load(assetRelPath);
            await File(path).writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
              flush: true,
            );
            exists = true;
            print('[RulesetManager] 从资产复制规则集: $assetRelPath -> $path');
          } catch (_) {
            // 忽略复制失败，继续走原有不存在分支日志
          }
        }

        if (exists) {
          final tag = filename.replaceAll('.srs', '');
          validRulesets.add({
            "tag": tag,
            "type": "local",
            "format": "binary",
            "path": path,
          });
        } else {
          print('[RulesetManager] 规则集文件不存在: $path');
        }
      } catch (e) {
        print('[RulesetManager] 获取规则集路径失败 $filename: $e');
      }
    }

    if (validRulesets.isEmpty) {
      print('[RulesetManager] 警告: 没有找到任何有效的规则集文件');
    } else {
      print('[RulesetManager] 找到 ${validRulesets.length} 个有效规则集');
    }

    return validRulesets;
  }

  /// 获取用户配置的规则集文件名列表
  static Future<List<String>> _getUserConfiguredRulesets() async {
    try {
      final routingService = RoutingConfigService.instance;
      if (!routingService.isInitialized) {
        await routingService.initialize();
      }

      final configuredRulesets = routingService.getConfiguredRulesets();
      return configuredRulesets.map((ruleset) => '$ruleset.srs').toList();
    } catch (e) {
      print('[RulesetManager] 获取用户配置规则集失败: $e');
      return [];
    }
  }

  /// 获取规则集文件路径
  static Future<String> _getRulesetPath(String filename) async {
    try {
      // 直接根据规则名计算目标路径，按需检查，避免全量扫描
      final geositeManager = GeositeManager();
      final rulesetName = filename.endsWith('.srs')
          ? filename.substring(0, filename.length - 4)
          : filename;
      final directPath = await geositeManager.getRulesetPath(rulesetName);
      if (File(directPath).existsSync()) {
        return directPath;
      }
    } catch (e) {
      print('[RulesetManager] 计算规则集路径失败: $e');
    }

    // 回退到旧版本路径查找
    return _getFallbackPath(filename);
  }

  /// 获取规则集文件路径（支持多个路径查找）
  static String _getFallbackPath(String filename) {
    if (Platform.isWindows) {
      // 降级到原有的应用程序目录
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      String rulesetPath;

      if (filename.startsWith("geoip")) {
        rulesetPath =
            "$exeDir\\data\\flutter_assets\\assets\\rulesets\\geo\\geoip\\$filename";
      } else {
        rulesetPath =
            "$exeDir\\data\\flutter_assets\\assets\\rulesets\\geo\\geosite\\$filename";
      }

      // 如果生产环境路径不存在，尝试开发环境路径
      if (!File(rulesetPath).existsSync()) {
        final devPath = Directory.current.path;
        if (filename.startsWith("geoip")) {
          rulesetPath = "$devPath\\assets\\rulesets\\geo\\geoip\\$filename";
        } else {
          rulesetPath = "$devPath\\assets\\rulesets\\geo\\geosite\\$filename";
        }
      }

      return rulesetPath;
    } else {
      // 其他平台的路径处理
      if (filename.startsWith("geoip")) {
        return "assets/rulesets/geo/geoip/$filename";
      } else {
        return "assets/rulesets/geo/geosite/$filename";
      }
    }
  }

  /// 出站集合
  static List<Map<String, dynamic>> getOutbounds(
    Map<String, dynamic> proxyConfig,
  ) {
    return [
      proxyConfig,
      {"tag": "direct", "type": "direct"},
      {"tag": "block", "type": "block"},
      {"tag": "dns-out", "type": "dns"},
    ];
  }

  /// DNS 配置
  static Map<String, dynamic> getDnsConfig(
    ProxyMode mode, {
    required bool useTun,
  }) {
    final dns = DnsManager();
    return dns.generateDnsConfig(
      // 只有规则模式启用DNS分流
      // 全局模式下所有DNS查询都应该通过代理DNS，不使用本地DNS
      preferRuleRouting: mode == ProxyMode.rule,
      useTun: useTun,
      forceProxyDns: mode == ProxyMode.global, // 全局模式强制使用代理DNS
    );
  }

  /// 生成完整 sing-box 配置
  static Future<Map<String, dynamic>> generateSingBoxConfig({
    required Map<String, dynamic> proxyConfig,
    required ProxyMode mode,
    int? localPort,
    bool useTun = false,
    bool tunStrictRoute = false,
    String? preferredTunStack,
    bool enableClashApi = false,
    int clashApiPort = 9090,
    String clashApiSecret = '',
    int? tunMtu,
    bool enableIpv6 = false,
  }) async {
    // 初始化自定义规则服务
    try {
      await CustomRulesService.instance.initialize();
    } catch (e) {
      print('[ERROR] 自定义规则服务初始化失败: $e');
    }

    // 确保配置已加载（供多出站绑定解析）
    try {
      final cfgMgr = ConfigManager();
      if (cfgMgr.configs.isEmpty) {
        await cfgMgr.loadConfigs();
      }
    } catch (e) {
      print('[WARN] 加载配置失败，可能影响多出站绑定: $e');
    }

    // 初始化多出站绑定服务
    final outboundBinding = OutboundBindingService.instance;
    try {
      if (!outboundBinding.isInitialized) {
        await outboundBinding.initialize();
      }
    } catch (e) {
      print('[WARN] 初始化多出站绑定服务失败: $e');
    }
    final inbounds = <Map<String, dynamic>>[];

    if (useTun) {
      if (Platform.isAndroid) {
        // Android: 使用外部 VpnService 建立的 TUN FD，最小化配置以避免接口配置权限
        inbounds.add({
          "tag": "tun-in",
          "type": "tun",
          "auto_route": false,
          "strict_route": false,
          "stack": "gvisor",
          // 不设置 address/mtu/route 等，由原生注入 fd 后直接使用
        });
      } else {
        inbounds.add({
          "tag": "tun-in",
          "type": "tun",
          // 使用稳定的接口名称
          if (Platform.isWindows) "interface_name": "sing-box",
          // IPv4地址配置，仅在明确启用IPv6且VPS支持时才添加IPv6
          "address": enableIpv6
              ? ["172.19.0.1/30", "2001:db8::1/128"]
              : ["172.19.0.1/30"],

          // 使用稳定的MTU设置
          "mtu": tunMtu ?? 1500,
          "auto_route": true,
          "strict_route": tunStrictRoute,

          // 保守的嗅探配置
          "sniff": true,

          // 添加稳定性配置
          "domain_strategy": "prefer_ipv4",
          // 默认 system；Windows 下为 Wintun
          "stack": Platform.isWindows ? 'system' : 'system',

          if (Platform.isWindows) "endpoint_independent_nat": false,

          // 路由表配置
          "inet4_route_address": ["0.0.0.0/1", "128.0.0.0/1"],
        });
      }
    }

    inbounds.add({
      "tag": "mixed-in",
      "type": "mixed",
      "listen": "::",
      "listen_port": (localPort == null || localPort <= 0) ? 7890 : localPort,
      "sniff": true,
      "users": [],
    });

    // 固化一个延时测试专用 inbound（SOCKS，不暴露到 0.0.0.0，只在本机使用）
    inbounds.add({
      "tag": "latency-test-in",
      "type": "socks",
      "listen": "127.0.0.1",
      "listen_port": 17890,
      "sniff": false,
      "users": [],
    });

    // 只调用一次 getRouteConfig，避免重复日志与重复扫描
    final routeConfig = await getRouteConfig(mode);

    // 先组装基础 outbounds
    final baseOutbounds = getOutbounds({"tag": "proxy", ...proxyConfig});

    // 注入额外出站（proxy-a/proxy-b）
    try {
      final extra = outboundBinding.buildAdditionalOutbounds();
      if (extra.isNotEmpty) {
        baseOutbounds.addAll(extra);
      }
    } catch (e) {
      print('[WARN] 生成额外出站失败: $e');
    }

    // 计算最终出站标签（场景），若目标不存在则回退 proxy
    var finalTag = 'proxy';
    try {
      finalTag = outboundBinding.finalOutboundTag;
      final available = baseOutbounds
          .map((e) => (e['tag'] ?? '').toString())
          .where((t) => t.isNotEmpty)
          .toSet();
      if (!available.contains(finalTag)) {
        finalTag = 'proxy';
      }
    } catch (_) {}

    // 可用出站标签集合，用于校验规则引用
    final availableTags = baseOutbounds
        .map((e) => (e['tag'] ?? '').toString())
        .where((t) => t.isNotEmpty)
        .toSet();

    // 取出已有路由规则，并做一次健壮性回退：若规则引用了不存在的出站，则回退到 proxy
    List<Map<String, dynamic>> _sanitizeRules(
      List<Map<String, dynamic>> rules,
    ) {
      return rules.map((r) {
        final outbound = r['outbound'];
        if (outbound is String && outbound.isNotEmpty) {
          if (!availableTags.contains(outbound)) {
            // 打印并回退
            print('[WARN] 规则引用的出站不存在: "$outbound"，已回退为 "proxy"');
            return {...r, 'outbound': 'proxy'};
          }
        }
        return r;
      }).toList();
    }

    final inboundBypassRule = {
      "inbound": ["latency-test-in"],
      "outbound": "direct",
    };

    // 在 Android TUN 模式下，劫持系统 DNS（UDP/53）给内部 dns-out，避免系统直连 DNS 失败或被污染
    final androidTunDnsHijackRule = (useTun && Platform.isAndroid)
        ? <String, dynamic>{
            "protocol": ["dns"], // sing-box 支持的速记：等价于 dst port 53/udp
            "outbound": "dns-out",
          }
        : null;

    final mergedRules = <Map<String, dynamic>>[
      inboundBypassRule,
      if (androidTunDnsHijackRule != null) androidTunDnsHijackRule,
      ...?(routeConfig)["rules"] as List?,
    ];
    final sanitizedRules = _sanitizeRules(mergedRules);

    final config = <String, dynamic>{
      "log": {"level": "fatal", "timestamp": true},
      "dns": getDnsConfig(mode, useTun: useTun),
      "inbounds": inbounds,
      "outbounds": baseOutbounds,
      "route": {
        ...routeConfig,
        // 覆盖最终出站标签
        "final": finalTag,
        "rules": sanitizedRules,
      },
    };

    // Inject endpoints (e.g., Tailscale) if enabled in DNS manager
    try {
      final eps = DnsManager().generateEndpointsConfig();
      if (eps.isNotEmpty) {
        config['endpoints'] = eps;
      }
    } catch (e) {
      print('[WARN] 生成 endpoints 失败: $e');
    }

    // 如果用户开启但运行时判定不支持 IPv6（调用方会传 enableIpv6=false），则确保 DNS 策略强制 ipv4_only 并去掉 fakeip 的 inet6_range
    if (!enableIpv6) {
      try {
        final dns = config['dns'] as Map<String, dynamic>?;
        if (dns != null) {
          dns['strategy'] = 'ipv4_only';
          final fakeip = dns['fakeip'];
          if (fakeip is Map<String, dynamic>) {
            fakeip.remove('inet6_range');
          }
        }
      } catch (e) {
        print('[WARN] 应用 IPv4-only DNS 策略失败: $e');
      }
    }

    if (enableClashApi) {
      config["experimental"] = {
        "clash_api": {
          'external_controller': '127.0.0.1:$clashApiPort',
          'secret': clashApiSecret,
        },
      };
    }

    return config;
  }
}
