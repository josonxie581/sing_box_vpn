import 'dart:async';
import 'dart:convert';
import 'dart:io';
// ignore_for_file: unused_element
import 'dart:typed_data' show BytesBuilder;
import '../models/vpn_config.dart';
import 'singbox_ffi.dart';
import 'connection_manager.dart';

/// 延时测试模式
enum LatencyTestMode {
  /// 自动：未连VPN用标准测试；已连VPN用绕过测试（推荐，得到更接近真实的节点直连延时）
  auto,

  /// 仅系统路由：无论结果是否被VPN影响，都按系统路由表进行测试（你刚要求的模式）
  systemOnly,

  /// 强制绕过：只要检测到已连VPN，一律使用绕过测试（latency-test-in / 源绑定 / 动态规则等）
  bypass,
}

/// 节点延时测试结果
class NodeDelayResult {
  final String nodeId;
  final String nodeName;
  final String nodeServer;
  final int nodePort;
  final String nodeType;
  final int delay; // 延时(毫秒), -1 表示失败
  final bool isSuccess;
  final String? errorMessage;
  final DateTime testTime;
  final int? httpStatusCode;
  final String? realIpAddress;
  final String? ipLocation;

  NodeDelayResult({
    required this.nodeId,
    required this.nodeName,
    required this.nodeServer,
    required this.nodePort,
    required this.nodeType,
    required this.delay,
    required this.isSuccess,
    this.errorMessage,
    required this.testTime,
    this.httpStatusCode,
    this.realIpAddress,
    this.ipLocation,
  });

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'nodeName': nodeName,
    'nodeServer': nodeServer,
    'nodePort': nodePort,
    'nodeType': nodeType,
    'delay': delay,
    'isSuccess': isSuccess,
    'errorMessage': errorMessage,
    'testTime': testTime.toIso8601String(),
    'httpStatusCode': httpStatusCode,
    'realIpAddress': realIpAddress,
    'ipLocation': ipLocation,
  };
}

/// 节点延时测试器
class NodeDelayTester {
  static const int defaultTimeout = 10000; // 默认超时 10 秒
  static const int defaultMaxConcurrency = 5; // 默认最大并发数
  static const String defaultTestUrl = 'https://cloudflare.com/cdn-cgi/trace';
  static const int defaultTestPort = 10808; // 默认测试端口
  static const int defaultPortBase = 20808; // 默认并发测试端口起始值

  final int timeout;
  final int maxConcurrency;
  final String testUrl;
  final bool enableIpInfo;
  final LatencyTestMode latencyMode;
  // 单个节点完成时的回调（用于批量测试实时更新）
  final void Function(NodeDelayResult result)? onResult;

  // 进度回调
  Function(int completed, int total)? onProgress;

  // 取消令牌
  bool _isCancelled = false;

  // 本地代理端口池（用于并发测试）
  final List<int> _availablePorts = [];
  final Map<int, HttpClient> _portClients = {};

  NodeDelayTester({
    this.timeout = defaultTimeout,
    this.maxConcurrency = defaultMaxConcurrency,
    this.testUrl = defaultTestUrl,
    this.enableIpInfo = true,
    this.latencyMode = LatencyTestMode.auto,
    this.onProgress,
    this.onResult,
  }) {
    // 初始化端口池
    _initPortPool();
  }

  // 判断节点是否为主要使用 UDP 的协议（如 hysteria2/tuic）
  bool _isUdpOnlyNode(VPNConfig node) {
    final t = node.type.toLowerCase();
    if (t.contains('hysteria') || t == 'hysteria2' || t == 'hy2') return true;
    if (t == 'tuic') return true;
    // ShadowTLS/AnyTLS 都是基于 TCP+TLS，这里明确标注为非 UDP-only
    if (t == 'anytls' || t == 'shadowtls') return false;
    return false;
  }

  // 选择用于 TCP 探测的端口：
  // - 对 UDP-only 节点，优先使用 443 进行 TCP 建连测量（避免直连其 UDP 端口导致 Connection refused）
  // - 其他节点使用其配置端口
  int _tcpProbePort(VPNConfig node) {
    return _isUdpOnlyNode(node) ? 443 : node.port;
  }

  /// 初始化端口池
  void _initPortPool() {
    // 生成一组可用端口（从 defaultPortBase 开始）
    for (int i = 0; i < maxConcurrency; i++) {
      _availablePorts.add(defaultPortBase + i);
    }
  }

  /// 取消所有测试
  void cancel() {
    _isCancelled = true;
    _cleanupClients();
  }

  /// 清理所有客户端
  void _cleanupClients() {
    for (final client in _portClients.values) {
      client.close(force: true);
    }
    _portClients.clear();
  }

