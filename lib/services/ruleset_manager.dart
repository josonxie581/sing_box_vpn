import 'dart:io';

import '../models/proxy_mode.dart';
import 'dns_manager.dart';
import 'custom_rules_service.dart';
import 'routing_config_service.dart';
import 'geosite_manager.dart';

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
      {"ip_cidr": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16", "224.0.0.0/4", "::1/128", "fc00::/7", "fe80::/10"], "outbound": "direct"},
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
        {"rule_set": ["geoip-private"], "outbound": "direct"},
        {"rule_set": ["geosite-cn"], "outbound": "direct"},
        {"rule_set": ["geoip-cn"], "outbound": "direct"},
        {"rule_set": ["geosite-ads"], "outbound": "block"},
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
      {"ip_cidr": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16", "224.0.0.0/4", "::1/128", "fc00::/7", "fe80::/10"], "outbound": "direct"},
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
      {"ip_cidr": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16", "224.0.0.0/4", "::1/128", "fc00::/7", "fe80::/10"], "outbound": "direct"},
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
        final baseRulesets = [
          "geosite-ads.srs",
        ];

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
  static Future<List<Map<String, dynamic>>> _getValidRulesets(List<String> filenames) async {
    final validRulesets = <Map<String, dynamic>>[];

    for (final filename in filenames) {
      try {
        final path = await _getRulesetPath(filename);
        if (File(path).existsSync()) {
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
      // 首先尝试从 GeositeManager 获取规则集路径
      final geositeManager = GeositeManager();
      final rulesetName = filename.endsWith('.srs')
          ? filename.substring(0, filename.length - 4)
          : filename;

      // 检查 GeositeManager 中是否有这个规则集
      final downloadedRulesets = await geositeManager.getDownloadedRulesets();
      if (downloadedRulesets.contains(rulesetName)) {
        return await geositeManager.getRulesetPath(rulesetName);
      }
    } catch (e) {
      print('[RulesetManager] 从 GeositeManager 获取路径失败: $e');
    }

    // 降级到旧版本路径查找
    return _getFallbackPath(filename);
  }

  /// 获取规则集文件路径（支持多个路径查找）
  static String _getFallbackPath(String filename) {
    if (Platform.isWindows) {
      // 降级到原有的应用程序目录
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      String rulesetPath;

      if (filename.startsWith("geoip")) {
        rulesetPath = "$exeDir\\data\\flutter_assets\\assets\\rulesets\\geo\\geoip\\$filename";
      } else {
        rulesetPath = "$exeDir\\data\\flutter_assets\\assets\\rulesets\\geo\\geosite\\$filename";
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
    final inbounds = <Map<String, dynamic>>[];

    if (useTun) {
      inbounds.add({
        "tag": "tun-in",
        "type": "tun",
        // 使用稳定的接口名称
        if (Platform.isWindows) "interface_name": "sing-box",
        // IPv4地址配置，仅在明确启用IPv6且VPS支持时才添加IPv6
        "address": enableIpv6
            ? ["172.19.0.1/30", "2001:db8::1/128"]
            : ["172.19.0.1/30"],

        // 使用稳定的MTU设置，避免频繁调整导致连接中断
        "mtu": tunMtu ?? 1500, // 标准以太网MTU，最稳定
        "auto_route": true,
        "strict_route": tunStrictRoute,

        // 保守的嗅探配置，避免影响DNS
        "sniff": true,

        // 添加稳定性配置
        "domain_strategy": "prefer_ipv4", // 优先IPv4提高稳定性
        // 默认使用 system（Windows 下 Wintun），必要时可切换 gvisor
        "stack": Platform.isWindows ? 'system' : 'system',

        // Windows平台稳定性配置
        if (Platform.isWindows) "endpoint_independent_nat": false,

        // 路由表配置，减少路由冲突
        "inet4_route_address": ["0.0.0.0/1", "128.0.0.0/1"],
      });
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

    final config = <String, dynamic>{
      "log": {"level": "error", "timestamp": true},
      "dns": getDnsConfig(mode, useTun: useTun),
      "inbounds": inbounds,
      "outbounds": getOutbounds({"tag": "proxy", ...proxyConfig}),
      "route": {
        ...await getRouteConfig(mode),
        "rules": [
          {
            "inbound": ["latency-test-in"],
            "outbound": "direct",
          },
          ...?(await getRouteConfig(mode))["rules"] as List?,
        ],
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
