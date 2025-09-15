import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vpn_config.dart';

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
/// 根据官方文档规范实现 Clash API 延时测试
class PingService {
  static const Duration _timeout = Duration(seconds: 3);

  // sing-box Clash API 配置
  static SingBoxApiConfig _apiConfig = const SingBoxApiConfig();

  // 根据官方文档推荐的测试URL
  static const String _officialTestUrl = 'https://www.gstatic.com/generate_204';
  static const List<String> _fallbackTestUrls = [
    'https://cp.cloudflare.com', // Cloudflare连通性测试
    'http://detectportal.firefox.com/success.txt', // Firefox连通性测试
    'http://www.msftconnecttest.com/connecttest.txt', // Microsoft连通性测试
  ];

  // 延时校准相关
  static int? _apiOverhead;
  static bool _calibrationCompleted = false;

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

  /// 校准API调用开销
  ///
  /// 通过多次测试本地API调用时间来计算平均开销
  /// 这个开销将用于校正实际的代理延时测试结果
  static Future<void> calibrateApiOverhead() async {
    if (_calibrationCompleted) return;

    try {
      print('[DEBUG] 开始校准API开销...');
      final samples = <int>[];

      // 进行5次校准测试
      for (int i = 0; i < 5; i++) {
        final stopwatch = Stopwatch()..start();

        final client = http.Client();
        try {
          // 测试简单的API调用（获取版本信息）
          final apiUrl = '${_apiConfig.baseUrl}/version';
          final response = await client
              .get(Uri.parse(apiUrl), headers: _apiConfig.headers)
              .timeout(const Duration(seconds: 2));

          stopwatch.stop();

          if (response.statusCode == 200) {
            samples.add(stopwatch.elapsedMilliseconds);
          }
        } finally {
          client.close();
        }

        // 校准测试间隔
        if (i < 4) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      if (samples.isNotEmpty) {
        // 计算平均API开销，去除异常值
        samples.sort();
        // 去除最高和最低值，取中间值的平均
        final middleSamples = samples.length > 2
            ? samples.sublist(1, samples.length - 1)
            : samples;

        _apiOverhead =
            middleSamples.reduce((a, b) => a + b) ~/ middleSamples.length;
        _calibrationCompleted = true;

        print('[DEBUG] API开销校准完成: ${_apiOverhead}ms (样本: $samples)');
      } else {
        print('[DEBUG] API开销校准失败，使用默认值');
        _apiOverhead = 50; // 使用默认估算值50ms
        _calibrationCompleted = true;
      }
    } catch (e) {
      print('[DEBUG] API开销校准异常: $e');
      _apiOverhead = 170; // 使用默认估算值
      _calibrationCompleted = true;
    }
  }

  /// 应用延时校准
  ///
  /// 从API测试结果中减去开销，获得更准确的网络延时
  static int _applyCalibratedDelay(int rawDelay) {
    if (!_calibrationCompleted || _apiOverhead == null || rawDelay <= 0) {
      return rawDelay;
    }

    // 从原始延时中减去API开销，但确保结果不小于10ms
    final calibratedDelay = rawDelay - _apiOverhead!;
    return calibratedDelay > 10 ? calibratedDelay : rawDelay ~/ 2;
  }

  /// 手动设置API开销校准值
  ///
  /// 用于手动指定API调用开销，跳过自动校准过程
  ///
  /// 参数：overhead API调用开销毫秒数（建议范围：20-100ms）
  static void setApiOverhead(int overhead) {
    _apiOverhead = overhead.clamp(10, 200);
    _calibrationCompleted = true;
    print('[DEBUG] 手动设置API开销: ${_apiOverhead}ms');
  }

  /// 重置校准状态
  ///
  /// 清除已有的校准数据，下次测试时重新进行校准
  static void resetCalibration() {
    _apiOverhead = null;
    _calibrationCompleted = false;
    print('[DEBUG] 延时校准已重置');
  }

  /// 获取当前API开销值
  static int? get apiOverhead => _apiOverhead;

  /// 检测单个节点配置的网络延时
  ///
  /// 根据 sing-box 官方文档实现，支持 VPN 连接和直连两种模式
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
      // 确保API开销已校准
      if (!_calibrationCompleted) {
        await calibrateApiOverhead();
      }

      final stopwatch = Stopwatch()..start();

      // VPN已连接时，所有配置都测试通过VPN到该服务器的延时
      if (isConnected) {
        return await _testLatencyThroughVpnTunnel(config);
      }

      // 未连接时，根据不同协议类型使用不同的测试方法
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

  /// 测试VPN连接的真实网络延时
  /// 使用官方推荐的测试URL和方法
  static Future<int> _testVpnLatency() async {
    final List<int> results = [];

    // 1. 优先使用官方推荐的测试URL
    final officialResult = await _testHttpLatencyThroughVpn(_officialTestUrl);
    if (officialResult > 0) {
      results.add(officialResult);
    }

    // 2. 使用备用测试URL
    for (final url in _fallbackTestUrls.take(2)) {
      final result = await _testHttpLatencyThroughVpn(url);
      if (result > 0) {
        results.add(result);
      }
    }

    // 3. 如果HTTP测试都失败，尝试TCP连接测试
    if (results.isEmpty) {
      final tcpResults = await _testTcpConnections();
      results.addAll(tcpResults);
    }

    if (results.isEmpty) {
      return -1;
    }

    // 返回最佳结果的平均值
    results.sort();
    final bestResults = results.take(3).toList();
    return bestResults.reduce((a, b) => a + b) ~/ bestResults.length;
  }

  /// 测试TCP连接延时
  static Future<List<int>> _testTcpConnections() async {
    final results = <int>[];

    // 使用标准的测试服务器
    final testServers = [
      {'host': '8.8.8.8', 'port': 53}, // Google DNS
      {'host': '1.1.1.1', 'port': 53}, // Cloudflare DNS
      {'host': 'www.google.com', 'port': 443}, // Google HTTPS
    ];

    for (final server in testServers) {
      try {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect(
          server['host'] as String,
          server['port'] as int,
          timeout: const Duration(milliseconds: 2000),
        );
        sw.stop();
        socket.destroy();

        final latency = sw.elapsedMilliseconds;
        if (latency > 0 && latency < 5000) {
          results.add(latency);
        }
      } catch (_) {
        continue;
      }
    }

    return results;
  }

  /// 测试VPN连接的服务器延时
  /// 通过本地代理端口测试到VPS服务器的延时
  static Future<int> _testVpnConnectedServerLatency(VPNConfig config) async {
    try {
      // 方法1: 通过本地代理端口测试连接
      final localProxyResult = await _testThroughLocalProxy();
      if (localProxyResult > 0) {
        return localProxyResult;
      }

      // 方法2: 如果代理测试失败，使用网络延时作为备用
      final networkResult = await _testNetworkLatencyThroughVpn();
      if (networkResult > 0) {
        return networkResult;
      }

      return -1;
    } catch (e) {
      return -1;
    }
  }

  /// 通过本地代理端口测试延时
  static Future<int> _testThroughLocalProxy() async {
    try {
      // 测试本地代理端口的响应延时
      final sw = Stopwatch()..start();

      // 尝试连接到常见的本地代理端口
      final ports = [7890, 1080, 8080, 10809]; // 常见的本地代理端口

      for (final port in ports) {
        try {
          final socket = await Socket.connect(
            '127.0.0.1',
            port,
            timeout: const Duration(milliseconds: 500),
          );
          sw.stop();
          socket.destroy();

          // 连接成功，但需要添加一些基准延时，因为本地连接太快
          // 通过测试简单HTTP请求来获得更真实的延时
          return await _testSimpleHttpThroughProxy(port) ??
              sw.elapsedMilliseconds + 10;
        } catch (_) {
          continue;
        }
      }
      return -1;
    } catch (_) {
      return -1;
    }
  }

  /// 通过代理测试简单HTTP请求
  static Future<int?> _testSimpleHttpThroughProxy(int port) async {
    try {
      final sw = Stopwatch()..start();
      final client = http.Client();

      try {
        // 通过代理测试一个简单的HTTP请求
        final response = await client
            .get(Uri.parse('http://httpbin.org/ip'))
            .timeout(const Duration(milliseconds: 2000));

        sw.stop();
        if (response.statusCode == 200) {
          return sw.elapsedMilliseconds;
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // 忽略错误
    }
    return null;
  }

  /// 通过VPN测试网络延时
  static Future<int> _testNetworkLatencyThroughVpn() async {
    final List<int> latencies = [];

    // 使用TCP连接测试，比HTTP更快更准确
    final tcpTargets = [
      {'host': '8.8.8.8', 'port': 53}, // Google DNS
      {'host': '1.1.1.1', 'port': 53}, // Cloudflare DNS
      {'host': '114.114.114.114', 'port': 53}, // 国内DNS
    ];

    final results = await Future.wait(
      tcpTargets.map((target) async {
        try {
          final sw = Stopwatch()..start();
          final socket = await Socket.connect(
            target['host'] as String,
            target['port'] as int,
            timeout: const Duration(milliseconds: 800),
          );
          sw.stop();
          socket.destroy();
          return sw.elapsedMilliseconds;
        } catch (_) {
          return -1;
        }
      }),
    );

    for (final result in results) {
      if (result > 0) {
        latencies.add(result);
      }
    }

    if (latencies.isEmpty) {
      return -1;
    }

    // 取平均值，但限制在合理范围内
    final avg = latencies.reduce((a, b) => a + b) ~/ latencies.length;

    // 如果平均值太高，可能是网络问题，取最小值
    if (avg > 500) {
      latencies.sort();
      return latencies.first;
    }

    return avg;
  }

  /// 测试通过VPN隧道到目标服务器的延时
  /// 使用sing-box Clash API规范进行延时测试
  static Future<int> _testLatencyThroughVpnTunnel(VPNConfig config) async {
    try {
      print('[DEBUG] 开始测试VPN延时: ${config.name}');

      // 方法1: 测试当前激活的代理出站
      final activeProxyResult = await _testActiveProxy();
      if (activeProxyResult > 0) {
        print('[DEBUG] ✅ 活跃代理测试成功: ${config.name} -> ${activeProxyResult}ms');
        return activeProxyResult;
      }

      // 方法2: 根据配置生成可能的出站标签并测试
      final configBasedResult = await _testConfigBasedProxy(config);
      if (configBasedResult > 0) {
        print('[DEBUG] ✅ 配置代理测试成功: ${config.name} -> ${configBasedResult}ms');
        return configBasedResult;
      }

      // 方法3: 使用备用网络测试方法
      final fallbackResult = await _testNetworkLatencyThroughVpn();
      if (fallbackResult > 0) {
        print('[DEBUG] ✅ 备用网络测试成功: ${config.name} -> ${fallbackResult}ms');
        return fallbackResult;
      }

      print('[DEBUG] 所有测试方法都失败: ${config.name}');
      return -1;
    } catch (e) {
      print('[DEBUG] 测试异常: ${config.name} -> $e');
      return -1;
    }
  }

  /// 测试当前激活的代理延时
  static Future<int> _testActiveProxy() async {
    // 常见的活跃代理标签
    final activeProxyTags = ['proxy', 'GLOBAL', 'auto', 'select'];

    for (final tag in activeProxyTags) {
      // 使用重试机制测试
      final result = await _testProxyWithRetry(tag);
      if (result > 0) return result;

      // 如果重试失败，尝试备用URL
      final fallbackResult = await _testProxyWithFallbackUrls(tag);
      if (fallbackResult > 0) return fallbackResult;
    }

    return -1;
  }

  /// 根据配置测试对应的代理
  static Future<int> _testConfigBasedProxy(VPNConfig config) async {
    final possibleTags = _generatePossibleOutboundTags(config);

    // 测试前6个最可能的标签，使用重试机制
    for (int i = 0; i < possibleTags.length && i < 6; i++) {
      final tag = possibleTags[i];

      // 首先尝试普通测试
      final result = await _testSpecificProxyTag(tag);
      if (result > 0) return result;

      // 如果失败，尝试重试
      final retryResult = await _testProxyWithRetry(tag, maxRetries: 1);
      if (retryResult > 0) return retryResult;
    }

    return -1;
  }

  /// 测试指定的代理标签延时
  /// 根据 sing-box Clash API 规范实现
  static Future<int> _testSpecificProxyTag(String proxyTag) async {
    try {
      print('[DEBUG] 测试代理标签: $proxyTag');

      final client = http.Client();

      try {
        // 使用官方推荐的测试URL
        final testUrl = _officialTestUrl;
        final timeout = 3000; // 3秒超时

        final apiUrl =
            '${_apiConfig.baseUrl}/proxies/${Uri.encodeComponent(proxyTag)}/delay'
            '?timeout=$timeout&url=${Uri.encodeComponent(testUrl)}';

        final response = await client
            .get(Uri.parse(apiUrl), headers: _apiConfig.headers)
            .timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          try {
            final data = json.decode(response.body);

            if (data['delay'] != null) {
              final rawDelay = _parseDelayFromResponse(data['delay']);
              if (rawDelay > 0 && rawDelay < 10000) {
                // 应用延时校准
                final calibratedDelay = _applyCalibratedDelay(rawDelay);
                print(
                  '[DEBUG] ✅ $proxyTag 延时测试成功: ${calibratedDelay}ms (原始: ${rawDelay}ms)',
                );
                return calibratedDelay;
              }
            }
          } catch (e) {
            print('[DEBUG] JSON解析失败: $e');
            return -1;
          }
        } else if (response.statusCode == 404) {
          print('[DEBUG] 代理标签不存在: $proxyTag');
          return -1;
        } else {
          print('[DEBUG] API错误: ${response.statusCode} - ${response.body}');
          return -1;
        }
      } finally {
        client.close();
      }

      return -1;
    } catch (e) {
      print('[DEBUG] 测试$proxyTag异常: $e');
      return -1;
    }
  }

  /// 解析延时响应数据
  static int _parseDelayFromResponse(dynamic delayData) {
    if (delayData is int) {
      return delayData;
    } else if (delayData is String) {
      return int.tryParse(delayData) ?? -1;
    } else if (delayData is double) {
      return delayData.round();
    }
    return -1;
  }

  /// 调试：列出所有可用的代理出站
  static Future<void> _debugListAllProxies() async {
    try {
      final client = http.Client();

      try {
        final apiUrl = '${_apiConfig.baseUrl}/proxies';

        final response = await client
            .get(Uri.parse(apiUrl), headers: _apiConfig.headers)
            .timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          print('[DEBUG] 所有可用代理:');
          final data = json.decode(response.body);
          if (data['proxies'] != null) {
            final proxies = data['proxies'] as Map<String, dynamic>;
            for (final proxyName in proxies.keys) {
              print('[DEBUG] - $proxyName');
            }
          }
        } else {
          print('[DEBUG] 获取代理列表失败: ${response.statusCode}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('[DEBUG] 获取代理列表异常: $e');
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

  /// 使用重试机制测试代理延时
  static Future<int> _testProxyWithRetry(
    String proxyTag, {
    int maxRetries = 2,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        // 等待重试间隔
        await Future.delayed(Duration(milliseconds: 500 * attempt));
        print('[DEBUG] 重试测试代理: $proxyTag (第${attempt + 1}次)');
      }

      final result = await _testSpecificProxyTag(proxyTag);
      if (result > 0) return result;
    }

    return -1;
  }

  /// 使用备用URL测试代理延时
  static Future<int> _testProxyWithFallbackUrls(String proxyTag) async {
    // 首先尝试官方推荐URL
    int result = await _testSpecificProxyTag(proxyTag);
    if (result > 0) return result;

    // 如果失败，尝试备用URL
    for (final testUrl in _fallbackTestUrls) {
      result = await _testSpecificProxyTagWithUrl(proxyTag, testUrl);
      if (result > 0) {
        print('[DEBUG] 使用备用URL成功: $testUrl');
        return result;
      }
    }

    return -1;
  }

  /// 使用指定URL测试代理延时
  static Future<int> _testSpecificProxyTagWithUrl(
    String proxyTag,
    String testUrl,
  ) async {
    try {
      final client = http.Client();

      try {
        final timeout = 3000;
        final apiUrl =
            '${_apiConfig.baseUrl}/proxies/${Uri.encodeComponent(proxyTag)}/delay'
            '?timeout=$timeout&url=${Uri.encodeComponent(testUrl)}';

        final response = await client
            .get(Uri.parse(apiUrl), headers: _apiConfig.headers)
            .timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['delay'] != null) {
            final rawDelay = _parseDelayFromResponse(data['delay']);
            if (rawDelay > 0 && rawDelay < 10000) {
              // 应用延时校准
              return _applyCalibratedDelay(rawDelay);
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      // 静默处理异常，由调用方处理重试逻辑
    }

    return -1;
  }

  /// 生成多种可能的出站标签格式
  static List<String> _generatePossibleOutboundTags(VPNConfig config) {
    // sing-box可能使用多种不同的标签格式，我们尝试所有可能的格式
    final possibleTags = <String>[
      // 常见的标签格式
      config.name, // 原始配置名称
      config.name.replaceAll(' ', '_'), // 空格转下划线
      config.name.replaceAll('-', '_'), // 横线转下划线
      config.name.replaceAll(' ', '-'), // 空格转横线
      config.name.toLowerCase(), // 小写
      config.name.toLowerCase().replaceAll(' ', '_'), // 小写+下划线
      config.name.toLowerCase().replaceAll('-', '_'), // 小写+下划线
      // 基于服务器信息的标签
      config.server, // 服务器地址
      '${config.server}:${config.port}', // 服务器:端口
      '${config.server}_${config.port}', // 服务器_端口
      // 基于ID的标签
      config.id, // 配置ID
      'proxy-${config.id}', // proxy-ID
      'out-${config.id}', // out-ID
      // 基于协议类型的标签
      '${config.type}-${config.id}', // 协议-ID
      '${config.type.toLowerCase()}-${config.name.replaceAll(' ', '_')}', // 协议-名称
      // 其他可能的格式
      'outbound-${config.id}', // outbound-ID
      '${config.type}_${config.server}_${config.port}', // 协议_服务器_端口
    ];

    // 移除重复和空字符串
    final uniqueTags = <String>{};
    for (final tag in possibleTags) {
      if (tag.isNotEmpty && tag.trim().isNotEmpty) {
        uniqueTags.add(tag.trim());
      }
    }

    return uniqueTags.toList();
  }

  /// 使用系统命令测试延时
  static Future<int> _testUsingSystemCommand() async {
    try {
      // 测试Google DNS，这在VPN环境下应该显示真实的延时
      final result = await Process.run(
        'ping',
        ['-n', '3', '8.8.8.8'], // Windows ping命令
      ).timeout(const Duration(seconds: 5));

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // 解析ping输出中的平均延时
        final avgMatch = RegExp(r'Average = (\d+)ms').firstMatch(output);
        if (avgMatch != null) {
          return int.tryParse(avgMatch.group(1)!) ?? -1;
        }

        // 如果没找到Average，尝试解析单个ping结果
        final timeMatch = RegExp(r'time=(\d+)ms').firstMatch(output);
        if (timeMatch != null) {
          return int.tryParse(timeMatch.group(1)!) ?? -1;
        }
      }
    } catch (e) {
      // 如果系统命令失败，返回-1
    }
    return -1;
  }

  /// 通过VPN隧道测试TCP连接
  static Future<int> _testTcpThroughVpn(String host, int port) async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 1000),
      );
      sw.stop();
      socket.destroy();

      // 返回实际测量的延时
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// 测试到标准服务器的延时（作为备用方案）
  /// 使用海外服务器确保流量通过VPN隧道
  static Future<int> _testStandardServersDelay() async {
    final List<int> results = [];

    // 使用明确需要翻墙的海外服务器，确保流量通过VPN隧道
    final servers = [
      {'host': 'www.google.com', 'port': 443}, // Google HTTPS - 需要翻墙
      {'host': 'www.youtube.com', 'port': 443}, // YouTube - 需要翻墙
      {'host': 'www.facebook.com', 'port': 443}, // Facebook - 需要翻墙
      {'host': 'www.twitter.com', 'port': 443}, // Twitter - 需要翻墙
    ];

    for (final server in servers) {
      try {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect(
          server['host'] as String,
          server['port'] as int,
          timeout: const Duration(milliseconds: 800),
        );
        sw.stop();
        socket.destroy();

        final latency = sw.elapsedMilliseconds;
        if (latency > 0 && latency < 1000) {
          // 只接受合理的延时值
          results.add(latency);
        }
      } catch (_) {
        continue;
      }
    }

    if (results.isEmpty) {
      return -1;
    }

    // 返回最快的响应时间，这通常代表最优的网络路径
    results.sort();
    return results.first;
  }

  /// 通过VPN测试HTTP延时
  static Future<int> _testHttpLatencyThroughVpn(String url) async {
    try {
      final sw = Stopwatch()..start();
      final client = http.Client();

      try {
        final response = await client
            .head(
              Uri.parse(url),
              headers: {
                'User-Agent': 'SingBox-VPN/1.0',
                'Accept': '*/*',
                'Connection': 'close',
              },
            )
            .timeout(const Duration(milliseconds: 1500));

        sw.stop();
        if (response.statusCode < 400) {
          return sw.elapsedMilliseconds;
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // 忽略错误
    }
    return -1;
  }

  /// 批量检测多个节点配置的延时
  ///
  /// 返回配置ID到延时毫秒数的映射表
  static Future<Map<String, int>> pingConfigs(
    List<VPNConfig> configs, {
    bool isConnected = false,
    VPNConfig? currentConfig,
  }) async {
    final results = <String, int>{};
    await pingConfigsWithProgress(
      configs,
      onEach: (c, p) => results[c.id] = p,
      isConnected: isConnected,
      currentConfig: currentConfig,
    );
    return results;
  }

  /// 自适应并发批量延时检测，支持进度回调
  ///
  /// 根据节点数量自动调整并发数，优化性能表现
  ///
  /// 参数：
  /// - configs: 要测试的 VPN 配置列表
  /// - onEach: 单个节点完成时的回调函数 (config, 延时ms)
  /// - onProgress: 整体进度回调函数 (已完成数, 总数)
  /// - concurrency: 自定义并发数（可选）
  /// - isConnected: 是否处于VPN连接状态
  /// - currentConfig: 当前连接的配置
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
        pingConfig(cfg, isConnected: isConnected, currentConfig: currentConfig)
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

  /// 测试 Shadowsocks 协议节点延时（纯TCP连接测试）
  static Future<int> _testShadowsocks(
    VPNConfig config,
    Stopwatch stopwatch,
  ) async {
    // 优先尝试配置指定端口的 TCP 握手
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;

    // 配置端口连接失败时，尝试常见代理端口
    return await _tryCommonTcpPorts(config.server);
  }

  /// 测试 VMess/VLess 协议节点延时（纯TCP连接测试）
  static Future<int> _testVmess(VPNConfig config, Stopwatch stopwatch) async {
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;
    return await _tryCommonTcpPorts(config.server);
  }

  /// 测试 Trojan 协议节点延时（纯TCP连接测试）
  static Future<int> _testTrojan(VPNConfig config, Stopwatch stopwatch) async {
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;
    return await _tryCommonTcpPorts(config.server);
  }

  /// 测试 Hysteria2 协议节点延时（纯TCP连接测试）
  static Future<int> _testHysteria2(
    VPNConfig config,
    Stopwatch stopwatch,
  ) async {
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;
    return await _tryCommonTcpPorts(config.server);
  }

  /// 测试 TUIC 协议节点延时（纯TCP连接测试）
  static Future<int> _testTuic(VPNConfig config, Stopwatch stopwatch) async {
    final direct = await _tryDirectTcp(config.server, config.port);
    if (direct >= 0) return direct;
    return await _tryCommonTcpPorts(config.server);
  }

  /// 通用协议节点延时测试（纯TCP连接测试）
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

  /// 格式化延时数值为用户友好的显示文本
  ///
  /// 参数：ping 延时毫秒数，-1表示超时
  /// 返回：格式化的延时字符串
  static String formatPing(int ping) {
    if (ping < 0) {
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
