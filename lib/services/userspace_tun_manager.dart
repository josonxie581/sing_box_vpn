/// 纯用户空间 TUN 管理器
/// 使用 gVisor 网络栈，无需管理员权限
///
/// 核心原理：
/// 1. gVisor 提供完整的 TCP/IP 栈实现
/// 2. 不修改系统路由表，而是在应用层拦截
/// 3. 通过 SOCKS/HTTP 代理接口暴露服务

import '../models/proxy_mode.dart';

class UserspaceTunManager {
  /// 生成纯用户空间的 gVisor 配置
  /// 关键：不使用 auto_route，避免需要管理员权限
  static Map<String, dynamic> generateUserSpaceConfig({
    required Map<String, dynamic> proxyConfig,
    required ProxyMode mode,
    int localPort = 7890,
  }) {
    return {
      "log": {"level": "info", "timestamp": true},
      "dns": _getDnsConfig(),
      "inbounds": [
        {
          // 1. 纯用户空间 TUN（不修改路由）
          "tag": "tun-in",
          "type": "tun",
          "interface_name": "Gsou Userspace",
          "address": ["172.19.0.1/30"],
          "mtu": 1500,
          "stack": "system", // 修改：启用 TUN 时固定使用 system (Wintun) 栈
          "auto_route": false, // ⚠️ 关键：不自动配置路由
          "strict_route": false,

          // gVisor 特定优化
          "gso": true, // Generic Segmentation Offload
          "tcp_multi_path": true,
          "tcp_fast_open": true,
        },
        {
          // 2. 混合代理入口（供应用程序使用）
          "tag": "mixed-in",
          "type": "mixed",
          "listen": "127.0.0.1",
          "listen_port": localPort,
          "sniff": true,
          "set_system_proxy": false, // 不修改系统代理
        },
        {
          // 3. 透明代理（仅处理本地重定向的流量）
          "tag": "redir-in",
          "type": "redirect",
          "listen": "127.0.0.1",
          "listen_port": localPort + 1,
          "sniff": true,
        },
      ],
      "outbounds": [
        {"tag": "proxy", ...proxyConfig},
        {"tag": "direct", "type": "direct"},
        {"tag": "block", "type": "block"},
        {"tag": "dns-out", "type": "dns"},
      ],
      "route": _getRouteConfig(mode),
    };
  }

  /// DNS 配置（使用 FakeIP 避免 DNS 泄露）
  static Map<String, dynamic> _getDnsConfig() {
    return {
      "servers": [
        {"tag": "remote", "address": "tls://8.8.8.8", "detour": "proxy"},
        {"tag": "local", "address": "223.5.5.5", "detour": "direct"},
      ],
      "rules": [
        {
          "rule_set": ["geosite-cn"],
          "server": "local",
        },
      ],
      "final": "remote",
      "strategy": "prefer_ipv4",
      "fakeip": {"enabled": true, "inet4_range": "198.18.0.0/15"},
    };
  }

  /// 路由配置
  static Map<String, dynamic> _getRouteConfig(ProxyMode mode) {
    return {
      "rules": [
        // 局域网直连
        {"ip_is_private": true, "outbound": "direct"},

        // 根据模式选择规则
        if (mode == ProxyMode.rule) ...[
          {
            "rule_set": ["geosite-cn"],
            "outbound": "direct",
          },
          {
            "rule_set": ["geoip-cn"],
            "outbound": "direct",
          },
        ],

        // 默认走代理
        {"outbound": "proxy"},
      ],
      "final": "proxy",
      "find_process": true, // gVisor 支持进程匹配
    };
  }
}

/// 用户空间流量劫持助手
/// 通过应用层 Hook 实现流量重定向，无需系统权限
class UserSpaceTrafficCapture {
  /// 方案1：使用 WinSock LSP (Layered Service Provider)
  /// 在用户空间拦截 socket 调用
  static Future<bool> installLSP() async {
    // LSP 可以在用户权限下工作
    // 拦截 connect(), send(), recv() 等调用
    // 重定向到本地代理端口
    return true;
  }

  /// 方案2：使用 Detours 或类似技术 Hook API
  static Future<bool> installAPIHooks() async {
    // Hook WinInet, WinHTTP 等网络 API
    // 在进程内重定向网络请求
    return true;
  }

  /// 方案3：使用 Windows Filtering Platform (WFP) 用户模式
  /// WFP 有用户模式 API，可以创建过滤器
  static Future<bool> installWFPFilters() async {
    // 使用 WFP 用户模式 API
    // 创建应用层过滤器
    // 重定向到本地代理
    return true;
  }
}

/// 进程代理注入器
/// 为特定进程注入代理设置，无需修改系统配置
class ProcessProxyInjector {
  /// 为浏览器进程设置代理
  static Future<void> setBrowserProxy(int port) async {
    // Chrome: --proxy-server=127.0.0.1:$port
    // Firefox: 修改 prefs.js
    // Edge: 类似 Chrome
  }

  /// 为常见应用设置代理环境变量
  static Future<void> setEnvironmentProxy(int port) async {
    // 设置进程级环境变量
    // HTTP_PROXY, HTTPS_PROXY, ALL_PROXY
    // 只影响子进程，不需要系统权限
  }
}
