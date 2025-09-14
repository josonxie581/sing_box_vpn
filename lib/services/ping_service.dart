import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vpn_config.dart';

/// 延时检测服务 (纯TCP方式)
class PingService {
  static const Duration _timeout = Duration(seconds: 3); // 从5秒优化到3秒

  /// 检测单个配置的延时
  /// 返回延时毫秒数，-1表示超时或失败
  static Future<int> pingConfig(VPNConfig config) async {
    try {
      final stopwatch = Stopwatch()..start();

      // 根据不同协议类型使用不同的测试方法
      switch (config.type.toLowerCase()) {
        case 'ss':
        case 'shadowsocks':
          return await _testShadowsocks(config, stopwatch);
        case 'vmess':
        case 'vless':
          return await _testVmess(config, stopwatch);
        case 'trojan':
          return await _testTrojan(config, stopwatch);
        case 'hysteria2':
        case 'hy2':
          return await _testHysteria2(config, stopwatch);
        case 'tuic':
          return await _testTuic(config, stopwatch);
        default:
          return await _testGeneric(config, stopwatch);
      }
    } catch (e) {
      return -1;
    }
  }

  /// 批量检测配置延时
  static Future<Map<String, int>> pingConfigs(List<VPNConfig> configs) async {
    final results = <String, int>{};
    await pingConfigsWithProgress(configs, onEach: (c, p) => results[c.id] = p);
    return results;
  }

  /// 自适应并发的批量检测，提供进度与逐项回调
  /// onEach: 单个节点完成时回调
  /// onProgress: (done, total) 进度回调
  static Future<void> pingConfigsWithProgress(
    List<VPNConfig> configs, {
    void Function(VPNConfig config, int ping)? onEach,
    void Function(int done, int total)? onProgress,
    int? concurrency,
  }) async {
    if (configs.isEmpty) return;
    final total = configs.length;
    // 自适应并发：节点少时不用开太多，避免进程/Socket 抖动
    final conc =
        concurrency ??
        (() {
          if (total <= 10) return 4;
          if (total <= 20) return 6;
          if (total <= 60) return 10;
          if (total <= 120) return 14;
          return 18; // 上限
        })();

    final queue = List<VPNConfig>.from(configs); // 简单队列
    int running = 0;
    int done = 0;
    final completer = Completer<void>();

    void scheduleNext() {
      if (queue.isEmpty && running == 0) {
        completer.complete();
        return;
      }
      while (running < conc && queue.isNotEmpty) {
        final cfg = queue.removeAt(0);
        running++;
        pingConfig(cfg)
            .then((ping) {
              onEach?.call(cfg, ping);
            })
            .catchError((_) {
              onEach?.call(cfg, -1);
            })
            .whenComplete(() {
              running--;
              done++;
              if (onProgress != null && (done == total || done % 3 == 0)) {
                onProgress(done, total);
              }
              scheduleNext();
            });
      }
    }

    scheduleNext();
    await completer.future;
  }

  /// 测试 Shadowsocks 延时 (纯TCP)
  static Future<int> _testShadowsocks(
    VPNConfig config,
    Stopwatch stopwatch,
  ) async {
    // 优先尝试配置端口 TCP 握手
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;

    // TCP失败时尝试常见端口
    return await _tryCommonTcpPorts(config.server);
  }

  /// 测试 VMess/VLess 延时 (纯TCP)
  static Future<int> _testVmess(VPNConfig config, Stopwatch stopwatch) async {
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;
    return await _tryCommonTcpPorts(config.server);
  }

  /// 测试 Trojan 延时 (纯TCP)
  static Future<int> _testTrojan(VPNConfig config, Stopwatch stopwatch) async {
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;
    return await _tryCommonTcpPorts(config.server);
  }

  /// 测试 Hysteria2 延时 (纯TCP)
  static Future<int> _testHysteria2(
    VPNConfig config,
    Stopwatch stopwatch,
  ) async {
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;
    return await _tryCommonTcpPorts(config.server);
  }

  /// 测试 TUIC 延时 (纯TCP)
  static Future<int> _testTuic(VPNConfig config, Stopwatch stopwatch) async {
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;
    return await _tryCommonTcpPorts(config.server);
  }

  /// 通用测试方法 (纯TCP)
  static Future<int> _testGeneric(VPNConfig config, Stopwatch stopwatch) async {
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;
    return await _tryCommonTcpPorts(config.server);
  }

  /// 尝试直接 TCP 连接指定端口，成功返回耗时，失败返回 -1
  static Future<int> _tryDirectTcp(String host, int port) async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(host, port, timeout: _timeout);
      final ms = sw.elapsedMilliseconds;
      socket.destroy();
      return ms;
    } catch (_) {
      return -1;
    }
  }

  /// 尝试常见TCP端口连接测试，替代ICMP ping
  static Future<int> _tryCommonTcpPorts(String host) async {
    // 常见端口列表，按优先级排序 (HTTPS, HTTP, SSH, DNS, Alt-HTTP, Alt-HTTPS)
    const ports = [443, 80, 22, 53, 8080, 8443];

    // 并行测试前3个端口，提升速度
    const quickTimeout = Duration(milliseconds: 1500); // 更短的超时
    final highPriorityPorts = ports.take(3);

    // 并行测试高优先级端口，取最快的成功结果
    final results = await Future.wait(
      highPriorityPorts.map(
        (port) => _tryTcpWithTimeout(host, port, quickTimeout),
      ),
    );

    // 查找第一个成功的结果
    for (final result in results) {
      if (result >= 0) return result;
    }

    // 如果高优先级端口都失败，顺序测试剩余端口
    for (int i = 3; i < ports.length; i++) {
      final result = await _tryTcpWithTimeout(host, ports[i], quickTimeout);
      if (result >= 0) return result;
    }

    return -1; // 所有端口都无法连接
  }

  /// 带超时的TCP连接测试
  static Future<int> _tryTcpWithTimeout(
    String host,
    int port,
    Duration timeout,
  ) async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(host, port, timeout: timeout);
      final ms = sw.elapsedMilliseconds;
      socket.destroy();
      return ms;
    } catch (_) {
      return -1;
    }
  }

  // ICMP ping相关代码已移除，改为使用纯TCP连接测试

  // （已移除未使用的 _testTcpConnection/_testHttpThroughProxy 以减轻分析告警）

  /// 格式化延时显示
  static String formatPing(int ping) {
    if (ping < 0) {
      return '超时';
    } else if (ping < 100) {
      return '${ping}ms';
    } else if (ping < 1000) {
      return '${ping}ms';
    } else {
      return '${(ping / 1000).toStringAsFixed(1)}s';
    }
  }

  /// 获取延时等级颜色
  static PingLevel getPingLevel(int ping) {
    if (ping < 0) return PingLevel.timeout;
    if (ping < 100) return PingLevel.excellent;
    if (ping < 200) return PingLevel.good;
    if (ping < 500) return PingLevel.fair;
    return PingLevel.poor;
  }

  /// 获取延时描述
  static String getPingDescription(int ping) {
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

/// 延时等级枚举
enum PingLevel {
  timeout, // 超时
  excellent, // 优秀 < 100ms
  good, // 良好 100-200ms
  fair, // 一般 200-500ms
  poor, // 较差 > 500ms
}
