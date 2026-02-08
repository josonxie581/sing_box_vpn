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
  static const double _speedSmoothingFactor = 0.12; // 一级指数平滑系数 (EMA1)
  static const double _secondarySmoothingFactor = 0.25; // 二级指数平滑 (EMA2)，响应略快
  static const int _slidingWindow = 6; // 最近N次用于窗口平均
  static const int _minVisualStep = 100; // 最小可见变动 (bytes/s) 防止数值抖动
  static const double _decayFactorWhenIdle = 0.7; // 空闲时衰减系数
  static const int _minUpdateInterval = 500; // 最小更新间隔（毫秒）
  static const double _speedChangeThreshold = 1024; // 速度变化阈值（1KB/s）
  static const int _nearZeroThreshold = 100; // 小于该值视为0 (bytes/s)

  // 单例
  static final ImprovedTrafficStatsService _instance =
      ImprovedTrafficStatsService._internal();
  factory ImprovedTrafficStatsService() => _instance;
  ImprovedTrafficStatsService._internal();

  // 状态管理
  Timer? _updateTimer;
  bool _isRunning = false;

  // Clash API配置
  int _clashApiPort = 9090;
  String _clashApiSecret = '';
  bool _isClashApiEnabled = false;

  // WebSocket 连接
  WebSocket? _trafficWebSocket;
  StreamSubscription? _trafficStreamSubscription;

  // 更新控制
  DateTime? _lastUpdateTime;
  int _lastNotifiedUploadSpeed = 0;
  int _lastNotifiedDownloadSpeed = 0;
  int _idleZeroTicks = 0; // 连续原始零速计数
  static const int _idleZeroThreshold = 2; // 连续多少次零速后强制归零

  // WebSocket 活性检测
  DateTime? _lastWebSocketDataTime; // 上次收到 WebSocket 数据的时间
  static const int _webSocketStaleSeconds = 10; // 超过此秒数无数据视为断连
  int _reconnectAttempts = 0; // 重连尝试次数
  static const int _maxReconnectDelay = 30; // 最大重连延迟(秒)

  // 流量数据
  final TrafficData _currentData = TrafficData();
  double _ema1Up = 0;
  double _ema1Down = 0;
  double _ema2Up = 0;
  double _ema2Down = 0;
  final List<int> _recentUp = [];
  final List<int> _recentDown = [];
  final List<TrafficSnapshot> _speedHistory = [];

  // 回调
  Function(TrafficData)? onTrafficUpdate;

  // 连接统计
  DateTime? _connectionStartTime;
  Duration _connectionDuration = Duration.zero;
  Timer? _durationTimer;

  // Getters
  bool get isRunning => _isRunning;
  TrafficData get currentData => _currentData;
  DateTime? get connectionStartTime => _connectionStartTime;
  Duration get connectionDuration => _connectionDuration;

  /// 启动流量统计
  void start({
    int clashApiPort = 9090,
    String clashApiSecret = '',
    bool enableClashApi = true,
  }) {
    if (_isRunning) {
      // 服务已在运行
      return;
    }

    // 启动流量统计服务
    _clashApiPort = clashApiPort;
    _clashApiSecret = clashApiSecret;
    _isClashApiEnabled = enableClashApi;
    _isRunning = true;

    // 初始化数据
    _currentData.reset();
    _speedHistory.clear();
    _ema1Up = 0;
    _ema1Down = 0;
    _ema2Up = 0;
    _ema2Down = 0;
    _recentUp.clear();
    _recentDown.clear();
    _connectionStartTime = DateTime.now();
    _connectionDuration = Duration.zero;

    // 重置重连计数
    _reconnectAttempts = 0;
    _lastWebSocketDataTime = null;

    // 尝试连接 WebSocket
    if (_isClashApiEnabled) {
      _connectWebSocket();
    }

    // 启动定时更新（兼顾 WebSocket 活性检测和 HTTP 轮询兜底）
    _updateTimer = Timer.periodic(_updateInterval, (timer) {
      if (_trafficWebSocket != null) {
        // WebSocket 已连接：检查是否还活着
        _checkWebSocketHealth();
      } else {
        // WebSocket 未连接：使用 HTTP 轮询兜底
        _updateTrafficStats();
      }
    });

    // 启动连接时长更新
    _durationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_connectionStartTime != null) {
        _connectionDuration = DateTime.now().difference(_connectionStartTime!);
      }
    });
  }

  /// 停止流量统计
  void stop() {
    _isRunning = false;
    _updateTimer?.cancel();
    _updateTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectionStartTime = null;
    _connectionDuration = Duration.zero;
    _reconnectAttempts = 0;
    _lastWebSocketDataTime = null;
    _disconnectWebSocket();
  }

  /// 检查 WebSocket 活性，如果长时间无数据则视为断连
  void _checkWebSocketHealth() {
    if (_lastWebSocketDataTime == null) return;
    final elapsed = DateTime.now().difference(_lastWebSocketDataTime!).inSeconds;
    if (elapsed >= _webSocketStaleSeconds) {
      print('[TrafficStats] WebSocket 已 ${elapsed}s 无数据，视为断连，重新连接');
      _disconnectWebSocket();
      _scheduleReconnect();
    }
  }

  /// 带退避的重连调度
  void _scheduleReconnect() {
    if (!_isRunning || !_isClashApiEnabled) return;
    // 指数退避：2, 4, 8, 16, 30(上限) 秒
    final delay = math.min(
      2 * math.pow(2, _reconnectAttempts).toInt(),
      _maxReconnectDelay,
    );
    _reconnectAttempts++;
    print('[TrafficStats] 将在 ${delay}s 后尝试第 $_reconnectAttempts 次重连');
    Future.delayed(Duration(seconds: delay), () {
      if (_isRunning && _isClashApiEnabled) {
        _connectWebSocket();
      }
    });
  }

  /// 连接 WebSocket
  Future<void> _connectWebSocket() async {
    if (_trafficWebSocket != null) return;

    final url = 'ws://127.0.0.1:$_clashApiPort/traffic';
    final headers = <String, String>{};

    if (_clashApiSecret.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_clashApiSecret';
    }

    try {
      // 连接 Clash WebSocket
      _trafficWebSocket = await WebSocket.connect(url, headers: headers);
      _reconnectAttempts = 0; // 连接成功，重置重连计数
      _lastWebSocketDataTime = DateTime.now();

      _trafficStreamSubscription = _trafficWebSocket!.listen(
        (data) {
          _handleWebSocketData(data);
        },
        onError: (error) {
          print('[TrafficStats] WebSocket 错误: $error');
          _disconnectWebSocket();
          _scheduleReconnect();
        },
        onDone: () {
          print('[TrafficStats] WebSocket 连接关闭');
          _disconnectWebSocket();
          _scheduleReconnect();
        },
      );

      print('[TrafficStats] WebSocket 连接成功');
    } catch (e) {
      print('[TrafficStats] WebSocket 连接失败: $e');
      _disconnectWebSocket();
      _scheduleReconnect(); // 连接失败也要重试
    }
  }

  /// 断开 WebSocket
  void _disconnectWebSocket() {
    _trafficStreamSubscription?.cancel();
    _trafficStreamSubscription = null;
    _trafficWebSocket?.close();
    _trafficWebSocket = null;
  }

  /// 处理 WebSocket 数据
  void _handleWebSocketData(dynamic data) {
    try {
      _lastWebSocketDataTime = DateTime.now(); // 更新活性时间戳

      final Map<String, dynamic> json = jsonDecode(data);
      final int newUploadSpeed =
          (json['up'] as num?)?.toInt() ?? 0; // 原始瞬时速度 (bytes/s)
      final int newDownloadSpeed =
          (json['down'] as num?)?.toInt() ?? 0; // 原始瞬时速度 (bytes/s)

      // 近零(噪声)归零处理前的原始值用于累计；用于平滑的值先做近零剪裁
      final int clippedUpload = newUploadSpeed < _nearZeroThreshold
          ? 0
          : newUploadSpeed;
      final int clippedDownload = newDownloadSpeed < _nearZeroThreshold
          ? 0
          : newDownloadSpeed;

      final bool rawIdle =
          newUploadSpeed < _nearZeroThreshold &&
          newDownloadSpeed < _nearZeroThreshold;
      if (rawIdle) {
        _idleZeroTicks++;
      } else {
        _idleZeroTicks = 0;
      }

      // 应用平滑算法（基于剪裁后的值）
      final smoothed = _applyMultiStageSmoothing(
        clippedUpload,
        clippedDownload,
      );
      final smoothedUploadSpeed = smoothed.$1;
      final smoothedDownloadSpeed = smoothed.$2;

      // 空闲强制归零（避免残留值挂住）
      int finalUpload = smoothedUploadSpeed;
      int finalDownload = smoothedDownloadSpeed;
      // 近零再剪裁一次（平滑后的小值直接归零）
      if (finalUpload < _nearZeroThreshold) finalUpload = 0;
      if (finalDownload < _nearZeroThreshold) finalDownload = 0;
      if (_idleZeroTicks >= _idleZeroThreshold) {
        finalUpload = 0;
        finalDownload = 0;
        _ema1Up = 0;
        _ema1Down = 0;
        _ema2Up = 0;
        _ema2Down = 0;
        _recentUp.clear();
        _recentDown.clear();
      }

      // 更新内部数据
      _currentData.uploadSpeed = finalUpload;
      _currentData.downloadSpeed = finalDownload;

      // 累计流量
      _currentData.totalUploadBytes += newUploadSpeed;
      _currentData.totalDownloadBytes += newDownloadSpeed;

      // 检查是否需要通知更新
      final now = DateTime.now();
      final shouldUpdate = _shouldNotifyUpdate(now, finalUpload, finalDownload);

      if (shouldUpdate) {
        _lastUpdateTime = now;
        _lastNotifiedUploadSpeed = finalUpload;
        _lastNotifiedDownloadSpeed = finalDownload;

        // 减少日志输出频率
        // if (smoothedUploadSpeed > 1024 || smoothedDownloadSpeed > 1024) {
        //   print('流量更新 - 上传: ${formatSpeed(smoothedUploadSpeed)}, 下载: ${formatSpeed(smoothedDownloadSpeed)}');
        // }

        onTrafficUpdate?.call(_currentData);
      }
    } catch (e) {
      // 解析 WebSocket 数据失败
    }
  }

  /// 判断是否应该通知更新
  bool _shouldNotifyUpdate(DateTime now, int uploadSpeed, int downloadSpeed) {
    // 首次更新
    if (_lastUpdateTime == null) {
      return true;
    }

    // 检查时间间隔
    final timeDiff = now.difference(_lastUpdateTime!).inMilliseconds;
    if (timeDiff < _minUpdateInterval) {
      return false;
    }

    // 检查速度变化是否超过阈值
    final uploadChange = (uploadSpeed - _lastNotifiedUploadSpeed).abs();
    final downloadChange = (downloadSpeed - _lastNotifiedDownloadSpeed).abs();

    // 若从非零进入(近似)零速状态，强制更新一次
    bool _isZero(int v) => v <= _nearZeroThreshold; // 含“近零”视为0
    final becameIdle =
        (_isZero(uploadSpeed) &&
            _lastNotifiedUploadSpeed > _nearZeroThreshold) ||
        (_isZero(downloadSpeed) &&
            _lastNotifiedDownloadSpeed > _nearZeroThreshold);
    if (becameIdle) return true;

    // 如果变化很小且速度很低，不更新（保持平静）
    final veryLow = uploadSpeed < 1024 && downloadSpeed < 1024;
    if (veryLow &&
        uploadChange < _speedChangeThreshold &&
        downloadChange < _speedChangeThreshold) {
      return false;
    }

    // 如果变化超过阈值的10%，更新
    if (_lastNotifiedUploadSpeed > 0) {
      final uploadChangePercent = uploadChange / _lastNotifiedUploadSpeed;
      if (uploadChangePercent > 0.1) return true;
    }

    if (_lastNotifiedDownloadSpeed > 0) {
      final downloadChangePercent = downloadChange / _lastNotifiedDownloadSpeed;
      if (downloadChangePercent > 0.1) return true;
    }

    // 定期更新（每2秒）
    return timeDiff > 2000;
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
    if (newSnapshot == null) {
      newSnapshot = await _getTrafficFromSystem();
    }

    if (newSnapshot != null) {
      _processTrafficSnapshot(newSnapshot);
    } else {
      // 无法获取流量数据
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

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_clashApiTimeout);

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
        r'Get-Counter -Counter "\Network Interface(*)\Bytes Received/sec", "\Network Interface(*)\Bytes Sent/sec" -SampleInterval 1 -MaxSamples 1 | ForEach-Object {$_.CounterSamples | Where-Object {$_.InstanceName -ne "_Total" -and $_.InstanceName -notmatch "Loopback"} | Measure-Object -Property CookedValue -Sum | Select-Object Sum}',
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
    final instantDownloadSpeed =
        (downloadDelta * 1000) / timeDiff.inMilliseconds;

    // 应用速度平滑算法
    final rawUp = instantUploadSpeed.round();
    final rawDown = instantDownloadSpeed.round();
    // 近零处理 & 空闲检测
    final bool rawIdle =
        rawUp < _nearZeroThreshold && rawDown < _nearZeroThreshold;
    if (rawIdle) {
      _idleZeroTicks++;
    } else {
      _idleZeroTicks = 0;
    }
    int clippedUp = rawUp < _nearZeroThreshold ? 0 : rawUp;
    int clippedDown = rawDown < _nearZeroThreshold ? 0 : rawDown;

    final smoothed = _applyMultiStageSmoothing(clippedUp, clippedDown);
    int finalUp = smoothed.$1;
    int finalDown = smoothed.$2;
    if (finalUp < _nearZeroThreshold) finalUp = 0;
    if (finalDown < _nearZeroThreshold) finalDown = 0;
    if (_idleZeroTicks >= _idleZeroThreshold) {
      finalUp = 0;
      finalDown = 0;
      _ema1Up = 0;
      _ema1Down = 0;
      _ema2Up = 0;
      _ema2Down = 0;
      _recentUp.clear();
      _recentDown.clear();
    }
    _currentData.uploadSpeed = finalUp;
    _currentData.downloadSpeed = finalDown;

    // 更新历史记录
    _speedHistory.add(
      TrafficSnapshot(
        timestamp: now,
        totalUpload: snapshot.totalUpload,
        totalDownload: snapshot.totalDownload,
        uploadSpeed: _currentData.uploadSpeed,
        downloadSpeed: _currentData.downloadSpeed,
        source: snapshot.source,
      ),
    );

    // 限制历史记录长度
    while (_speedHistory.length > _maxSpeedHistory) {
      _speedHistory.removeAt(0);
    }

    // 更新最后快照
    _currentData.lastSnapshot = snapshot;

    // 通知更新
    // 发送流量更新
    onTrafficUpdate?.call(_currentData);
  }

  /// 速度平滑算法
  /// 复合平滑：EMA1 -> EMA2 -> 滑动窗口 -> 阶梯最小变化
  (int, int) _applyMultiStageSmoothing(int rawUp, int rawDown) {
    // 1. 一级EMA
    _ema1Up =
        _ema1Up * (1 - _speedSmoothingFactor) + rawUp * _speedSmoothingFactor;
    _ema1Down =
        _ema1Down * (1 - _speedSmoothingFactor) +
        rawDown * _speedSmoothingFactor;

    // 2. 二级EMA（对一级结果再平滑，使曲线更顺）
    _ema2Up =
        _ema2Up * (1 - _secondarySmoothingFactor) +
        _ema1Up * _secondarySmoothingFactor;
    _ema2Down =
        _ema2Down * (1 - _secondarySmoothingFactor) +
        _ema1Down * _secondarySmoothingFactor;

    // 3. 滑动窗口（加入近期值，进一步消除尖峰）
    _recentUp.add(_ema2Up.round());
    _recentDown.add(_ema2Down.round());
    while (_recentUp.length > _slidingWindow) _recentUp.removeAt(0);
    while (_recentDown.length > _slidingWindow) _recentDown.removeAt(0);
    final avgUp = _recentUp.isEmpty
        ? 0
        : _recentUp.reduce((a, b) => a + b) / _recentUp.length;
    final avgDown = _recentDown.isEmpty
        ? 0
        : _recentDown.reduce((a, b) => a + b) / _recentDown.length;

    // 4. 空闲衰减：在源数据几乎为0时逐步衰减展示值
    double finalUp = avgUp.toDouble();
    double finalDown = avgDown.toDouble();
    if (rawUp < 200 && finalUp < 1500) {
      finalUp *= _decayFactorWhenIdle;
    }
    if (rawDown < 200 && finalDown < 1500) {
      finalDown *= _decayFactorWhenIdle;
    }

    // 5. 最小视觉阶梯：避免频繁 +/- 很小的抖动
    finalUp = _applyMinStep(_currentData.uploadSpeed.toDouble(), finalUp);
    finalDown = _applyMinStep(_currentData.downloadSpeed.toDouble(), finalDown);

    return (finalUp.round(), finalDown.round());
  }

  double _applyMinStep(double previous, double next) {
    final diff = (next - previous).abs();
    if (diff == 0) return previous;
    if (diff < _minVisualStep) {
      // 采用缓动过渡，避免突然跳动
      return previous + (next - previous) * 0.25;
    }
    return next;
  }

  /// 格式化字节数
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 格式化速度
  static String formatSpeed(int bytesPerSecond) {
    return '${formatBytes(bytesPerSecond)}/s';
  }

  /// 格式化时长
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// 获取平均速度
  int getAverageUploadSpeed() {
    if (_speedHistory.length < 2) return 0;
    final recent = _speedHistory.skip(math.max(0, _speedHistory.length - 5));
    final sum = recent.fold<int>(
      0,
      (sum, snapshot) => sum + snapshot.uploadSpeed,
    );
    return (sum / recent.length).round();
  }

  int getAverageDownloadSpeed() {
    if (_speedHistory.length < 2) return 0;
    final recent = _speedHistory.skip(math.max(0, _speedHistory.length - 5));
    final sum = recent.fold<int>(
      0,
      (sum, snapshot) => sum + snapshot.downloadSpeed,
    );
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
enum TrafficSource { clashApi, system, networkInterface }
