import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// 改进的流量统计服务
/// 参考sing-box-for-android的设计，提供更准确和稳定的流量统计
class ImprovedTrafficStatsService {
  static const Duration _updateInterval = Duration(seconds: 1);
  static const Duration _clashApiTimeout = Duration(seconds: 2);
  static const int _maxSpeedHistory = 10;
  static const double _speedSmoothingFactor = 0.3;

  // 单例
  static final ImprovedTrafficStatsService _instance = ImprovedTrafficStatsService._internal();
  factory ImprovedTrafficStatsService() => _instance;
  ImprovedTrafficStatsService._internal();

  // 状态管理
  Timer? _updateTimer;
  bool _isRunning = false;

  // Clash API配置
  int _clashApiPort = 9090;
  String _clashApiSecret = '';
  bool _isClashApiEnabled = false;

  // 流量数据
  final TrafficData _currentData = TrafficData();
  final List<TrafficSnapshot> _speedHistory = [];

  // 回调
  Function(TrafficData)? onTrafficUpdate;

  // Getters
  bool get isRunning => _isRunning;
  TrafficData get currentData => _currentData;

  /// 启动流量统计
  void start({
    int clashApiPort = 9090,
    String clashApiSecret = '',
    bool enableClashApi = true,
  }) {
    if (_isRunning) return;

    _clashApiPort = clashApiPort;
    _clashApiSecret = clashApiSecret;
    _isClashApiEnabled = enableClashApi;
    _isRunning = true;

    // 初始化数据
    _currentData.reset();
    _speedHistory.clear();

    // 启动定时更新
    _updateTimer = Timer.periodic(_updateInterval, (timer) {
      _updateTrafficStats();
    });
  }

  /// 停止流量统计
  void stop() {
    _isRunning = false;
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  /// 重置统计数据
  void reset() {
    _currentData.reset();
    _speedHistory.clear();
  }

  /// 主要更新流程
  Future<void> _updateTrafficStats() async {
    if (!_isRunning) return;

    TrafficSnapshot? newSnapshot;

    // 优先尝试Clash API
    if (_isClashApiEnabled) {
      newSnapshot = await _getTrafficFromClashApi();
    }

    // 备用方案：系统级统计
    newSnapshot ??= await _getTrafficFromSystem();

    if (newSnapshot != null) {
      _processTrafficSnapshot(newSnapshot);
    }
  }

  /// 从Clash API获取流量数据
  Future<TrafficSnapshot?> _getTrafficFromClashApi() async {
    try {
      final url = 'http://127.0.0.1:$_clashApiPort/traffic';
      final headers = <String, String>{'Content-Type': 'application/json'};

      if (_clashApiSecret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_clashApiSecret';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(_clashApiTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return TrafficSnapshot(
          timestamp: DateTime.now(),
          totalUpload: (data['up'] as num?)?.toInt() ?? 0,
          totalDownload: (data['down'] as num?)?.toInt() ?? 0,
          source: TrafficSource.clashApi,
        );
      }
    } catch (e) {
      // Clash API不可用，将使用备用方案
    }
    return null;
  }

  /// 从系统获取流量数据（备用方案）
  Future<TrafficSnapshot?> _getTrafficFromSystem() async {
    try {
      // Windows平台使用netstat统计
      if (Platform.isWindows) {
        return await _getWindowsNetworkStats();
      }
    } catch (e) {
      // 系统统计失败
    }
    return null;
  }

