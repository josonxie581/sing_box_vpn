import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vpn_config.dart';
import 'node_delay_tester.dart';

/// sing-box Clash API 配置类
class SingBoxApiConfig {
  final String host;
  final int port;
  final String secret;

  const SingBoxApiConfig({
    this.host = '127.0.0.1',
    this.port = 9090,
    this.secret = '',
  });

  String get baseUrl => 'http://$host:$port';

  Map<String, String> get headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (secret.isNotEmpty) 'Authorization': 'Bearer $secret',
  };
}

/// sing-box 延时检测服务
/// 提供VPN节点延时测试功能
class PingService {
  // 保留默认超时常量由各测试器内部定义与控制，此处不再冗余定义

  // sing-box Clash API 配置（保留占位，以便未来扩展；当前 Windows 口径未使用）
  static SingBoxApiConfig _apiConfig = const SingBoxApiConfig();

  /// 设置 sing-box API 配置
  static void setApiConfig({String? host, int? port, String? secret}) {
    _apiConfig = SingBoxApiConfig(
      host: host ?? '127.0.0.1',
      port: port ?? 9090,
      secret: secret ?? '',
    );
  }

  /// 检查 sing-box API 是否可用
  static Future<bool> isApiAvailable() async {
    try {
      final client = http.Client();

      try {
        final apiUrl = '${_apiConfig.baseUrl}/version';

        final response = await client
            .get(Uri.parse(apiUrl), headers: _apiConfig.headers)
            .timeout(const Duration(seconds: 2));

        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (e) {
      print('[DEBUG] API健康检查失败: $e');
      return false;
    }
  }

  /// 获取所有可用的代理出站列表
  static Future<List<String>> getAvailableProxies() async {
    try {
      final client = http.Client();

      try {
        final apiUrl = '${_apiConfig.baseUrl}/proxies';

        final response = await client
            .get(Uri.parse(apiUrl), headers: _apiConfig.headers)
            .timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['proxies'] != null) {
            final proxies = data['proxies'] as Map<String, dynamic>;
            return proxies.keys.toList();
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('[DEBUG] 获取代理列表异常: $e');
    }
    return [];
  }

  /// 检测单个节点配置的网络延时
  ///
  /// 参数：
  /// - config: 要测试的 VPN 配置
  /// - isConnected: 是否处于 VPN 连接状态
  /// - currentConfig: 当前连接的配置（VPN连接时使用）
  ///
  /// 返回：延时毫秒数，-1 表示连接超时或测试失败
  static Future<int> pingConfig(
    VPNConfig config, {
    bool isConnected = false,
    VPNConfig? currentConfig,
  }) async {
    try {
      print('[DEBUG] Windows口径：统一使用“节点握手RTT”测延时 -> ${config.name}');

      if (isConnected) {
        // 已连接：为避免 VPN 路由干扰，使用“绕过”路径进行节点握手测试
        final tester = NodeDelayTester(
          timeout: 6000,
          enableIpInfo: false,
          latencyMode: LatencyTestMode.bypass,
        );
        final result = await tester.realTest(config);
        if (result.isSuccess) return result.delay;
        return -1;
      } else {
        // 未连接：按你的要求，同样走“独立实例直连路由”的绕过路径，确保与 Windows 口径一致
        final tester = NodeDelayTester(
          timeout: 5000,
          enableIpInfo: false,
          latencyMode: LatencyTestMode.bypass,
        );
        final result = await tester.realTest(config);
        if (result.isSuccess) return result.delay;
        return -1;
      }
    } catch (e) {
      print('[DEBUG] 节点 ${config.name} 延时测试异常: $e');
      return -1;
    }
  }

  // Windows 口径已统一在 pingConfig 内部通过 NodeDelayTester 实现

  // 其余 Clash API 相关的私有方法已移除，以统一 Windows 口径

  /// 批量检测多个节点配置的延时
  ///
  /// 返回配置ID到延时毫秒数的映射表
  static Future<Map<String, int>> pingConfigs(
    List<VPNConfig> configs, {
    bool isConnected = false,
    VPNConfig? currentConfig,
    int? concurrency,
  }) async {
    final results = <String, int>{};

    await pingConfigsWithProgress(
      configs,
      isConnected: isConnected,
      currentConfig: currentConfig,
      concurrency: concurrency,
      onEach: (cfg, ping) => results[cfg.id] = ping,
    );

    return results;
  }

  /// 自适应并发批量延时检测，支持进度回调
  static Future<void> pingConfigsWithProgress(
    List<VPNConfig> configs, {
    void Function(VPNConfig config, int ping)? onEach,
    void Function(int done, int total)? onProgress,
    int? concurrency,
    bool isConnected = false,
    VPNConfig? currentConfig,
  }) async {
    if (configs.isEmpty) return;

    final total = configs.length;
    final workerCount = _resolveConcurrency(total, concurrency);

    print('[DEBUG] 并发延时测试启动: 节点数量=$total, 并发数=$workerCount, 已连接=$isConnected');

    int nextIndex = 0;
    int completed = 0;
    int successCount = 0;

    Future<void> worker() async {
      while (true) {
        final current = nextIndex;
        if (current >= total) {
          return;
        }
        nextIndex++;
        final cfg = configs[current];

        int ping = -1;
        try {
          ping = await pingConfig(
            cfg,
            isConnected: isConnected,
            currentConfig: currentConfig,
          );
        } catch (e) {
          print('[DEBUG] 节点 ${cfg.name} 并发延时测试异常: $e');
        } finally {
          if (ping >= 0) {
            successCount++;
          }
          onEach?.call(cfg, ping);
          completed++;
          onProgress?.call(completed, total);
        }
      }
    }

    try {
      final futures = List.generate(workerCount, (_) => worker());
      await Future.wait(futures);
      print('[DEBUG] 并发延时测试完成，成功节点: $successCount/$total，线程数=$workerCount');
    } catch (e) {
      print('[DEBUG] 并发批量延时测试异常: $e');
    }
  }

  /// 根据节点数量决定并发数，避免对系统造成过大压力
  static int _resolveConcurrency(int total, int? preferred) {
    if (total <= 1) {
      return 1;
    }

    int value;
    if (preferred != null && preferred > 0) {
      value = preferred;
    } else if (total <= 6) {
      value = 2;
    } else if (total <= 20) {
      value = 4;
    } else if (total <= 60) {
      value = 6;
    } else if (total <= 120) {
      value = 8;
    } else if (total <= 200) {
      value = 10;
    } else {
      value = 12;
    }

    if (value > total) {
      value = total;
    }

    return value < 1 ? 1 : value;
  }

  static String formatPing(int ping) {
    if (ping == -2) {
      return '已连接';
    } else if (ping < 0) {
      return '超时';
    } else if (ping < 1000) {
      return '${ping}ms';
    } else {
      return '${(ping / 1000).toStringAsFixed(1)}s';
    }
  }

  /// 根据延时数值获取网络质量等级
  ///
  /// 参数：ping 延时毫秒数
  /// 返回：对应的网络质量等级枚举
  static PingLevel getPingLevel(int ping) {
    if (ping == -2) return PingLevel.excellent; // 当前连接的服务器显示为优秀
    if (ping < 0) return PingLevel.timeout;
    if (ping < 100) return PingLevel.excellent;
    if (ping < 200) return PingLevel.good;
    if (ping < 500) return PingLevel.fair;
    return PingLevel.poor;
  }

  /// 获取延时等级的中文描述
  ///
  /// 参数：ping 延时毫秒数
  /// 返回：网络质量的中文描述文本
  static String getPingDescription(int ping) {
    if (ping == -2) return '当前连接';
    final level = getPingLevel(ping);
    switch (level) {
      case PingLevel.timeout:
        return '连接超时';
      case PingLevel.excellent:
        return '优秀';
      case PingLevel.good:
        return '良好';
      case PingLevel.fair:
        return '一般';
      case PingLevel.poor:
        return '较差';
    }
  }
}

/// 网络延时质量等级枚举
///
/// 根据延时范围划分网络连接质量等级
enum PingLevel {
  /// 连接超时或测试失败
  timeout,

  /// 优秀网络质量（< 100ms）
  excellent,

  /// 良好网络质量（100-200ms）
  good,

  /// 一般网络质量（200-500ms）
  fair,

  /// 较差网络质量（> 500ms）
  poor,
}
