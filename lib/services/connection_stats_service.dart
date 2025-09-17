import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// 真实连接统计服务
class ConnectionStatsService {
  static const Duration _timeout = Duration(seconds: 3);
  static int _clashFailCount = 0;
  static DateTime? _clashNextProbeAt;
  static const int _clashFailThreshold = 2; // 超过2次失败则进入冷却
  static const Duration _clashCooldown = Duration(seconds: 30);
  static DateTime? _lastNetstatLogAt;
  static const Duration _netstatLogInterval = Duration(seconds: 15);

  /// 快速探测 127.0.0.1:port 是否在监听
  static Future<bool> _isLocalPortOpen(int port) async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(milliseconds: 250),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 获取连接统计信息
  static Future<ConnectionStats?> getConnectionStats({
    int clashApiPort = 9090,
    String clashApiSecret = '',
  }) async {
    try {
      // 仅在端口可用且未处于冷却期时尝试 Clash API
      final now = DateTime.now();
      final inCooldown =
          _clashNextProbeAt != null && now.isBefore(_clashNextProbeAt!);
      List<ConnectionInfo>? connections;
      if (!inCooldown && await _isLocalPortOpen(clashApiPort)) {
        connections = await _getClashConnections(
          port: clashApiPort,
          secret: clashApiSecret,
        );
      }
      if (connections != null) {
        // 成功则清零失败与冷却
        _clashFailCount = 0;
        _clashNextProbeAt = null;
        return ConnectionStats(
          connections: connections,
          source: ConnectionSource.clashAPI,
        );
      }

      // 如果 Clash API 不可用，尝试其他方法
      final systemStats = await _getSystemConnections();
      return ConnectionStats(
        connections: systemStats,
        source: ConnectionSource.system,
      );
    } catch (e) {
      print('获取连接统计失败: $e');
      return null;
    }
  }