  /// 获取Windows网络统计
  Future<TrafficSnapshot?> _getWindowsNetworkStats() async {
    try {
      // 使用更简单可靠的PowerShell命令
      final result = await Process.run('powershell', [
        '-Command',
        r'Get-Counter -Counter "\Network Interface(*)\Bytes Received/sec", "\Network Interface(*)\Bytes Sent/sec" -SampleInterval 1 -MaxSamples 1 | ForEach-Object {$_.CounterSamples | Where-Object {$_.InstanceName -ne "_Total" -and $_.InstanceName -notmatch "Loopback"} | Measure-Object -Property CookedValue -Sum | Select-Object Sum}'
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final sumMatch = RegExp(r'Sum\s*:\s*(\d+)').firstMatch(output);

        if (sumMatch != null) {
          final totalBytes = int.tryParse(sumMatch.group(1) ?? '0') ?? 0;

          // 简化版：假设上传下载各占一半（这只是备用方案）
          return TrafficSnapshot(
            timestamp: DateTime.now(),
            totalUpload: totalBytes ~/ 2,
            totalDownload: totalBytes ~/ 2,
            source: TrafficSource.system,
          );
        }
      }
    } catch (e) {
      // PowerShell方案失败，尝试使用netstat
      return await _getWindowsNetstatStats();
    }
    return null;
  }

  /// 使用netstat获取Windows网络统计（备用方案）
  Future<TrafficSnapshot?> _getWindowsNetstatStats() async {
    try {
      final result = await Process.run('netstat', ['-e']);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');

        // 查找包含字节数的行
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.contains('Bytes') && i + 1 < lines.length) {
            final dataLine = lines[i + 1].trim();
            final parts = dataLine.split(RegExp(r'\s+'));

            if (parts.length >= 2) {
              final received = int.tryParse(parts[0]) ?? 0;
              final sent = int.tryParse(parts[1]) ?? 0;

              return TrafficSnapshot(
                timestamp: DateTime.now(),
                totalUpload: sent,
                totalDownload: received,
                source: TrafficSource.system,
              );
            }
            break;
          }
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }

  /// 处理流量快照
  void _processTrafficSnapshot(TrafficSnapshot snapshot) {
    final now = DateTime.now();

    // 第一次记录，直接保存
    if (_currentData.lastSnapshot == null) {
      _currentData.lastSnapshot = snapshot;
      return;
    }

    final lastSnapshot = _currentData.lastSnapshot!;
    final timeDiff = snapshot.timestamp.difference(lastSnapshot.timestamp);

    // 时间间隔太短，跳过
    if (timeDiff.inMilliseconds < 500) return;

    // 计算增量
    final uploadDelta = snapshot.totalUpload - lastSnapshot.totalUpload;
    final downloadDelta = snapshot.totalDownload - lastSnapshot.totalDownload;

    // 处理数据回退或重置的情况
    if (uploadDelta < 0 || downloadDelta < 0) {
      // 数据发生了重置，重新开始统计
      _currentData.reset();
      _currentData.lastSnapshot = snapshot;
      _speedHistory.clear();
      return;
    }

    // 更新累计流量
    _currentData.totalUploadBytes += uploadDelta;
    _currentData.totalDownloadBytes += downloadDelta;

    // 计算瞬时速度 (bytes/second)
    final instantUploadSpeed = (uploadDelta * 1000) / timeDiff.inMilliseconds;
    final instantDownloadSpeed = (downloadDelta * 1000) / timeDiff.inMilliseconds;

    // 应用速度平滑算法
    _currentData.uploadSpeed = _smoothSpeed(
      _currentData.uploadSpeed.toDouble(),
      instantUploadSpeed,
    ).round();
    _currentData.downloadSpeed = _smoothSpeed(
      _currentData.downloadSpeed.toDouble(),
      instantDownloadSpeed,
    ).round();

    // 更新历史记录
    _speedHistory.add(TrafficSnapshot(
      timestamp: now,
      totalUpload: snapshot.totalUpload,
      totalDownload: snapshot.totalDownload,
      uploadSpeed: _currentData.uploadSpeed,
      downloadSpeed: _currentData.downloadSpeed,
      source: snapshot.source,
    ));

    // 限制历史记录长度
    while (_speedHistory.length > _maxSpeedHistory) {
      _speedHistory.removeAt(0);
    }

    // 更新最后快照
    _currentData.lastSnapshot = snapshot;

    // 通知更新
    onTrafficUpdate?.call(_currentData);
  }

  /// 速度平滑算法
  double _smoothSpeed(double currentSpeed, double newSpeed) {
    // 使用指数移动平均进行平滑
    return currentSpeed * (1 - _speedSmoothingFactor) + newSpeed * _speedSmoothingFactor;
  }

  /// 格式化字节数
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 格式化速度
  static String formatSpeed(int bytesPerSecond) {
    return '${formatBytes(bytesPerSecond)}/s';
  }

  /// 获取平均速度
  int getAverageUploadSpeed() {
    if (_speedHistory.length < 2) return 0;
    final recent = _speedHistory.skip(math.max(0, _speedHistory.length - 5));
    final sum = recent.fold<int>(0, (sum, snapshot) => sum + snapshot.uploadSpeed);
    return (sum / recent.length).round();
  }

  int getAverageDownloadSpeed() {
    if (_speedHistory.length < 2) return 0;
    final recent = _speedHistory.skip(math.max(0, _speedHistory.length - 5));
    final sum = recent.fold<int>(0, (sum, snapshot) => sum + snapshot.downloadSpeed);
    return (sum / recent.length).round();
  }
}

/// 流量数据
class TrafficData {
  int totalUploadBytes = 0;
  int totalDownloadBytes = 0;
  int uploadSpeed = 0; // bytes/second
  int downloadSpeed = 0; // bytes/second
  TrafficSnapshot? lastSnapshot;

  int get totalBytes => totalUploadBytes + totalDownloadBytes;

  void reset() {
    totalUploadBytes = 0;
    totalDownloadBytes = 0;
    uploadSpeed = 0;
    downloadSpeed = 0;
    lastSnapshot = null;
  }
}

/// 流量快照
class TrafficSnapshot {
  final DateTime timestamp;
  final int totalUpload;
  final int totalDownload;
  final int uploadSpeed;
  final int downloadSpeed;
  final TrafficSource source;

  TrafficSnapshot({
    required this.timestamp,
    required this.totalUpload,
    required this.totalDownload,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    required this.source,
  });
}

/// 流量数据源
enum TrafficSource {
  clashApi,
  system,
  networkInterface,
}