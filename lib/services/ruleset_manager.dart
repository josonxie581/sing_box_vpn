import 'dart:io';

import '../models/proxy_mode.dart';
import 'dns_manager.dart';

/// 规则与配置组装（兼容 sing-box v1.8.0 及以上）
class RulesetManager {
  /// 路由规则（规则模式）
  static List<Map<String, dynamic>> getRuleModeRoutes() {
    return [
      // 系统 DNS 给内网 DNS 处理，避免被导入代理
      {"network": "udp", "port": 53, "outbound": "dns-out"},
      {"network": "tcp", "port": 53, "outbound": "dns-out"},
      // 私有网段直连
      {"ip_is_private": true, "outbound": "direct"},
      // 中国域名直连
      {"rule_set": ["geosite-cn"], "outbound": "direct"},
      // 中国IP直连
      {"rule_set": ["geoip-cn"], "outbound": "direct"},
      // 广告拦截
      {"rule_set": ["geosite-ads"], "outbound": "block"},
      // 其余流量走 route.final（见 getRouteConfig）
    ];
  }

  /// 路由规则（全局模式）
  static List<Map<String, dynamic>> getGlobalModeRoutes() {
    return [
      {"network": "udp", "port": 53, "outbound": "dns-out"},
      {"network": "tcp", "port": 53, "outbound": "dns-out"},
      {"ip_is_private": true, "outbound": "direct"},
      // 广告拦截（即使全局模式也保留广告拦截）
      {"rule_set": ["geosite-ads"], "outbound": "block"},
      // 其余流量走 route.final
    ];
  }

  /// 根据模式生成 route 配置
  static Map<String, dynamic> getRouteConfig(ProxyMode mode) {
    final base = {
      "auto_detect_interface": true,
      "final": "proxy",
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
    };
    switch (mode) {
      case ProxyMode.rule:
        return {
          ...base,
          "rules": getRuleModeRoutes(),
        };
      case ProxyMode.global:
        return {
          ...base,
          "rules": getGlobalModeRoutes(),
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
      preferRuleRouting: mode == ProxyMode.rule,
      useTun: useTun,
    );
  }

  /// 生成完整 sing-box 配置
  static Map<String, dynamic> generateSingBoxConfig({
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
  }) {
    final inbounds = <Map<String, dynamic>>[];

    if (useTun) {
      inbounds.add({
        "tag": "tun-in",
        "type": "tun",
        if (Platform.isWindows) "interface_name": "Gsou Adapter Tunnel",
        // 官方规范：使用address字段，根据配置决定是否包含IPv6
        "address": enableIpv6
          ? ["172.19.0.1/30", "2001:db8::1/128"]
          : ["172.19.0.1/30"],

        // 可根据探测回退，默认较大 MTU
        "mtu": tunMtu ?? 4064,
        "auto_route": true,
        "strict_route": tunStrictRoute,
        // route_exclude_address 在 v1.8.0 不支持，暂不设置
        // 默认使用 system（Windows 下 Wintun），必要时可切换 gvisor
        "stack": Platform.isWindows ? 'system' : 'system',
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

    final config = <String, dynamic>{
      "log": {"level": "error", "timestamp": true},
      "dns": getDnsConfig(mode, useTun: useTun),
      "inbounds": inbounds,
      "outbounds": getOutbounds({"tag": "proxy", ...proxyConfig}),
      "route": getRouteConfig(mode),
    };

    if (enableClashApi) {
      config["experimental"] = {
        "clash_api": {
          'external_controller': '127.0.0.1:$clashApiPort',
          'secret': clashApiSecret,
        }
      };
    }

    return config;
  }
}