  /// 通过 Clash API 获取连接信息
  static Future<List<ConnectionInfo>?> _getClashConnections({
    required int port,
    required String secret,
  }) async {
    try {
      final url = 'http://127.0.0.1:$port/connections';
      final uri = Uri.parse(url);

      // 创建请求头
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (secret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $secret';
      }

      final response = await http.get(uri, headers: headers).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final connectionsData = data['connections'] as List?;

        // 添加调试信息
        // print(
        //   'Clash API 响应: 状态码=${response.statusCode}, 数据长度=${response.body.length}',
        // );
        // print('连接数组长度: ${connectionsData?.length ?? 0}');

        if (connectionsData != null && connectionsData.isNotEmpty) {
          // print('第一个连接数据示例: ${connectionsData.first}');
          final connections = connectionsData
              .map((conn) => ConnectionInfo.fromClashAPI(conn))
              .toList();
          // print('成功解析 ${connections.length} 个连接');
          return connections;
        } else {
          print('Clash API 返回空连接列表，将尝试系统连接获取');
          return null; // 返回 null 以触发 fallback
        }
      } else {
        // 降噪：只在少量失败内输出一次，随后进入冷却
        if (_clashFailCount < _clashFailThreshold) {
          print('Clash API 请求失败: 状态码=${response.statusCode}');
        }
        _clashFailCount++;
        if (_clashFailCount == _clashFailThreshold) {
          _clashNextProbeAt = DateTime.now().add(_clashCooldown);
        }
      }
    } catch (e) {
      // Clash API 不可用：降噪 + 冷却
      if (_clashFailCount < _clashFailThreshold) {
        print('Clash API 连接失败: $e');
      }
      _clashFailCount++;
      if (_clashFailCount == _clashFailThreshold) {
        _clashNextProbeAt = DateTime.now().add(_clashCooldown);
      }
      return null;
    }
    return null;
  }

  /// 通过系统命令获取连接信息（备用方案）
  static Future<List<ConnectionInfo>> _getSystemConnections() async {
    final connections = <ConnectionInfo>[];

    try {
      if (Platform.isWindows) {
        final now = DateTime.now();
        final shouldLog =
            _lastNetstatLogAt == null ||
            now.difference(_lastNetstatLogAt!) >= _netstatLogInterval;
        if (shouldLog) {
          print('使用 netstat 获取系统连接信息...');
        }

        // 获取进程列表（用于PID到进程名的映射）
        final processMap = await _getProcessMap();

        // 使用 netstat 获取 Windows 连接信息，只获取 TCP 连接
        final result = await Process.run('netstat', [
          '-ano',
        ], runInShell: true);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          if (shouldLog) {
            print('netstat 返回 ${lines.length} 行数据');
            _lastNetstatLogAt = now;
          }

          for (final line in lines) {
            final conn = _parseWindowsNetstatLine(line, processMap);
            if (conn != null) {
              connections.add(conn);
            }
          }
          // print('成功解析 $parsedCount 个系统连接');
        } else {
          print('netstat 命令执行失败: ${result.stderr}');
        }
      }
    } catch (e) {
      print('获取系统连接信息失败: $e');
    }

    return connections;
  }

  /// 获取进程ID到进程名的映射
  static Future<Map<int, String>> _getProcessMap() async {
    final processMap = <int, String>{};

    try {
      final result = await Process.run('tasklist', [
        '/FO',
        'CSV',
      ], runInShell: true);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (int i = 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isNotEmpty) {
            final parts = line.split(',');
            if (parts.length >= 2) {
              final processName = parts[0].replaceAll('"', '');
              final pidStr = parts[1].replaceAll('"', '');
              final pid = int.tryParse(pidStr);
              if (pid != null) {
                processMap[pid] = processName;
              }
            }
          }
        }
      }
    } catch (e) {
      print('获取进程列表失败: $e');
    }

    return processMap;
  }

  /// 解析 Windows netstat 输出行
  static ConnectionInfo? _parseWindowsNetstatLine(
    String line,
    Map<int, String> processMap,
  ) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return null;

    try {
      final protocol = parts[0];
      final localAddress = parts[1];
      final remoteAddress = parts[2];
      final state = parts.length > 3 ? parts[3] : '';
      final pid = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;

      // 只处理已建立的 TCP 连接
      if (protocol.toUpperCase() != 'TCP' || state != 'ESTABLISHED')
        return null;

      // 过滤回环地址和特殊地址
      if (remoteAddress.startsWith('127.0.0.1') ||
          remoteAddress.startsWith('0.0.0.0') ||
          remoteAddress.startsWith('::1') ||
          remoteAddress.startsWith('192.168.') ||
          remoteAddress.startsWith('10.') ||
          remoteAddress.contains('0.0.0.0')) {
        return null;
      }

      // 过滤掉明显的系统内部端口，但保留常见的 Web 服务端口
      final remotePort = remoteAddress.split(':').last;
      final port = int.tryParse(remotePort) ?? 0;

      // 保留常见端口：80(HTTP), 443(HTTPS), 8080-8999(Web服务), 等
      final isCommonWebPort =
          port >= 80 &&
          port <= 65535 &&
          (port == 80 ||
              port == 443 ||
              (port >= 8000 && port <= 9999) ||
              (port >= 3000 && port <= 3999) ||
              (port >= 5000 && port <= 5999));

      if (!isCommonWebPort) {
        return null;
      }

      // 获取进程名称
      String processName = processMap[pid] ?? 'PID:$pid';

      return ConnectionInfo(
        id: '${localAddress}_${remoteAddress}',
        host: remoteAddress,
        localAddress: localAddress,
        protocol: protocol.toLowerCase(),
        state: state,
        pid: pid,
        process: processName,
        uploadBytes: 0, // netstat 不提供流量信息，但会在更新时模拟
        downloadBytes: 0,
        duration: Duration.zero, // 将在更新时计算
        rule: 'SYSTEM',
        target: '直连',
        startTime: DateTime.now(), // 记录连接发现时间作为开始时间
        domain: null,  // netstat 不提供域名信息
        proxyProtocol: null,  // netstat 不提供代理协议
        chains: null,
      );
    } catch (e) {
      return null;
    }
  }

  /// 获取进程名称
  static Future<String> getProcessName(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist', [
          '/FI',
          'PID eq $pid',
          '/FO',
          'CSV',
          '/NH',
        ], runInShell: true);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().trim().split('\n');
          if (lines.isNotEmpty) {
            final parts = lines[0].split(',');
            if (parts.isNotEmpty) {
              return parts[0].replaceAll('"', '');
            }
          }
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return 'Unknown';
  }
}