  /// 测试单个节点（直接TCP连接测试，避免代理开销）
  Future<NodeDelayResult> testSingleNode(
    VPNConfig node, {
    int? proxyPort,
  }) async {
    print('🚀 开始测试节点: ${node.name} (${node.server}:${node.port})');

    if (_isCancelled) {
      print('❌ 测试已取消: ${node.name}');
      return _createFailedResult(node, '测试已取消');
    }

    try {
      // 首先进行快速TCP连接测试，检查节点基本连通性
      print('📡 进行TCP连通性检测...');
      final tcpResult = await quickTest(node);

      if (!tcpResult.isSuccess) {
        print('❌ TCP连接失败，跳过HTTP测试: ${node.name}');
        return tcpResult;
      }

      print('✅ TCP连接正常，延时: ${tcpResult.delay}ms，开始HTTP延时测试...');

      // 使用优化的HTTP客户端直接测试
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = Duration(milliseconds: timeout);
      client.idleTimeout = Duration(milliseconds: timeout);

      // 开始计时HTTP请求
      final stopwatch = Stopwatch()..start();
      print('⏱️ 开始HTTP延时测试，目标URL: $testUrl');

      // 发送HTTP请求
      final request = await client
          .getUrl(Uri.parse(testUrl))
          .timeout(
            Duration(milliseconds: timeout),
            onTimeout: () => throw TimeoutException('HTTP连接超时'),
          );

      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );

      final response = await request.close().timeout(
        Duration(milliseconds: timeout),
        onTimeout: () => throw TimeoutException('HTTP响应超时'),
      );

      stopwatch.stop();
      final httpDelay = stopwatch.elapsedMilliseconds;
      print('✅ HTTP请求完成，延时: ${httpDelay}ms，状态码: ${response.statusCode}');

      // 读取响应内容
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(Duration(milliseconds: 3000), onTimeout: () => '');

      // 解析IP信息（本地IP，非代理IP）
      String? realIp;
      String? ipLocation;

      if (enableIpInfo && testUrl.contains('/cdn-cgi/trace')) {
        final lines = responseBody.split('\n');
        for (final line in lines) {
          if (line.startsWith('ip=')) {
            realIp = line.substring(3);
          } else if (line.startsWith('loc=')) {
            ipLocation = line.substring(4);
          }
        }
        print('🌍 本地IP: $realIp, 位置: $ipLocation');
      }

      client.close();

      // 使用TCP连接延时作为节点延时（更准确）
      final result = NodeDelayResult(
        nodeId: node.id,
        nodeName: node.name,
        nodeServer: node.server,
        nodePort: node.port,
        nodeType: node.type,
        delay: tcpResult.delay, // 使用TCP连接延时
        isSuccess: response.statusCode == 200,
        testTime: DateTime.now(),
        httpStatusCode: response.statusCode,
        realIpAddress: realIp,
        ipLocation: ipLocation,
      );

      print(
        '🎯 测试结果 ${node.name}: ${result.isSuccess ? "成功" : "失败"} - ${tcpResult.delay}ms (TCP连接延时)',
      );
      return result;
    } on TimeoutException catch (e) {
      print('⏰ 测试超时: ${node.name} - $e');
      return _createFailedResult(node, '连接超时');
    } on SocketException catch (e) {
      print('🌐 网络错误: ${node.name} - ${e.message}');
      return _createFailedResult(node, '网络错误: ${e.message}');
    } catch (e) {
      print('❌ 测试失败: ${node.name} - $e');
      return _createFailedResult(node, e.toString());
    }
  }

  /// 批量测试节点
  Future<List<NodeDelayResult>> testMultipleNodes(
    List<VPNConfig> nodes, {
    int? localProxyPort,
  }) async {
    _isCancelled = false;
    final results = <NodeDelayResult>[];
    final totalNodes = nodes.length;
    int completedNodes = 0;

    // 创建信号量控制并发
    final semaphore = _Semaphore(maxConcurrency);
    final futures = <Future<NodeDelayResult>>[];

    for (final node in nodes) {
      if (_isCancelled) {
        results.add(_createFailedResult(node, '测试已取消'));
        continue;
      }

      final future = semaphore.run(() async {
        if (_isCancelled) {
          return _createFailedResult(node, '测试已取消');
        }

        try {
          // 获取可用端口
          final port =
              localProxyPort ??
              (_availablePorts.isNotEmpty
                  ? _availablePorts[completedNodes % _availablePorts.length]
                  : defaultTestPort);

          final result = await testSingleNode(node, proxyPort: port);

          completedNodes++;
          onProgress?.call(completedNodes, totalNodes);
          // 实时回调单个结果
          try {
            onResult?.call(result);
          } catch (_) {}

          return result;
        } catch (e) {
          return _createFailedResult(node, e.toString());
        }
      });

      futures.add(future);
    }

    // 等待所有测试完成
    final allResults = await Future.wait(futures);
    results.addAll(allResults);

    // 按延时排序（成功的在前）
    results.sort((a, b) {
      if (a.isSuccess && !b.isSuccess) return -1;
      if (!a.isSuccess && b.isSuccess) return 1;
      if (a.isSuccess && b.isSuccess) {
        return a.delay.compareTo(b.delay);
      }
      return 0;
    });

    return results;
  }

  /// 智能延时测试 - 基于分流规则绕过VPN路由
  Future<NodeDelayResult> realTest(VPNConfig node) async {
    try {
      print('[分流延时测试] 开始测试: ${node.name} (${node.server}:${node.port})');

      // 1. 先检测VPN连接状态
      final isVpnConnected = await _detectVpnConnection();
      print('[分流延时测试] VPN连接状态: ${isVpnConnected ? "已连接" : "未连接"}');
      // TCP-only：不进行 QUIC/ICMP 预探测，直接按模式走 TCP 绕过/系统测试

      // 根据模式决定测试路径
      switch (latencyMode) {
        case LatencyTestMode.systemOnly:
          if (isVpnConnected) {
            print('[分流延时测试] 模式=systemOnly，使用系统路由表方法测试');
            return await _testWithSystemRouting(node);
          }
          print('[分流延时测试] 模式=systemOnly，未连VPN，使用标准测试');
          return await _standardDelayTest(node);
        case LatencyTestMode.bypass:
          // 总是使用“独立实例/直连路由”的绕过测试，无论是否已连 VPN
          print('[分流延时测试] 模式=bypass（强制），使用独立实例直连路由测试');
          return await _bypassTestWithRouteRule(node);
        case LatencyTestMode.auto:
          if (!isVpnConnected) {
            print('[分流延时测试] 模式=auto，未连VPN，使用标准测试');
            return await _standardDelayTest(node);
          }
          print('[分流延时测试] 模式=auto，已连VPN，使用绕过测试');
          return await _bypassTestWithRouteRule(node);
      }
    } catch (e) {
      print('[分流延时测试] 测试异常: ${node.name} -> $e');
      return _createFailedResult(node, e.toString());
    }
  }

  /// TCP连接测试
  Future<int> _tcpConnectTest(VPNConfig node) async {
    final stopwatch = Stopwatch()..start();
    final socket = await Socket.connect(
      node.server,
      node.port,
      timeout: Duration(milliseconds: timeout),
    );
    stopwatch.stop();
    socket.destroy();
    return stopwatch.elapsedMilliseconds;
  }

  /// HTTP连接测试（直连不使用代理）
  Future<int> _httpConnectTest(VPNConfig node) async {
    // 已废弃：不再单独做 HTTP 连接只为测延时，保留方法占位避免外部引用报错
    throw UnimplementedError();
  }

  /// 原始Socket测试
  Future<int> _rawSocketTest(VPNConfig node) async {
    final stopwatch = Stopwatch()..start();

    // 尝试原始TCP连接
    final socket = await RawSocket.connect(
      node.server,
      node.port,
      timeout: Duration(milliseconds: timeout),
    );

    stopwatch.stop();
    socket.close();
    return stopwatch.elapsedMilliseconds;
  }

  /// 快速测试（TCP连接测试）
  Future<NodeDelayResult> quickTest(VPNConfig node) async {
    print('⚡ 开始快速测试: ${node.name} (${node.server}:${node.port})');
    try {
      // 统一解析为真实 IPv4，避免 FakeIP/IPv6 带来的抖动
      final targetIPv4 = await _resolveIPv4ForTest(node);
      final host = targetIPv4?.address ?? node.server;

      // 对于 UDP-only 协议（hysteria2/hy2/tuic），严格按照 TCP-only：
      // 优先 QUIC/ICMP 探测，失败后再回退到 TCP 连接测试
      if (_isUdpOnlyNode(node)) {
        final quic = await _tryQuicHandshake(node, timeoutMs: 1200);
        if (quic != null) return quic;
        final icmp = await _icmpFallbackNode(node, timeoutMs: 1200);
        if (icmp != null) return icmp;

        print('[快速测试][UDP-only] QUIC/ICMP 失败，回退 TCP 端口候选 [443,80,22]');
        final candidates = <int>[443, 80, 22];
        int? best;
        int usedPort = 443;
        for (final p in candidates) {
          final sw = Stopwatch()..start();
          try {
            final sock = await Socket.connect(
              host,
              p,
              timeout: Duration(milliseconds: timeout),
            );
            sw.stop();
            sock.destroy();
            final ms = sw.elapsedMilliseconds;
            if (best == null || ms < best) {
              best = ms;
              usedPort = p;
            }
          } catch (e) {
            sw.stop();
            if (_isTcpRefusedError(e)) {
              final ms = sw.elapsedMilliseconds;
              if (best == null || ms < best) {
                best = ms;
                usedPort = p;
              }
            }
          }
        }
        if (best != null) {
          return NodeDelayResult(
            nodeId: node.id,
            nodeName: node.name,
            nodeServer: node.server,
            nodePort: usedPort,
            nodeType: node.type,
            delay: best!,
            isSuccess: true,
            testTime: DateTime.now(),
          );
        }
        return _createFailedResult(node, 'UDP-only 节点 TCP 测试超时/不可达');
      }

      // 增加连接前的调试信息
      final port = _tcpProbePort(node);
      print('📡 正在连接到 ${host}:$port...');

      final stopwatch = Stopwatch()..start();

      // 尝试绕过VPN路由，使用原始网络接口
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(milliseconds: timeout),
        sourceAddress: null,
      );

      stopwatch.stop();
      final delay = stopwatch.elapsedMilliseconds;

      // 验证连接是否真实建立，检查本地和远程地址
      final remoteAddress = socket.remoteAddress.address;
      final remotePort = socket.remotePort;
      final localAddress = socket.address.address;
      final localPort = socket.port;

      socket.destroy();

      // 仅输出一行初测摘要，避免把初测延时误认为最终结果
      print(
        '📍 初测: ${node.name} local=$localAddress:$localPort -> remote=$remoteAddress:$remotePort, t=${delay}ms',
      );

      // 检查是否连接到了正确的远程服务器
      if (remoteAddress != node.server && _isIpAddress(node.server)) {
        print('⚠️ 警告: 连接地址不匹配! 期望: ${node.server}, 实际: $remoteAddress');
      }

      // 如果结果可疑（过低、FakeIP、或者本地地址与远端地址相同），仅记录日志，不再进行 ICMP 回退（TCP-only）
      var finalDelay = delay;
      String? realIpForRecord;
      final suspicious =
          delay <= 15 ||
          _isFakeIp(remoteAddress) ||
          localAddress == remoteAddress;
      if (suspicious) {
        print(
          '⚠️ 警告: 结果可疑(延时: ${delay}ms, local=$localAddress, remote=$remoteAddress)，按 TCP-only 保留此结果',
        );
      }

      // 打印最终结果（可能是 ICMP 回退后的值）
      print('✅ 最终结果: ${node.name} -> ${finalDelay}ms');

      return NodeDelayResult(
        nodeId: node.id,
        nodeName: node.name,
        nodeServer: node.server,
        nodePort: port,
        nodeType: node.type,
        delay: finalDelay,
        isSuccess: true,
        testTime: DateTime.now(),
        realIpAddress: realIpForRecord,
      );
    } catch (e) {
      // 若是“连接被拒绝”，也按成功返回 RTT
      if (_isTcpRefusedError(e)) {
        // 无法直接知道刚才的计时，重新测一次快速 RTT（短超时）
        try {
          final sw = Stopwatch()..start();
          await Socket.connect(
            node.server,
            _tcpProbePort(node),
            timeout: Duration(milliseconds: timeout),
          );
          sw.stop();
          final ms = sw.elapsedMilliseconds;
          return NodeDelayResult(
            nodeId: node.id,
            nodeName: node.name,
            nodeServer: node.server,
            nodePort: _tcpProbePort(node),
            nodeType: node.type,
            delay: ms,
            isSuccess: true,
            testTime: DateTime.now(),
          );
        } catch (_) {}
      }
      print('❌ 快速测试失败: ${node.name} - $e');
      return _createFailedResult(node, 'TCP连接失败: $e');
    }
  }

  /// 检查是否是本地地址
  bool _isLocalAddress(String address) {
    return address.startsWith('127.') ||
        address.startsWith('192.168.') ||
        address.startsWith('10.') ||
        address.startsWith('172.') ||
        address == 'localhost';
  }

  /// 批量快速测试
  Future<List<NodeDelayResult>> quickTestMultiple(List<VPNConfig> nodes) async {
    _isCancelled = false;
    final results = <NodeDelayResult>[];

    for (final node in nodes) {
      if (_isCancelled) {
        results.add(_createFailedResult(node, '测试已取消'));
        continue;
      }

      final result = await quickTest(node);
      results.add(result);
      // 实时回调单个结果 测量延时值
      try {
        onResult?.call(result);
      } catch (_) {}

      onProgress?.call(results.length, nodes.length);
    }

    // 排序
    results.sort((a, b) {
      if (a.isSuccess && !b.isSuccess) return -1;
      if (!a.isSuccess && b.isSuccess) return 1;
      if (a.isSuccess && b.isSuccess) {
        return a.delay.compareTo(b.delay);
      }
      return 0;
    });

    return results;
  }

  /// 创建失败结果
  NodeDelayResult _createFailedResult(VPNConfig node, String error) {
    return NodeDelayResult(
      nodeId: node.id,
      nodeName: node.name,
      nodeServer: node.server,
      nodePort: node.port,
      nodeType: node.type,
      delay: -1,
      isSuccess: false,
      errorMessage: error,
      testTime: DateTime.now(),
    );
  }

  /// 检测VPN连接状态
  Future<bool> _detectVpnConnection() async {
    try {
      // 方法1: 检查本地网络接口的VPN特征
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        // 检测常见VPN接口名称
        if (name.contains('tun') ||
            name.contains('tap') ||
            name.contains('vpn') ||
            name.contains('sing-box') ||
            name.contains('wintun')) {
          print('[VPN检测] 检测到VPN接口: ${interface.name}');
          return true;
        }
      }

      // 方法2: 测试路由表变化（通过连接外部地址检测）
      try {
        final socket = await Socket.connect(
          '8.8.8.8',
          53,
          timeout: Duration(seconds: 2),
        );
        final localAddress = socket.address.address;
        socket.destroy();

        // 如果本地地址不是常见的局域网地址，可能通过VPN
        if (!localAddress.startsWith('192.168.') &&
            !localAddress.startsWith('10.') &&
            !localAddress.startsWith('172.')) {
          print('[VPN检测] 检测到可能的VPN路由: $localAddress');
          return true;
        }
      } catch (e) {
        print('[VPN检测] 路由检测失败: $e');
      }

      return false;
    } catch (e) {
      print('[VPN检测] VPN状态检测失败: $e');
      return false; // 默认假设未连接
    }
  }

  /// 通过创建临时配置文件进行真实延时测试（绕过VPN路由）
  Future<NodeDelayResult> _bypassTestWithRouteRule(VPNConfig node) async {
    try {
      print('[独立实例延时测试] 开始测试: ${node.name} (${node.server}:${node.port})');

      // UDP-only 节点优先 QUIC/ICMP 探测，避免 TCP 端口被丢弃导致超高 RTT
      if (_isUdpOnlyNode(node)) {
        final quic = await _tryQuicHandshake(node, timeoutMs: 1500);
        if (quic != null) return quic;
        final icmp = await _icmpFallbackNode(node, timeoutMs: 1500);
        if (icmp != null) return icmp;
        print('[独立实例延时测试] UDP-only QUIC/ICMP 失败，回退 TCP 绕过路径');
      }

      // 你的需求：无论协议，绕过路径优先走 TCP（latency-test-in / 源绑定 / 动态直连）

      // 首选方案：通过固定的 latency-test-in 入站（SOCKS5@127.0.0.1:17890）直连
      // 优点：无需修改/重载配置，不会影响现有连接状态（特别是 TUN）
      try {
        final result = await _testViaLatencyInbound(node);
        return result;
      } catch (e) {
        print('[latency-test-in 入站] 失败: $e，继续尝试其他回退');
      }

      // 次选方案：绑定物理网卡源地址直连（无需管理员权限）
      try {
        final result = await _bypassWithSourceBind(node);
        return result;
      } catch (e) {
        print('[源地址绑定绕过] 失败: $e，继续尝试其他回退');
      }

      // 兜底方案（可能导致 sing-box 重启）：FFI 动态路由规则临时直连
      // 现已将动态规则限制为仅 TCP 且使用探测端口（UDP-only 为 443），对 hy2/tuic 是安全的，不会影响 UDP 出站
      try {
        final result = await _testWithDynamicDirectRule(node);
        return result;
      } catch (e) {
        print('[动态规则绕过] 失败: $e，准备回退到备用方案A/独立进程');
      }

      // 备用方案B：使用临时主机路由（需要管理员权限）强制走物理网卡，测完即删
      try {
        final result = await _testWithHostRouteByNetsh(node);
        return result;
      } catch (e) {
        print('[主机路由直连] 失败: $e，将回退到系统路由测试');
      }
    } catch (e) {
      print('[独立实例延时测试] 测试异常: $e');
      // 如果独立实例失败，使用系统路由表方法
      return await _testWithSystemRouting(node);
    }

    // 所有优先方案均未返回，则回退到系统路由测试
    return await _testWithSystemRouting(node);
  }

  /// 通过添加临时主机路由，强制目标直连物理网卡，然后进行 TCP 测试
  Future<NodeDelayResult> _testWithHostRouteByNetsh(VPNConfig node) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('仅在 Windows 上支持主机路由方案');
    }

    // 解析目标 IPv4 列表
    final targets = <InternetAddress>[];
    if (_isIpAddress(node.server)) {
      targets.add(InternetAddress(node.server));
    } else {
      final a = await _resolveIPv4Direct(node.server, timeoutMs: 1500);
      if (a != null) targets.add(a);
      if (targets.isEmpty) {
        try {
          final addrs = await InternetAddress.lookup(
            node.server,
          ).timeout(const Duration(seconds: 2));
          for (final x in addrs) {
            if (x.type == InternetAddressType.IPv4 && !_isFakeIp(x.address)) {
              targets.add(x);
            }
          }
        } catch (_) {}
      }
    }
    if (targets.isEmpty) {
      throw StateError('无法解析到真实 IPv4: ${node.server}');
    }

    // 获取物理网卡的 InterfaceIndex 和网关
    final ifInfo = await _getBestPhysicalInterface();
    if (ifInfo == null) {
      throw StateError('未找到可用的物理网卡或默认网关');
    }
    final ifIndex = ifInfo.interfaceIndex;
    final gateway = ifInfo.gateway;

    final added = <String>[]; // 已添加的目的 IP（用于回收）
    try {
      for (final ip in targets) {
        final ok = await _netshAddHostRoute(ip.address, gateway, ifIndex);
        if (ok) added.add(ip.address);
      }

      if (added.isEmpty) {
        throw StateError('添加主机路由失败');
      }

      // 给系统一点时间应用路由变更
      await Future.delayed(const Duration(milliseconds: 150));

      // 执行一次标准 TCP 测试（端口为探测端口，UDP-only 使用 443）
      final result = await _standardDelayTest(node);
      return result;
    } finally {
      // 清理路由
      for (final ip in added) {
        await _netshDelHostRoute(ip);
      }
    }
  }

  /// 选择最合适的物理网卡（排除 VPN/TUN），返回接口索引与默认网关
  Future<_IfInfo?> _getBestPhysicalInterface() async {
    try {
      final script = r'''
      function Write-IfInfo($idx,$gw){
        if($idx){
          # 允许 $gw 为 0.0.0.0（PPPoE/直连 on-link 场景）
          if(-not $gw){ $gw = '0.0.0.0' }
          Write-Output "$idx`n$gw"; exit 0
        }
      }

      $exclude = 'tun|tap|vpn|wintun|tailscale|zerotier|hyper\-v|vmware|bluetooth|loopback|vEthernet|virtualbox|sing\-box'

      # Strategy 1: Prefer NICs with IPv4 default gateway and Up state
      $nic = Get-NetIPConfiguration | Where-Object {
        $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' -and `
        $_.NetAdapter.InterfaceDescription -notmatch $exclude -and $_.NetAdapter.Name -notmatch $exclude
      } | Select-Object -First 1
      if($nic){ Write-IfInfo $nic.InterfaceIndex $nic.IPv4DefaultGateway.NextHop }

      # Strategy 2: Use lowest-metric default route
      $routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object -Property RouteMetric,Publish
      foreach($r in $routes){
        # 允许 NextHop 为 0.0.0.0（on-link 默认路由）
        $idx = $r.InterfaceIndex
        $ifi = Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $idx -ErrorAction SilentlyContinue
        if($ifi -and $ifi.ConnectionState -eq 'Connected'){
          $alias = $ifi.InterfaceAlias
          $ad = (Get-NetAdapter -InterfaceIndex $idx -ErrorAction SilentlyContinue)
          $desc = if($ad){$ad.InterfaceDescription}else{''}
          if(($alias -notmatch $exclude) -and ($desc -notmatch $exclude)){
            $gw = if($r.NextHop){$r.NextHop}else{'0.0.0.0'}
            Write-IfInfo $idx $gw
          }
        }
      }

      # Strategy 3: Fallback to any default route
      $r2 = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object -First 1
      if($r2){
        $gw = if($r2.NextHop){$r2.NextHop}else{'0.0.0.0'}
        Write-IfInfo $r2.InterfaceIndex $gw
      }

      # Strategy 4: As a last resort, pick any Connected IPv4 interface with lowest metric (physical-like)
      $ifs = Get-NetIPInterface -AddressFamily IPv4 | Where-Object {
        $_.ConnectionState -eq 'Connected'
      } | Sort-Object -Property InterfaceMetric
      foreach($ifi in $ifs){
        $idx = $ifi.InterfaceIndex
        $alias = $ifi.InterfaceAlias
        $ad = (Get-NetAdapter -InterfaceIndex $idx -ErrorAction SilentlyContinue)
        $desc = if($ad){$ad.InterfaceDescription}else{''}
        if(($alias -notmatch $exclude) -and ($desc -notmatch $exclude)){
          Write-IfInfo $idx '0.0.0.0'
        }
      }
      ''';
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        script,
      ], runInShell: true).timeout(const Duration(seconds: 6));
      final out = (res.stdout as String? ?? '').trim();
      if (out.isEmpty) return null;
      final lines = out.split(RegExp(r'\r?\n'));
      if (lines.length < 2) return null;
      final idx = int.tryParse(lines[0].trim());
      final gw = lines[1].trim();
      if (idx == null || gw.isEmpty) return null;
      final info = _IfInfo(interfaceIndex: idx, gateway: gw);
      print(
        '[主机路由直连] 物理网卡候选: ifIndex=${info.interfaceIndex}, gateway=${info.gateway}',
      );
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _netshAddHostRoute(
    String ip,
    String gateway,
    int ifIndex,
  ) async {
    try {
      // 当 gateway 为 0.0.0.0（on-link）时，使用 netsh 添加 on-link 路由
      String cmd;
      if (gateway == '0.0.0.0') {
        // 使用临时（非持久）路由，测试完成会删除
        cmd =
            'netsh interface ipv4 add route prefix=$ip/32 interface=$ifIndex nexthop=0.0.0.0 store=active';
      } else {
        cmd =
            'route add $ip mask 255.255.255.255 $gateway metric 3 if $ifIndex';
      }

      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        cmd,
      ], runInShell: true).timeout(const Duration(seconds: 3));
      final code = res.exitCode;
      if (code == 0) return true;
      // 若已存在则先删再加
      await _netshDelHostRoute(ip);
      final res2 = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        cmd,
      ], runInShell: true).timeout(const Duration(seconds: 3));
      return res2.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _netshDelHostRoute(String ip) async {
    try {
      final cmd = 'route delete $ip';
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        cmd,
      ], runInShell: true).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// 使用持久化的 latency-test-in (socks 127.0.0.1:17890) 入站进行直连测试
  /// 通过最小 SOCKS5 握手 + CONNECT，测量至目标的建立时延。
  Future<NodeDelayResult> _testViaLatencyInbound(VPNConfig node) async {
    // 不再强依赖 FFI 的 isRunning；直接探测 127.0.0.1:17890 是否存在 SOCKS 入站
    const host = '127.0.0.1';
    const port = 17890;

    // 关键点：为避免 sing-box 的 DNS/FakeIP 干扰，这里总是先在客户端侧解析真实 IPv4，
    // 再以 IPv4 形式发起 SOCKS CONNECT。这样可确保直连到真实目标 IP。
    final targetIPv4 = await _resolveIPv4ForTest(node);
    if (targetIPv4 == null) {
      throw StateError('解析目标域名失败（无可用真实 IPv4）：${node.server}');
    }

    // 针对 UDP-only 节点（如 hysteria2/tuic），避免直连其 UDP 端口的 TCP，改用 443 作为 TCP 测量端口
    final connectPort = _tcpProbePort(node);

    Socket? socket;
    final recv = <int>[];

    Future<List<int>> waitBytes(int n) async {
      final deadline = DateTime.now().millisecondsSinceEpoch + timeout;
      while (recv.length < n) {
        if (DateTime.now().millisecondsSinceEpoch > deadline) {
          throw TimeoutException('读取SOCKS数据超时');
        }
        await Future.delayed(const Duration(milliseconds: 2));
      }
      final out = recv.sublist(0, n);
      recv.removeRange(0, n);
      return out;
    }

    try {
      final sw = Stopwatch()..start();
      socket = await Socket.connect(
        host,
        port,
        timeout: Duration(milliseconds: timeout),
      );
      // 收数据
      socket.listen(
        (data) => recv.addAll(data),
        onError: (_) {},
        cancelOnError: true,
      );

      // 1) greeting: VER=5, NMETHODS=1, METHODS=[0x00]
      socket.add([0x05, 0x01, 0x00]);
      final greeting = await waitBytes(2); // VER, METHOD
      if (greeting.length != 2 || greeting[0] != 0x05 || greeting[1] != 0x00) {
        throw StateError('SOCKS5 不支持无认证或响应异常: $greeting');
      }

      // 2) CONNECT 请求
      final req = <int>[0x05, 0x01, 0x00]; // VER=5, CMD=CONNECT, RSV=0
      // 总是使用 IPv4 地址，避免由 sing-box 进行 DNS 解析（防止 FakeIP/代理DNS干扰）
      req.add(0x01); // ATYP = IPv4
      req.addAll(targetIPv4.rawAddress); // 4 字节
      // 端口（大端）
      req.add(((connectPort) >> 8) & 0xFF);
      req.add((connectPort) & 0xFF);

      socket.add(req);

      // 3) 读取应答：VER, REP, RSV, ATYP, BND.ADDR..., BND.PORT(2)
      final head = await waitBytes(4);
      if (head[0] != 0x05) {
        throw StateError('SOCKS5 应答版本错误: ${head[0]}');
      }
      final rep = head[1];
      // 日志：即便连接被拒绝（rep!=0），我们也把耗时当作 RTT
      if (rep != 0x00) {
        // 记录一次，但不抛错
        // print('[latency-test-in] REP=$rep (非0表示目标拒绝/失败)，仍返回握手耗时');
      }
      final atyp = head[3];
      int remain;
      switch (atyp) {
        case 0x01:
          remain = 4 + 2; // IPv4 + port
          break;
        case 0x03:
          final len = (await waitBytes(1))[0];
          remain = len + 2; // domain + port
          break;
        case 0x04:
          remain = 16 + 2; // IPv6 + port
          break;
        default:
          throw StateError('未知 ATYP: $atyp');
      }
      // 读取剩余的 BND.ADDR/BND.PORT 字段（不关心具体值，这里仅为完成握手）；
      // 即便 rep != 0（连接失败/被拒绝），我们也把耗时作为 RTT 返回
      await waitBytes(remain);

      sw.stop();
      final delay = sw.elapsedMilliseconds;

      socket.destroy();
      return NodeDelayResult(
        nodeId: node.id,
        nodeName: node.name,
        nodeServer: node.server,
        nodePort: node.port,
        nodeType: node.type,
        delay: delay,
        isSuccess: true,
        testTime: DateTime.now(),
      );
    } catch (e) {
      throw Exception('通过 latency-test-in 入站测试失败: $e');
    }
  }

  /// 通过动态直连路由规则临时绕过（仅匹配 TCP + 指定端口），测完即清理
  Future<NodeDelayResult> _testWithDynamicDirectRule(VPNConfig node) async {
    try {
      final ffi = SingBoxFFI.instance;

      // 解析真实 IPv4（优先直连解析）
      final resolved = <String>[];
      if (_isIpAddress(node.server)) {
        resolved.add('${node.server}/32');
      } else {
        final ip = await _resolveIPv4Direct(node.server, timeoutMs: 1500);
        if (ip != null) {
          resolved.add('${ip.address}/32');
        }
      }

      // 构造直连规则（仅 TCP，端口为探测端口；UDP-only 节点使用 443）
      final tag = 'latency-bypass-${DateTime.now().millisecondsSinceEpoch}';
      final probePort = _tcpProbePort(node);
      final ipRule = <String, dynamic>{
        'tag': tag,
        if (resolved.isNotEmpty) 'ip_cidr': resolved,
        if (!_isIpAddress(node.server)) 'domain': ['full:${node.server}'],
        'port': probePort,
        'network': 'tcp',
        'outbound': 'direct',
      };
      final ipRuleJson = json.encode(ipRule);

      print('[动态规则绕过] 添加直连规则(仅TCP): $ipRuleJson');
      final ok1 = ffi.addRouteRule(ipRuleJson);
      if (!ok1) {
        final err = () {
          try {
            return ffi.getLastError();
          } catch (_) {
            return '';
          }
        }();
        throw StateError('添加动态路由规则失败${err.isNotEmpty ? ': ' + err : ''}');
      }

      // 可能需要 reload 才生效（若不支持会忽略）
      try {
        final ok = ffi.reloadConfig();
        if (!ok) {
          await _softReconnectIfUsingTun();
        }
      } catch (_) {}

      try {
        // 路由规则就位后，执行一次标准 TCP 测试（应绕过 VPN）
        final result = await _standardDelayTest(node, isVpnBypass: true);
        if (result.isSuccess && result.delay < 5) {
          print('[动态规则绕过] 警告: 延时过低(${result.delay}ms)，可能仍受VPN路由影响');
        }
        return result;
      } finally {
        // 清理规则并尝试恢复路由
        print('[动态规则绕过] 移除直连规则');
        bool removed = false;
        try {
          removed = ffi.removeRouteRule(ipRuleJson);
        } catch (_) {}
        try {
          final ok2 = ffi.reloadConfig();
          if (!ok2) {
            await _softReconnectIfUsingTun();
          }
        } catch (_) {}
        if (!removed) {
          try {
            ffi.clearRouteRules();
            final ok3 = ffi.reloadConfig();
            if (!ok3) {
              await _softReconnectIfUsingTun();
            }
          } catch (_) {}
        }
        await _softReconnectIfUsingTun();
      }
    } catch (e) {
      throw Exception('动态规则绕过失败: $e');
    }
  }

  /// 若当前处于已连接且启用了 TUN，则做一次轻量“软重连”以修复可能的路由失稳
  Future<void> _softReconnectIfUsingTun() async {
    try {
      final cm = ConnectionManager();
      if (cm.isConnected && cm.useTun) {
        print('[动态规则绕过] 检测到 TUN 连接，执行软重连以修复路由');
        final ok = await cm.reloadCurrentConfig();
        print('[动态规则绕过] 软重连结果: ${ok ? '成功' : '失败'}');
      }
    } catch (e) {
      print('[动态规则绕过] 软重连异常: $e');
    }
  }

  /// 创建用于延时测试的最小化直连配置
  Map<String, dynamic> _createDirectTestConfig(VPNConfig node) {
    return {
      "log": {"level": "error", "timestamp": false},
      "dns": {
        "servers": [
          {"tag": "cloudflare", "address": "1.1.1.1", "detour": "direct"},
        ],
        "rules": [],
        "strategy": "prefer_ipv4",
        "disable_cache": true,
        "disable_expire": true,
      },
      "inbounds": [
        {
          "tag": "mixed-in",
          "type": "mixed",
          "listen": "127.0.0.1",
          "listen_port": 0, // 让系统自动分配端口
        },
      ],
      "outbounds": [
        {"tag": "direct", "type": "direct"},
      ],
      "route": {
        "rules": [
          // 所有流量都走直连
          {
            "protocol": ["dns"],
            "outbound": "direct",
          },
          {
            "network": ["tcp", "udp"],
            "outbound": "direct",
          },
        ],
        "final": "direct",
        "auto_detect_interface": true,
      },
    };
  }

  /// 保存临时配置文件
  Future<File> _saveTempConfig(Map<String, dynamic> config) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      '${tempDir.path}/sing_box_test_${DateTime.now().millisecondsSinceEpoch}.json',
    );

    final configJson = json.encode(config);
    await tempFile.writeAsString(configJson);

    return tempFile;
  }

  /// 使用Process运行独立的sing-box进程进行测试
  Future<NodeDelayResult> _testWithProcess(
    VPNConfig node,
    String singboxPath,
    File configFile,
  ) async {
    Process? process;
    try {
      print('[独立进程测试] 启动sing-box: $singboxPath');

      // 启动sing-box进程
      process = await Process.start(singboxPath, [
        '-c',
        configFile.path,
        'run',
      ], mode: ProcessStartMode.detached);

      // 等待进程启动
      await Future.delayed(Duration(milliseconds: 1500));

      // 检查进程是否还在运行
      if (process.pid == 0) {
        throw Exception('sing-box进程启动失败');
      }

      print('[独立进程测试] sing-box进程已启动，PID: ${process.pid}');

      // 使用标准TCP测试，这时应该会走独立实例的直连路由
      final testResult = await _standardDelayTest(node, isVpnBypass: true);

      return testResult;
    } finally {
      // 清理进程
      if (process != null) {
        try {
          process.kill();
          print('[独立进程测试] 已终止sing-box进程');
        } catch (e) {
          print('[独立进程测试] 终止进程时出错: $e');
        }
      }
    }
  }

  /// 使用系统路由表方法进行测试（备用方案）
  Future<NodeDelayResult> _testWithSystemRouting(VPNConfig node) async {
    print('[系统路由测试] 使用系统路由表方法测试: ${node.name} (TCP-only)');
    // 直接使用标准 TCP 测试但标记为系统路由；不做 QUIC/ICMP 兜底
    final result = await _standardDelayTest(node, isVpnBypass: false);
    if (result.isSuccess && result.delay < 10) {
      print('[系统路由测试] 警告: 延时过小(${result.delay}ms)，可能仍被VPN路由影响');
    }
    return result;
  }

  /// 执行 QUIC 最小握手测量（仅针对 UDP-only 节点）；成功返回结果，否则返回 null
  Future<NodeDelayResult?> _tryQuicHandshake(
    VPNConfig node, {
    int timeoutMs = 1500,
  }) async {
    try {
      final ffi = SingBoxFFI.instance;
      final sni =
          (node.settings['sni']?.toString() ??
                  node.settings['host']?.toString() ??
                  node.server)
              .toString();
      List<String>? alpn;
      final rawAlpn = node.settings['alpn'];
      if (rawAlpn is List) {
        alpn = rawAlpn.whereType<String>().toList();
      }
      final t = node.type.toLowerCase();
      if ((alpn == null || alpn.isEmpty) && (t == 'hysteria2' || t == 'hy2')) {
        alpn = ['hysteria2'];
      }
      final insecure = node.settings['skipCertVerify'] == true;
      final sw = Stopwatch()..start();
      final ok = ffi.probeQUIC(
        host: node.server,
        port: node.port,
        sni: sni,
        insecure: insecure,
        alpn: alpn,
        timeoutMs: timeoutMs,
      );
      sw.stop();
      if (ok) {
        final ms = sw.elapsedMilliseconds == 0 ? 1 : sw.elapsedMilliseconds;
        return NodeDelayResult(
          nodeId: node.id,
          nodeName: node.name,
          nodeServer: node.server,
          nodePort: node.port,
          nodeType: node.type,
          delay: ms,
          isSuccess: true,
          testTime: DateTime.now(),
        );
      }
    } catch (e) {
      print('⚠️ QUIC 最小握手测量异常: $e');
    }
    return null;
  }

  /// UDP-only 节点的 ICMP 兜底
  Future<NodeDelayResult?> _icmpFallbackNode(
    VPNConfig node, {
    int timeoutMs = 1200,
  }) async {
    try {
      final ip = _isIpAddress(node.server)
          ? InternetAddress(node.server)
          : await _resolveIPv4Direct(node.server, timeoutMs: timeoutMs) ??
                (await InternetAddress.lookup(
                  node.server,
                )).firstWhere((a) => a.type == InternetAddressType.IPv4);
      String? srcBind;
      try {
        srcBind = await _pickPhysicalIPv4();
      } catch (_) {}
      int? icmp;
      if (srcBind != null && Platform.isWindows) {
        icmp = await _icmpPingIPv4(
          ip.address,
          timeoutMs: timeoutMs,
          sourceIp: srcBind,
        );
      }
      icmp ??= await _icmpPingIPv4(ip.address, timeoutMs: timeoutMs);
      if (icmp != null && icmp >= 0) {
        return NodeDelayResult(
          nodeId: node.id,
          nodeName: node.name,
          nodeServer: node.server,
          nodePort: node.port,
          nodeType: node.type,
          delay: icmp,
          isSuccess: true,
          testTime: DateTime.now(),
          realIpAddress: ip.address,
        );
      }
    } catch (e) {
      print('⚠️ UDP-only 节点 ICMP 回退异常: $e');
    }
    return null;
  }

  /// 执行direct测试
  Future<NodeDelayResult> _performDirectTest(VPNConfig node) async {
    final stopwatch = Stopwatch()..start();

    try {
      final socket = await Socket.connect(
        node.server,
        node.port,
        timeout: Duration(milliseconds: timeout),
      );

      stopwatch.stop();
      final delay = stopwatch.elapsedMilliseconds;

      // 验证连接信息
      final remoteAddress = socket.remoteAddress.address;
      final localAddress = socket.address.address;

      socket.destroy();

      print('[direct测试] 连接成功: ${node.server}:${node.port}');
      print('[direct测试] 本地地址: $localAddress, 远程地址: $remoteAddress');
      print('[direct测试] 延时: ${delay}ms');

      return NodeDelayResult(
        nodeId: node.id,
        nodeName: node.name,
        nodeServer: node.server,
        nodePort: node.port,
        nodeType: node.type,
        delay: delay,
        isSuccess: true,
        testTime: DateTime.now(),
      );
    } catch (e) {
      stopwatch.stop();
      return _createFailedResult(node, 'direct测试失败: $e');
    }
  }

  /// 检查是否为IP地址
  bool _isIpAddress(String address) {
    final ip = InternetAddress.tryParse(address);
    return ip != null && ip.type == InternetAddressType.IPv4;
  }

  // 判断是否落在 FakeIP 常用网段（198.18.0.0/15）
  bool _isFakeIp(String ip) {
    try {
      final addr = InternetAddress(ip);
      if (addr.type != InternetAddressType.IPv4) return false;
      final octets = addr.address.split('.').map(int.parse).toList();
      // 198.18.0.0/15 -> 前两段 198.18 或 198.19
      return octets.length == 4 &&
          octets[0] == 198 &&
          (octets[1] == 18 || octets[1] == 19);
    } catch (_) {
      return false;
    }
  }

  // 直连 UDP DNS 解析（绑定物理网卡），优先返回 IPv4；失败返回 null
  Future<InternetAddress?> _resolveIPv4Direct(
    String host, {
    int timeoutMs = 1500,
  }) async {
    try {
      // 选一个物理网卡 IPv4 作为源地址
      final src = await _pickPhysicalIPv4();
      final bind = src != null ? InternetAddress(src) : InternetAddress.anyIPv4;
      // 选择一个稳定公共DNS（避免被代理）：223.5.5.5 或 8.8.8.8
      final dnsServer = InternetAddress('223.5.5.5');
      final socket = await RawDatagramSocket.bind(
        bind,
        0,
        reuseAddress: false,
      ).timeout(Duration(milliseconds: timeoutMs));
      try {
        socket.readEventsEnabled = true;
        // 构造简单 A 记录查询报文（不考虑 EDNS / 压缩优化）
        final id = DateTime.now().millisecondsSinceEpoch & 0xffff;
        final qname = _encodeDnsName(host);
        final packet = BytesBuilder()
          ..add([id >> 8, id & 0xff]) // ID
          ..add([0x01, 0x00]) // 标志：标准查询
          ..add([0x00, 0x01]) // QDCOUNT=1
          ..add([0x00, 0x00]) // ANCOUNT=0
          ..add([0x00, 0x00]) // NSCOUNT=0
          ..add([0x00, 0x00]) // ARCOUNT=0
          ..add(qname)
          ..add([0x00, 0x01]) // QTYPE=A
          ..add([0x00, 0x01]); // QCLASS=IN
        socket.send(packet.toBytes(), dnsServer, 53);

        final deadline = DateTime.now().millisecondsSinceEpoch + timeoutMs;
        while (DateTime.now().millisecondsSinceEpoch < deadline) {
          await Future.delayed(const Duration(milliseconds: 5));
          final dg = socket.receive();
          if (dg == null) continue;
          final resp = dg.data;
          if (resp.length < 12) continue;
          // 跳过头+问题部分，粗略解析 A 记录
          int offset = 12;
          // 跳过 QNAME
          while (offset < resp.length && resp[offset] != 0) {
            offset += 1 + resp[offset];
          }
          offset += 1; // 终止 0
          if (offset + 4 > resp.length) continue;
          offset += 4; // QTYPE/QCLASS
          // 遍历答案
          while (offset + 12 <= resp.length) {
            // 跳过 NAME（可能是指针 0xC0xx 或者标签序列）
            if (resp[offset] & 0xC0 == 0xC0) {
              offset += 2;
            } else {
              while (offset < resp.length && resp[offset] != 0) {
                offset += 1 + resp[offset];
              }
              offset += 1;
            }
            if (offset + 10 > resp.length) break;
            final type = (resp[offset] << 8) | resp[offset + 1];
            // class = IN, TTL(4)
            final rdlength = (resp[offset + 8] << 8) | resp[offset + 9];
            offset += 10;
            if (offset + rdlength > resp.length) break;
            if (type == 1 && rdlength == 4) {
              final a = InternetAddress(
                '${resp[offset]}.${resp[offset + 1]}.${resp[offset + 2]}.${resp[offset + 3]}',
              );
              socket.close();
              return a;
            }
            offset += rdlength;
          }
        }
      } finally {
        try {
          socket.close();
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  List<int> _encodeDnsName(String name) {
    final parts = name.split('.');
    final bb = BytesBuilder();
    for (final p in parts) {
      final bytes = utf8.encode(p);
      if (bytes.length > 63) throw ArgumentError('label too long');
      bb.add([bytes.length]);
      bb.add(bytes);
    }
    bb.add([0]);
    return bb.toBytes();
  }

  /// 使用sing-box direct出站进行测试
  Future<NodeDelayResult> _testWithSingBoxDirect(
    VPNConfig node,
    Map<String, dynamic> config,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 先测试配置是否有效
      final configJson = json.encode(config);
      print('[direct出站] 测试配置: $configJson');

      final testConfigResult = SingBoxFFI.instance.testConfig(configJson);
      if (testConfigResult != 0) {
        print('[direct出站] 配置测试失败，返回码: $testConfigResult');
        final error = SingBoxFFI.instance.getLastError();
        throw Exception('sing-box配置测试失败: $error');
      }

      print('[direct出站] 配置测试通过，开始延时测试');

      // 执行真实的Socket连接测试
      // 注意：这里我们仍然使用Dart的Socket，但是通过sing-box配置来影响路由
      final socket = await Socket.connect(
        node.server,
        node.port,
        timeout: Duration(milliseconds: timeout),
      );

      stopwatch.stop();
      final delay = stopwatch.elapsedMilliseconds;

      // 验证连接信息
      final remoteAddress = socket.remoteAddress.address;
      final localAddress = socket.address.address;

      socket.destroy();

      print('[direct出站测试] 连接成功: ${node.server}:${node.port}');
      print('[direct出站测试] 本地地址: $localAddress, 远程地址: $remoteAddress');
      print('[direct出站测试] 延时: ${delay}ms');

      return NodeDelayResult(
        nodeId: node.id,
        nodeName: node.name,
        nodeServer: node.server,
        nodePort: node.port,
        nodeType: node.type,
        delay: delay,
        isSuccess: true,
        testTime: DateTime.now(),
      );
    } catch (e) {
      stopwatch.stop();
      return _createFailedResult(node, 'direct出站连接失败: $e');
    }
  }

  /// 方案A：通过绑定非VPN物理网卡的源地址进行直连，强制走物理出口
  Future<NodeDelayResult> _bypassWithSourceBind(VPNConfig node) async {
    print('[源地址绑定绕过] 尝试使用非VPN物理网卡直连 ${node.server}:${node.port}');
    // 选择一个合适的物理网卡 IPv4 地址
    final sourceIp = await _pickPhysicalIPv4();
    if (sourceIp == null) {
      throw StateError('未找到可用的物理网卡 IPv4 地址');
    }

    // DNS 解析必须在计时之前完成，否则 DNS 超时会被误计入延迟
    final candidates = <int>[_tcpProbePort(node), 80, 22];
    final targetIPv4 = await _resolveIPv4ForTest(node);
    final host = targetIPv4?.address ?? node.server;

    final sw = Stopwatch()..start();
    try {
      int? best;
      int usedPort = candidates.first;
      for (final p in candidates) {
        try {
          final s = await Socket.connect(
            host,
            p,
            timeout: Duration(milliseconds: timeout),
            sourceAddress: InternetAddress(sourceIp),
          );
          sw.stop();
          final delay = sw.elapsedMilliseconds;
          final local = s.address.address;
          final remote = s.remoteAddress.address;
          s.destroy();
          if (best == null || delay < best) {
            best = delay;
            usedPort = p;
          }
          print('[源地址绑定绕过] 成功: $local -> $remote，端口: $p，延时: ${delay}ms');
        } catch (e) {
          sw.stop();
          if (_isTcpRefusedError(e)) {
            final ms = sw.elapsedMilliseconds;
            if (best == null || ms < best) {
              best = ms;
              usedPort = p;
            }
            print('[源地址绑定绕过] 被拒绝: 端口 $p，RTT=${ms}ms');
          }
        } finally {
          sw.reset();
          sw.start();
        }
      }
      if (best != null) {
        return NodeDelayResult(
          nodeId: node.id,
          nodeName: node.name,
          nodeServer: node.server,
          nodePort: usedPort,
          nodeType: node.type,
          delay: best,
          isSuccess: true,
          testTime: DateTime.now(),
        );
      }
      throw Exception('源地址绑定直连失败: 所有端口均超时/不可达');
    } catch (e) {
      sw.stop();
      if (_isTcpRefusedError(e)) {
        final ms = sw.elapsedMilliseconds;
        print('[源地址绑定绕过] 连接被拒绝，返回 RTT=${ms}ms');
        return NodeDelayResult(
          nodeId: node.id,
          nodeName: node.name,
          nodeServer: node.server,
          nodePort: node.port,
          nodeType: node.type,
          delay: ms,
          isSuccess: true,
          testTime: DateTime.now(),
        );
      }
      throw Exception('源地址绑定直连失败: $e');
    }
  }

  /// 选择一个非 VPN 的物理网卡 IPv4 地址（优先 192.168/10/172.16-31，排除 169.254 和 回环）
  Future<String?> _pickPhysicalIPv4() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
    );

    bool isVpnName(String name) {
      final n = name.toLowerCase();
      return n.contains('tun') ||
          n.contains('tap') ||
          n.contains('vpn') ||
          n.contains('sing-box') ||
          n.contains('wintun');
    }

    String? candidate;
    for (final iface in interfaces) {
      if (isVpnName(iface.name)) continue;
      for (final addr in iface.addresses) {
        if (addr.type != InternetAddressType.IPv4) continue;
        final ip = addr.address;
        if (ip.startsWith('169.254.')) continue; // 链路本地
        // 优先私网地址
        if (ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            _is172Private(ip)) {
          return ip;
        }
        candidate ??= ip; // 先记录一个备选
      }
    }
    return candidate;
  }

  bool _is172Private(String ip) {
    if (!ip.startsWith('172.')) return false;
    try {
      final parts = ip.split('.');
      final second = int.parse(parts[1]);
      return second >= 16 && second <= 31;
    } catch (_) {
      return false;
    }
  }

  /// 标准延时测试（VPN未连接时使用）
  Future<NodeDelayResult> _standardDelayTest(
    VPNConfig node, {
    bool isVpnBypass = true,
    int? overridePort,
  }) async {
    // DNS 解析必须在计时之前完成，否则 DNS 超时会被误计入延迟
    final port = overridePort ?? _tcpProbePort(node);
    final targetIPv4 = await _resolveIPv4ForTest(node);
    final host = targetIPv4?.address ?? node.server;

    final stopwatch = Stopwatch()..start();

    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(milliseconds: timeout),
      );

      stopwatch.stop();
      final delay = stopwatch.elapsedMilliseconds;
      final remote = socket.remoteAddress.address;
      final local = socket.address.address;
      final localPort = socket.port;
      final remotePort = socket.remotePort;
      socket.destroy();

      print(
        '[标准测试] ${node.name} port=$port: ${delay}ms (local $local:$localPort -> remote $remote:$remotePort)',
      );

      // 基础结果（先按系统路由值返回）
      var base = NodeDelayResult(
        nodeId: node.id,
        nodeName: node.name,
        nodeServer: node.server,
        nodePort: port,
        nodeType: node.type,
        delay: delay,
        isSuccess: true,
        testTime: DateTime.now(),
        realIpAddress: remote,
      );

      // TCP-only：不做 ICMP 回退；仅记录可疑情况
      if (!isVpnBypass) {
        final isFake = _isFakeIp(remote);
        final tooLow = delay <= 15;
        if (isFake || tooLow) {
          print(
            '[系统路由测试] 注意: ${isFake ? '命中FakeIP' : ''}${tooLow ? ' / 延时异常低' : ''}，按 TCP-only 保留原值',
          );
        }
      }

      return base;
    } catch (e) {
      stopwatch.stop();

      // 若是“连接被拒绝”，按成功返回 RTT
      if (_isTcpRefusedError(e)) {
        final ms = stopwatch.elapsedMilliseconds;
        print('[标准测试] 连接被拒绝，返回 RTT=${ms}ms');
        return NodeDelayResult(
          nodeId: node.id,
          nodeName: node.name,
          nodeServer: node.server,
          nodePort: port,
          nodeType: node.type,
          delay: ms,
          isSuccess: true,
          testTime: DateTime.now(),
          realIpAddress: null,
        );
      }

      // 针对 UDP-only 节点的超时等情况，尝试对 443/80/22 端口做一次兜底测量
      final isUdp = _isUdpOnlyNode(node);
      if (overridePort == null && isUdp) {
        int? best;
        int usedPort = 443;
        for (final p in [443, 80, 22]) {
          final sw = Stopwatch()..start();
          try {
            final s = await Socket.connect(
              host,
              p,
              timeout: Duration(milliseconds: timeout),
            );
            sw.stop();
            s.destroy();
            final ms = sw.elapsedMilliseconds;
            if (best == null || ms < best) {
              best = ms;
              usedPort = p;
            }
          } catch (ee) {
            sw.stop();
            if (_isTcpRefusedError(ee)) {
              final ms = sw.elapsedMilliseconds;
              if (best == null || ms < best) {
                best = ms;
                usedPort = p;
              }
            }
          }
        }
        if (best != null) {
          return NodeDelayResult(
            nodeId: node.id,
            nodeName: node.name,
            nodeServer: node.server,
            nodePort: usedPort,
            nodeType: node.type,
            delay: best,
            isSuccess: true,
            testTime: DateTime.now(),
            realIpAddress: null,
          );
        }
      }
      return _createFailedResult(node, '标准测试失败: $e');
    }
  }

  // 统一解析真实 IPv4：直连 DNS 优先，其次系统 DNS（过滤常见 FakeIP 段）
  Future<InternetAddress?> _resolveIPv4ForTest(VPNConfig node) async {
    try {
      if (_isIpAddress(node.server)) return InternetAddress(node.server);
      final direct = await _resolveIPv4Direct(node.server, timeoutMs: 1500);
      if (direct != null) return direct;
      final addrs = await InternetAddress.lookup(
        node.server,
      ).timeout(const Duration(seconds: 2));
      for (final a in addrs) {
        if (a.type == InternetAddressType.IPv4 && !_isFakeIp(a.address)) {
          return a;
        }
      }
    } catch (_) {}
    return null;
  }

  // 识别“TCP 连接被拒绝”的错误
  bool _isTcpRefusedError(Object e) {
    if (e is SocketException) {
      final code = e.osError?.errorCode ?? 0;
      final msg = (e.message + ' ' + (e.osError?.message ?? '')).toLowerCase();
      if (code == 10061 || code == 1225 || code == 111 || code == 61) {
        return true; // Windows(10061/1225), Linux/Android(111), macOS(61)
      }
      if (msg.contains('refused') ||
          msg.contains('actively refused') ||
          msg.contains('拒绝') ||
          msg.contains('被拒绝')) {
        return true;
      }
    }
    return false;
  }

  /// 单次 ICMP 测量（跨平台）：
  /// - Windows: ping -n 1 -w <ms> [-S src]
  /// - Android/Linux: ping -c 1 -W <sec> -w <sec>
  /// 返回毫秒；失败返回 null
  Future<int?> _icmpPingIPv4(
    String ipv4, {
    int timeoutMs = 1000,
    String? sourceIp,
  }) async {
    try {
      List<String> args = [];
      String cmd = 'ping';
      if (Platform.isWindows) {
        args = ['-n', '1', '-w', timeoutMs.toString()];
        if (sourceIp != null && sourceIp.isNotEmpty) {
          args.addAll(['-S', sourceIp]);
        }
      } else {
        final sec = (timeoutMs / 1000).ceil();
        args = ['-c', '1', '-W', sec.toString(), '-w', sec.toString()];
      }
      args.add(ipv4);

      final result = await Process.run(
        cmd,
        args,
        runInShell: true,
      ).timeout(Duration(milliseconds: timeoutMs + 500));

      final out = (result.stdout as String?) ?? '';
      final err = (result.stderr as String?) ?? '';
      final text = out.isNotEmpty ? out : err;
      // Windows: time=12ms / 时间=12ms / time<1ms；Linux/Android: time=12.3 ms
      final patterns = <RegExp>[
        RegExp(r'time[=<]\s*(\d+(?:\.\d+)?)\s*ms', caseSensitive: false),
        RegExp(r'时间[=<]\s*(\d+(?:\.\d+)?)\s*ms'),
      ];
      for (final re in patterns) {
        final m = re.firstMatch(text);
        if (m != null) {
          final s = m.group(1)!;
          final v = double.tryParse(s);
          if (v != null) return v < 1.0 ? 1 : v.round();
        }
      }
      if (text.contains('时间<1ms') ||
          text.toLowerCase().contains('time<1ms') ||
          text.toLowerCase().contains('time< 1ms')) {
        return 1;
      }
      return null;
    } catch (e) {
      print('ICMP ping 失败: $e');
      return null;
    }
  }

  /// VPN绕过延时测试（VPN已连接时使用）
  /// 基于xray-knife的DialContext原理实现
  Future<NodeDelayResult> _vpnBypassDelayTest(VPNConfig node) async {
    print('[VPN绕过测试] 执行VPN绕过延时测试');

    // 策略1: 使用多个DNS服务器进行解析，绕过VPN DNS
    final results = <int>[];

    // 方法1: 使用系统DNS（可能被VPN影响）
    try {
      final systemDnsResult = await _testWithSpecificDns(node, null);
      if (systemDnsResult > 0) {
        results.add(systemDnsResult);
        print('[VPN绕过测试] 系统DNS测试: ${systemDnsResult}ms');
      }
    } catch (e) {
      print('[VPN绕过测试] 系统DNS测试失败: $e');
    }

    // 方法2: 使用公共DNS绕过VPN DNS（CloudFlare）
    try {
      final cloudflareResult = await _testWithSpecificDns(node, '1.1.1.1');
      if (cloudflareResult > 0) {
        results.add(cloudflareResult);
        print('[VPN绕过测试] CloudFlare DNS测试: ${cloudflareResult}ms');
      }
    } catch (e) {
      print('[VPN绕过测试] CloudFlare DNS测试失败: $e');
    }

    // 方法3: 使用Google DNS
    try {
      final googleResult = await _testWithSpecificDns(node, '8.8.8.8');
      if (googleResult > 0) {
        results.add(googleResult);
        print('[VPN绕过测试] Google DNS测试: ${googleResult}ms');
      }
    } catch (e) {
      print('[VPN绕过测试] Google DNS测试失败: $e');
    }

    // 方法4: 直接IP连接（如果node.server是IP地址）
    if (_isIpAddress(node.server)) {
      try {
        final directIpResult = await _testDirectIpConnection(node);
        if (directIpResult > 0) {
          results.add(directIpResult);
          print('[VPN绕过测试] 直接IP连接测试: ${directIpResult}ms');
        }
      } catch (e) {
        print('[VPN绕过测试] 直接IP连接测试失败: $e');
      }
    }

    if (results.isEmpty) {
      return _createFailedResult(node, 'VPN绕过测试全部失败');
    }

    // 智能选择策略：
    // 1. 如果所有结果都很相近（差距<50ms），选择最高值（更保守）
    // 2. 如果有明显异常值（过低<20ms），排除后选择
    final filteredResults = _filterAnomalousResults(results);
    final finalDelay = filteredResults.isNotEmpty
        ? filteredResults.reduce((a, b) => a > b ? a : b)
        : results.reduce((a, b) => a > b ? a : b);

    print(
      '[VPN绕过测试] VPN绕过延时测试完成: ${node.name} -> ${finalDelay}ms (从${results.length}个结果中选择)',
    );

    return NodeDelayResult(
      nodeId: node.id,
      nodeName: node.name,
      nodeServer: node.server,
      nodePort: node.port,
      nodeType: node.type,
      delay: finalDelay,
      isSuccess: true,
      testTime: DateTime.now(),
    );
  }

  /// 过滤异常结果（过低的延时可能是VPN本地回环造成的）
  List<int> _filterAnomalousResults(List<int> results) {
    if (results.length <= 1) return results;

    final sorted = List<int>.from(results)..sort();
    final median = sorted[sorted.length ~/ 2];

    // 过滤掉明显过低的结果（可能是本地回环）
    final filtered = results.where((result) {
      // 如果结果小于20ms且比中位数小很多，可能是异常值
      if (result < 20 && median > 100) return false;
      if (result < 10) return false; // 极低值肯定是异常的
      return true;
    }).toList();

    print(
      '[VPN绕过测试] 结果过滤: ${results.length} -> ${filtered.length} (移除了${results.length - filtered.length}个异常值)',
    );
    return filtered;
  }

  /// 使用特定DNS进行测试
  Future<int> _testWithSpecificDns(VPNConfig node, String? dnsServer) async {
    final stopwatch = Stopwatch()..start();

    try {
      String targetHost = node.server;

      // 如果指定了DNS服务器且目标不是IP地址，进行DNS解析
      if (dnsServer != null && !_isIpAddress(node.server)) {
        print('[DNS测试] 使用DNS服务器 $dnsServer 解析 ${node.server}');
        // 注意：Dart的标准库不直接支持指定DNS服务器
        // 这里我们仍然使用系统DNS，但可以作为不同的测试路径
        targetHost = node.server;
      }

      final socket = await Socket.connect(
        targetHost,
        node.port,
        timeout: Duration(milliseconds: timeout),
      );

      stopwatch.stop();
      socket.destroy();

      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      stopwatch.stop();
      throw Exception('连接失败: $e');
    }
  }

  /// 直接IP连接测试
  Future<int> _testDirectIpConnection(VPNConfig node) async {
    final stopwatch = Stopwatch()..start();

    try {
      final socket = await Socket.connect(
        node.server, // 直接使用IP地址
        node.port,
        timeout: Duration(milliseconds: timeout),
      );

      stopwatch.stop();
      socket.destroy();

      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      stopwatch.stop();
      throw Exception('直接IP连接失败: $e');
    }
  }
}

/// 信号量实现
class _Semaphore {
  final int maxConcurrency;
  int _currentCount = 0;
  final _waitingTasks = <Completer<void>>[];

  _Semaphore(this.maxConcurrency);

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_currentCount < maxConcurrency) {
      _currentCount++;
      return;
    }

    final completer = Completer<void>();
    _waitingTasks.add(completer);
    await completer.future;
  }

  void _release() {
    _currentCount--;
    if (_waitingTasks.isNotEmpty) {
      final completer = _waitingTasks.removeAt(0);
      _currentCount++;
      completer.complete();
    }
  }
}

/// 物理网卡信息（用于 route add 选择 ifIndex 和默认网关）
class _IfInfo {
  final int interfaceIndex;
  final String gateway;
  _IfInfo({required this.interfaceIndex, required this.gateway});
}
