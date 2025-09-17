import 'dart:io';

import '../models/proxy_mode.dart';
import 'dns_manager.dart';
import 'custom_rules_service.dart';

/// 规则与配置组装（兼容 sing-box v1.8.0 及以上）
class RulesetManager {
  /// 路由规则（规则模式）
  static List<Map<String, dynamic>> getRuleModeRoutes() {
    final rules = <Map<String, dynamic>>[
      // 系统 DNS 给内网 DNS 处理，避免被导入代理
      {"network": "udp", "port": 53, "outbound": "dns-out"},
      {"network": "tcp", "port": 53, "outbound": "dns-out"},
      // 私有网段直连
      {"ip_is_private": true, "outbound": "direct"},
    ];

    // 插入自定义规则（优先级高于默认地理规则）
    try {
      final customRules = CustomRulesService.instance.generateSingBoxRules();
      rules.addAll(customRules);
    } catch (e) {
      print('[ERROR] 加载自定义规则失败: $e');
    }

    // 添加默认地理规则
    rules.addAll([
      // 中国域名直连
      {
        "rule_set": ["geosite-cn"],
        "outbound": "direct",
      },
      // 中国IP直连
      {
        "rule_set": ["geoip-cn"],
        "outbound": "direct",
      },
      // 广告拦截
      {
        "rule_set": ["geosite-ads"],
        "outbound": "block",
      },
      // 其余流量走 route.final（见 getRouteConfig）
    ]);

    return rules;
  }

  /// 路由规则（全局模式）
  static List<Map<String, dynamic>> getGlobalModeRoutes() {
    final rules = <Map<String, dynamic>>[
      {"network": "udp", "port": 53, "outbound": "dns-out"},
      {"network": "tcp", "port": 53, "outbound": "dns-out"},
      {"ip_is_private": true, "outbound": "direct"},
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
      // 私有网段直连
      {"ip_is_private": true, "outbound": "direct"},
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
  static Map<String, dynamic> getRouteConfig(ProxyMode mode) {
    final base = {"auto_detect_interface": true, "final": "proxy"};

    switch (mode) {
      case ProxyMode.rule:
        return {
          ...base,
          "rule_set": [
            {
              "tag": "geosite-cn",
              "type": "local",
              "format": "binary",
              "path": _getRulesetPath("geosite-cn.srs"),
            },
            {
              "tag": "geoip-cn",
              "type": "local",
              "format": "binary",
              "path": _getRulesetPath("geoip-cn.srs"),
            },
            {
              "tag": "geosite-ads",
              "type": "local",
              "format": "binary",
              "path": _getRulesetPath("geosite-ads.srs"),
            },
            {
              "tag": "geosite-geolocation-!cn",
              "type": "local",
              "format": "binary",
              "path": _getRulesetPath("geosite-geolocation-!cn.srs"),
            },
          ],
          "rules": getRuleModeRoutes(),
        };
      case ProxyMode.global:
        return {
          ...base,
          "rule_set": [
            // 全局模式保留必要的规则集以支持DNS分流
            {
              "tag": "geosite-cn",
              "type": "local",
              "format": "binary",
              "path": _getRulesetPath("geosite-cn.srs"),
            },
            {
              "tag": "geosite-ads",
              "type": "local",
              "format": "binary",
              "path": _getRulesetPath("geosite-ads.srs"),
            },
            {
              "tag": "geosite-geolocation-!cn",
              "type": "local",
              "format": "binary",
              "path": _getRulesetPath("geosite-geolocation-!cn.srs"),
            },
          ],
          "rules": getGlobalModeRoutes(),
        };
      case ProxyMode.custom:
        return {
          ...base,
          "rule_set": [
            // 仅加载广告拦截规则集（如果需要的话）
            {
              "tag": "geosite-ads",
              "type": "local",
              "format": "binary",
              "path": _getRulesetPath("geosite-ads.srs"),
            },
          ],
          "rules": getCustomModeRoutes(),
        };
    }
  }

  /// 获取规则集文件路径
  static String _getRulesetPath(String filename) {
    if (Platform.isWindows) {
      // Windows平台使用应用程序目录下的assets路径
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
        ...getRouteConfig(mode),
        "rules": [
          {
            "inbound": ["latency-test-in"],
            "outbound": "direct",
          },
          ...?getRouteConfig(mode)["rules"] as List?,
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