/// 连接统计数据
class ConnectionStats {
  final List<ConnectionInfo> connections;
  final ConnectionSource source;
  final DateTime timestamp;

  ConnectionStats({required this.connections, required this.source})
    : timestamp = DateTime.now();
}

/// 连接信息来源
enum ConnectionSource {
  clashAPI, // 从 Clash API 获取
  system, // 从系统命令获取
}

/// 单个连接信息
class ConnectionInfo {
  final String id;
  final String host;
  final String localAddress;
  final String protocol;
  final String state;
  final int pid;
  final String process;
  final int uploadBytes;
  final int downloadBytes;
  final int uploadSpeed;
  final int downloadSpeed;
  final Duration duration;
  final String rule;
  final String target;
  final DateTime startTime;
  final String? domain;  // 域名（如果有的话）
  final String? proxyProtocol;  // 代理协议（如 Shadowsocks, VMess, Trojan 等）
  final List<String>? chains;  // 完整的代理链

  ConnectionInfo({
    required this.id,
    required this.host,
    required this.localAddress,
    required this.protocol,
    this.state = '',
    this.pid = 0,
    this.process = '',
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.duration = Duration.zero,
    this.rule = '',
    this.target = '',
    DateTime? startTime,
    this.domain,
    this.proxyProtocol,
    this.chains,
  }) : startTime = startTime ?? DateTime.now();

  /// 从 Clash API 数据创建连接信息
  factory ConnectionInfo.fromClashAPI(Map<String, dynamic> data) {
    final metadata = data['metadata'] ?? {};
    final id = data['id'] ?? '';
    final upload = (data['upload'] as num?)?.toInt() ?? 0;
    final download = (data['download'] as num?)?.toInt() ?? 0;
    final startTime = data['start'] != null
        ? DateTime.tryParse(data['start']) ?? DateTime.now()
        : DateTime.now();

    // 获取域名和IP
    final domain = metadata['host']?.toString();
    final destinationIP = metadata['destinationIP']?.toString() ?? 'unknown';
    final destinationPort = metadata['destinationPort']?.toString() ?? '';

    // 优先使用IP，如果没有IP则使用域名
    final hostDisplay = destinationIP != 'unknown' ? destinationIP : (domain ?? 'unknown');

    // 解析代理链
    final chains = (data['chains'] as List?)?.cast<String>() ?? [];

    // 推测代理协议（从代理链中提取）
    String? proxyProtocol;
    if (chains.isNotEmpty) {
      final proxyName = chains.firstWhere(
        (chain) => chain != 'DIRECT' && chain != 'REJECT',
        orElse: () => '',
      );
      // 尝试从代理名称中提取协议类型
      // 例如："vmess-us-01" -> "VMess", "trojan-hk" -> "Trojan"
      if (proxyName.isNotEmpty) {
        final lowerName = proxyName.toLowerCase();
        if (lowerName.contains('vmess')) {
          proxyProtocol = 'VMess';
        } else if (lowerName.contains('vless')) {
          proxyProtocol = 'VLESS';
        } else if (lowerName.contains('trojan')) {
          proxyProtocol = 'Trojan';
        } else if (lowerName.contains('shadowsocks') || lowerName.contains('ss')) {
          proxyProtocol = 'Shadowsocks';
        } else if (lowerName.contains('ssr')) {
          proxyProtocol = 'ShadowsocksR';
        } else if (lowerName.contains('hysteria')) {
          proxyProtocol = 'Hysteria';
        } else if (lowerName.contains('tuic')) {
          proxyProtocol = 'TUIC';
        } else if (lowerName.contains('wireguard') || lowerName.contains('wg')) {
          proxyProtocol = 'WireGuard';
        } else if (lowerName.contains('http')) {
          proxyProtocol = 'HTTP';
        } else if (lowerName.contains('socks')) {
          proxyProtocol = 'SOCKS';
        }
      }
    }

    return ConnectionInfo(
      id: id,
      host: '$hostDisplay:$destinationPort',
      localAddress:
          '${metadata['sourceIP'] ?? '127.0.0.1'}:${metadata['sourcePort'] ?? ''}',
      protocol: metadata['network'] ?? 'tcp',
      state: 'ESTABLISHED',
      pid: 0,
      process: metadata['processPath'] ?? metadata['process'] ?? 'Unknown',
      uploadBytes: upload,
      downloadBytes: download,
      uploadSpeed: 0, // Clash API 不直接提供速度
      downloadSpeed: 0,
      duration: DateTime.now().difference(startTime),
      rule: data['rule'] ?? 'DIRECT',
      target: chains.isNotEmpty ? chains.last : 'DIRECT',
      startTime: startTime,
      domain: domain,
      proxyProtocol: proxyProtocol,
      chains: chains,
    );
  }

  /// 转换为显示用的 Map
  Map<String, dynamic> toDisplayMap() {
    // 解析主机和端口
    String hostAddr = host;
    String hostPort = '';
    if (host.contains(':')) {
      final parts = host.split(':');
      hostAddr = parts[0];
      hostPort = parts.length > 1 ? parts[1] : '';
    }

    // 解析本地地址和端口
    String localAddr = localAddress;
    String localPort = '';
    if (localAddress.contains(':')) {
      final parts = localAddress.split(':');
      localAddr = parts[0];
      localPort = parts.length > 1 ? parts[1] : '';
    }

    // 获取进程名称（只显示文件名，不显示路径）
    String displayProcess = process;
    if (process.contains('\\')) {
      displayProcess = process.split('\\').last;
    } else if (process.contains('/')) {
      displayProcess = process.split('/').last;
    }
    if (displayProcess.isEmpty) {
      displayProcess = 'PID:$pid';
    }

    return {
      'id': id,
      'host': host,
      'hostAddr': hostAddr,
      'hostPort': hostPort,
      'localPort': localAddress,
      'localAddr': localAddr,
      'localPortOnly': localPort,
      'process': displayProcess,
      'processFullPath': process,
      'pid': pid,
      'protocol': protocol.toUpperCase(),
      'state': state,
      'uploadBytes': uploadBytes,
      'downloadBytes': downloadBytes,
      'uploadSpeed': uploadSpeed,
      'downloadSpeed': downloadSpeed,
      'rule': rule,
      'target': target,
      'duration': duration,
      'startTime': startTime,
      'totalBytes': uploadBytes + downloadBytes,
      'domain': domain,
      'proxyProtocol': proxyProtocol,
      'chains': chains,
    };
  }
}

/// 连接统计扩展方法
extension ConnectionStatsExtension on List<ConnectionInfo> {
  /// 获取总上传字节数
  int get totalUploadBytes => fold(0, (sum, conn) => sum + conn.uploadBytes);

  /// 获取总下载字节数
  int get totalDownloadBytes =>
      fold(0, (sum, conn) => sum + conn.downloadBytes);

  /// 获取总上传速度
  int get totalUploadSpeed => fold(0, (sum, conn) => sum + conn.uploadSpeed);

  /// 获取总下载速度
  int get totalDownloadSpeed =>
      fold(0, (sum, conn) => sum + conn.downloadSpeed);

  /// 按规则分组
  Map<String, List<ConnectionInfo>> groupByRule() {
    final groups = <String, List<ConnectionInfo>>{};
    for (final conn in this) {
      groups.putIfAbsent(conn.rule, () => []).add(conn);
    }
    return groups;
  }

  /// 按目标分组
  Map<String, List<ConnectionInfo>> groupByTarget() {
    final groups = <String, List<ConnectionInfo>>{};
    for (final conn in this) {
      groups.putIfAbsent(conn.target, () => []).add(conn);
    }
    return groups;
  }
}
