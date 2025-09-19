import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../models/vpn_config.dart';
import '../models/proxy_mode.dart';
import '../services/config_manager.dart';
import '../services/connection_manager.dart';
import '../services/dns_manager.dart';
import '../services/improved_traffic_stats_service.dart';
import '../services/ping_service.dart';
import '../services/connection_stats_service.dart';
import '../services/singbox_native_service.dart';
import '../utils/privilege_manager.dart';

/// 精简版VPN Provider
/// 职责明确：仅作为UI和服务之间的桥梁
class VPNProviderV2 extends ChangeNotifier {
  // 服务实例
  final ConfigManager _configManager = ConfigManager();
  final ConnectionManager _connectionManager = ConnectionManager();
  final ImprovedTrafficStatsService _trafficService =
      ImprovedTrafficStatsService();
  final SingBoxNativeService _singboxService = SingBoxNativeService();

  // Ping服务
  final Map<String, int> _configPings = {};
  Timer? _pingTimer;
  bool _isPingingAll = false;
  int _pingIntervalMinutes = 10;
  bool _autoSelectBestServer = false;
  bool _autoRefreshEnabled = true; // 自动刷新开关，默认开启

  // 连接时长定时器
  Timer? _durationUpdateTimer;

  // 连接信息相关
  List<ConnectionInfo> _connectionInfos = [];
  Timer? _connectionUpdateTimer;
  ConnectionSource _connectionSource = ConnectionSource.clashAPI;

  // 构造函数
  VPNProviderV2() {
    _init();
  }

  // 初始化
  Future<void> _init() async {
    await _configManager.loadConfigs();
    await _connectionManager.init();
    await _loadPreferences();

    // 初始化 sing-box 服务并启动基础代理用于延时测试
    await _initBasicProxy();

    // 初始化 PingService 配置
    PingService.setApiConfig(
      host: '127.0.0.1',
      port: clashApiPort,
      secret: '', // 初始化时暂不设置secret
    );

    // 监听流量更新
    _trafficService.onTrafficUpdate = (data) {
      notifyListeners();
    };

    notifyListeners();

    // 应用启动时自动测试所有配置的延时（未连接状态）
    _testAllConfigsOnStartup();
  }

  /// 初始化基础代理用于延时测试
  Future<void> _initBasicProxy() async {
    try {
      print('🚀 初始化 sing-box 服务...');
      // 仅初始化 sing-box FFI，不启动任何配置
      // 延时测试时会动态创建临时配置
      await _singboxService.initialize();
      print('✅ sing-box 服务初始化完成');
    } catch (e) {
      print('❌ 初始化 sing-box 服务失败: $e');
    }
  }

  /// 获取 sing-box 服务实例（供延时测试使用）
  SingBoxNativeService get singboxService => _singboxService;

  // ============== Getters ==============

  // 配置相关
  List<VPNConfig> get configs => _configManager.configs;
  // 当前配置：已连接时来自 ConnectionManager，未连接时回退到 ConfigManager
  VPNConfig? get currentConfig =>
      _connectionManager.currentConfig ?? _configManager.currentConfig;

  // 连接状态
  bool get isConnected => _connectionManager.isConnected;
  bool get isConnecting => _connectionManager.isConnecting;
  bool get isDisconnecting => _connectionManager.isDisconnecting;
  bool get isBusy => isConnecting || isDisconnecting;
  String get status => _connectionManager.statusMessage;
  List<String> get logs => _connectionManager.logs;

  // 连接设置
  ProxyMode get proxyMode => _connectionManager.proxyMode;
  bool get useTun => _connectionManager.useTun;
  bool get tunStrictRoute => _connectionManager.tunStrictRoute;
  int get localPort => _connectionManager.localPort;
  bool get autoSystemProxy => _connectionManager.autoSystemProxy;
  bool get enableClashApi => _connectionManager.enableClashApi;
  int get clashApiPort => _connectionManager.clashApiPort;
  String get clashApiSecret => _connectionManager.clashApiSecret;

  // 流量统计
  int get uploadBytes => _trafficService.currentData.totalUploadBytes;
  int get downloadBytes => _trafficService.currentData.totalDownloadBytes;
  int get uploadSpeed => _trafficService.currentData.uploadSpeed;
  int get downloadSpeed => _trafficService.currentData.downloadSpeed;
  Duration get connectionDuration => _trafficService.connectionDuration;
  int get totalBytes => uploadBytes + downloadBytes;

  // 平均速度
  int get averageUploadSpeed => connectionDuration.inSeconds > 0
      ? (uploadBytes / connectionDuration.inSeconds).round()
      : 0;
  int get averageDownloadSpeed => connectionDuration.inSeconds > 0
      ? (downloadBytes / connectionDuration.inSeconds).round()
      : 0;

  // Ping相关
  Map<String, int> get configPings => _configPings;
  bool get isPingingAll => _isPingingAll;
  bool get autoSelectBestServer => _autoSelectBestServer;
  bool get autoRefreshEnabled => _autoRefreshEnabled;
  int get pingIntervalMinutes => _pingIntervalMinutes;

  // 其他属性
  int get activeConnections => _connectionInfos.length; // 返回实际的连接数

  // 系统代理相关
  bool get isSystemProxySupported => true; // Windows 平台支持系统代理
  bool get isSystemProxyEnabled => autoSystemProxy;
  String get systemProxyServer => '127.0.0.1:$localPort';

  // TUN可用性
  TunAvailability get tunAvailability {
    return PrivilegeManager.instance.checkTunAvailability();
  }

  // ============== 配置管理 ==============

  Future<void> loadConfigs() async {
    await _configManager.loadConfigs();
    notifyListeners();
  }

  Future<void> addConfig(VPNConfig config) async {
    await _configManager.addConfig(config);
    notifyListeners();
  }

  Future<void> deleteConfig(int index) async {
    await _configManager.deleteConfig(index);
    notifyListeners();
  }

  Future<void> deleteAllConfigs() async {
    await _configManager.deleteAllConfigs();
    notifyListeners();
  }

  Future<void> updateConfig(int index, VPNConfig config) async {
    await _configManager.updateConfig(index, config);
    notifyListeners();
  }

  Future<bool> importFromLink(String link) async {
    final success = await _configManager.importFromLink(link);
    if (success) {
      notifyListeners();
    }
    return success;
  }

  Future<int> importFromSubscription(String content) async {
    final count = await _configManager.importFromSubscription(content);
    if (count > 0) {
      notifyListeners();
    }
    return count;
  }

  // 设置当前配置（不连接）
  Future<void> setCurrentConfig(VPNConfig config) async {
    _configManager.setCurrentConfig(config);
    await _savePreference('current_config_id', config.id);
    notifyListeners();

    // 未连接状态下，切换配置时自动测试新配置的延时
    if (!isConnected) {
      print('[DEBUG] 切换配置，测试新配置延时: ${config.name}');
      PingService.pingConfig(config, isConnected: false, currentConfig: null)
          .then((delay) {
            _configPings[config.id] = delay;
            notifyListeners();
            if (delay > 0) {
              print('[DEBUG] 配置延时测试完成: ${config.name} -> ${delay}ms');
            }
          })
          .catchError((error) {
            print('[DEBUG] 配置延时测试失败: ${config.name}');
            _configPings[config.id] = -1;
            notifyListeners();
          });
    }
  }

  // ============== 连接管理 ==============

  Future<bool> connect(VPNConfig config) async {
    print("[DEBUG] 尝试连接VPN: ${config.name}");
    final success = await _connectionManager.connect(config);

    if (success) {
      print('[DEBUG] VPN连接成功，不再测试延时');

      // 启动自动选择最佳服务器（但不立即测试）
      // if (_autoSelectBestServer) {
      //   _startPingTimer();
      // }

      _startPingTimer();

      // 启动连接时长更新定时器
      _startDurationUpdateTimer();

      // 启动连接信息更新定时器
      _startConnectionUpdateTimer();
    }

    notifyListeners();
    return success;
  }

  Future<bool> disconnect() async {
    _stopPingTimer();
    _stopDurationUpdateTimer();
    _stopConnectionUpdateTimer();
    final success = await _connectionManager.disconnect();
    notifyListeners();
    return success;
  }

  Future<void> toggleConnection(VPNConfig config) async {
    if (isConnected && currentConfig?.id == config.id) {
      await disconnect();
    } else {
      if (isConnected) {
        await disconnect();
      }
      await connect(config);
    }
  }

  // ============== 设置管理 ==============

  Future<void> setProxyMode(ProxyMode mode) async {
    final prev = _connectionManager.proxyMode;
    _connectionManager.setProxyMode(mode);
    await _savePreference('proxy_mode', mode.name);

    // 若已经连接则重载配置以应用新的路由模式
    if (isConnected && prev != mode) {
      try {
        final ok = await _connectionManager.reloadCurrentConfig();
        if (!ok) {
          print('[WARN] 代理模式切换后重载失败，模式=${mode.name}');
        } else {
          print('[INFO] 代理模式切换已生效: ${mode.name}');
        }
      } catch (e) {
        print('[ERROR] 切换代理模式重载异常: $e');
      }
    }

    notifyListeners();
  }

  Future<void> setUseTun(bool enabled) async {
    if (enabled) {
      // 开启 TUN 时互斥关闭系统代理
      if (_connectionManager.autoSystemProxy) {
        await _connectionManager.disableSystemProxy();
        _connectionManager.setAutoSystemProxy(false);
        await _savePreference('auto_system_proxy', false);
      }
      _connectionManager.setUseTun(true);
      await _savePreference('use_tun', true);
    } else {
      // 关闭 TUN 时自动开启系统代理（若之前未开启）
      _connectionManager.setUseTun(false);
      await _savePreference('use_tun', false);
      if (!_connectionManager.autoSystemProxy) {
        _connectionManager.setAutoSystemProxy(true);
        await _savePreference('auto_system_proxy', true);
        // 若已连接则立即启用系统代理
        if (_connectionManager.isConnected) {
          await _connectionManager.enableSystemProxy();
        }
      }
    }
    notifyListeners();
  }

  Future<void> setTunStrictRoute(bool enabled) async {
    _connectionManager.setTunStrictRoute(enabled);
    await _savePreference('tun_strict_route', enabled);
    notifyListeners();
  }

  Future<void> setLocalPort(int port) async {
    _connectionManager.setLocalPort(port);
    await _savePreference('local_port', port);
    notifyListeners();
  }

  Future<void> setAutoSystemProxy(bool enabled) async {
    // 开启系统代理时互斥关闭 TUN
    if (enabled && _connectionManager.useTun) {
      _connectionManager.setUseTun(false);
      await _savePreference('use_tun', false);
    }
    if (!enabled) {
      // 主动关闭系统代理（清理）
      await _connectionManager.disableSystemProxy();
    }
    _connectionManager.setAutoSystemProxy(enabled);
    await _savePreference('auto_system_proxy', enabled);
    notifyListeners();
  }

  Future<void> setClashApi(bool enabled, int port, String secret) async {
    _connectionManager.setClashApi(enabled, port, secret);

    // 更新 PingService 配置
    PingService.setApiConfig(host: '127.0.0.1', port: port, secret: secret);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_clash_api', enabled);
    await prefs.setInt('clash_api_port', port);
    await prefs.setString('clash_api_secret', secret);
    notifyListeners();
  }

  Future<void> setAutoSelectBestServer(bool enabled) async {
    _autoSelectBestServer = enabled;
    await _savePreference('auto_select_best_server', enabled);

    if (enabled && isConnected && _autoRefreshEnabled) {
      _startPingTimer();
    } else {
      _stopPingTimer();
    }

    notifyListeners();
  }

  Future<void> setAutoRefreshEnabled(bool enabled) async {
    _autoRefreshEnabled = enabled;
    await _savePreference('auto_refresh_enabled', enabled);

    if (enabled && _autoSelectBestServer && isConnected) {
      _startPingTimer();
    } else if (!enabled) {
      _stopPingTimer();
    }

    notifyListeners();
  }

  Future<void> setPingIntervalMinutes(int minutes) async {
    _pingIntervalMinutes = minutes;
    await _savePreference('ping_interval_minutes', minutes);

    if (_autoSelectBestServer && isConnected) {
      _stopPingTimer();
      _startPingTimer();
    }

    notifyListeners();
  }

  // ============== Ping管理 ==============

  void _startPingTimer() {
    _stopPingTimer();

    // 只有在启用自动选择最佳服务器且启用自动刷新时才启动定时器
    if (!_autoSelectBestServer) {
      print('[DEBUG] 自动选择最佳服务器功能未启用，不启动延时测试定时器');
      return;
    }

    if (!_autoRefreshEnabled) {
      print('[DEBUG] 自动刷新功能未启用，不启动延时测试定时器');
      return;
    }

    print('[DEBUG] 启动延时测试定时器，间隔: ${_pingIntervalMinutes}分钟');
    // 连接后不立即测试，使用现有的延时数据
    // 仅设置定期测试定时器用于自动选择最佳服务器
    _pingTimer = Timer.periodic(Duration(minutes: _pingIntervalMinutes), (
      timer,
    ) {
      print('[DEBUG] 定时器触发：开始测试所有配置延时');
      _pingAllConfigs();
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // ============== 连接时长更新 ==============

  void _startDurationUpdateTimer() {
    _stopDurationUpdateTimer();

    // 每秒更新一次，独立于流量统计
    _durationUpdateTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      // 仅通知监听器，不做其他操作
      // 连接时长由 ImprovedTrafficStatsService 内部计算
      notifyListeners();
    });
  }

  void _stopDurationUpdateTimer() {
    _durationUpdateTimer?.cancel();
    _durationUpdateTimer = null;
  }

  // 启动连接信息更新定时器
  void _startConnectionUpdateTimer() {
    _stopConnectionUpdateTimer();

    // 立即获取一次连接信息
    _updateConnectionInfo();

    // 每2秒更新一次连接信息
    _connectionUpdateTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      _updateConnectionInfo();
    });
  }

  // 停止连接信息更新定时器
  void _stopConnectionUpdateTimer() {
    _connectionUpdateTimer?.cancel();
    _connectionUpdateTimer = null;
    _connectionInfos.clear();
    notifyListeners();
  }

  // 更新连接信息
  Future<void> _updateConnectionInfo() async {
    if (!isConnected) {
      _connectionInfos.clear();
      notifyListeners();
      return;
    }

    try {
      final stats = await ConnectionStatsService.getConnectionStats(
        clashApiPort: clashApiPort,
        clashApiSecret: clashApiSecret,
      );

      if (stats != null) {
        _connectionInfos = stats.connections;
        _connectionSource = stats.source;
        notifyListeners();
      }
    } catch (e) {
      print('更新连接信息失败: $e');
    }
  }

  Future<void> _pingAllConfigs() async {
    if (_isPingingAll) return;

    _isPingingAll = true;
    notifyListeners();

    try {
      // 实时更新：每个节点完成即刻刷新对应延时
      await PingService.pingConfigsWithProgress(
        configs,
        concurrency: null,
        isConnected: isConnected,
        currentConfig: currentConfig,
        onEach: (cfg, ping) {
          final sanitized = _sanitizeLatency(cfg, ping);

          _configPings[cfg.id] = sanitized;

          notifyListeners();
        },
        onProgress: (done, total) {
          // 可选：可在此处记录进度供日后使用，目前保持静默
        },
      );
      // 兜底：全部完成后再次通知一次，确保UI一致
      notifyListeners();

      // 自动选择最佳服务器（仅在启用自动选择功能且启用自动刷新时）
      if (_autoSelectBestServer && _autoRefreshEnabled && isConnected) {
        print('[DEBUG] 自动选择最佳服务器功能已启用且自动刷新已开启，开始选择最佳服务器');
        _selectBestServer();
      } else if (isConnected) {
        if (!_autoSelectBestServer) {
          print('[DEBUG] 自动选择最佳服务器功能未启用，跳过切换');
        } else if (!_autoRefreshEnabled) {
          print('[DEBUG] 自动刷新功能未启用，跳过切换');
        }
      }
    } finally {
      _isPingingAll = false;
      notifyListeners();
    }
  }

  void _selectBestServer() {
    if (!_autoSelectBestServer) {
      print('[DEBUG] 自动选择最佳服务器功能未启用，取消选择');
      return;
    }

    if (!_autoRefreshEnabled) {
      print('[DEBUG] 自动刷新功能未启用，不切换节点');
      return;
    }

    VPNConfig? bestConfig;
    int bestPing = 999999;

    print('[DEBUG] 开始自动选择最佳服务器...');
    for (final config in configs) {
      final ping = _configPings[config.id] ?? 999999;
      print('[DEBUG] 服务器 ${config.name}: ${ping}ms');
      if (ping > 0 && ping < bestPing) {
        bestPing = ping;
        bestConfig = config;
      }
    }

    final currentPing = _configPings[currentConfig?.id ?? ''] ?? 999999;
    print('[DEBUG] 当前服务器 ${currentConfig?.name}: ${currentPing}ms');
    print('[DEBUG] 最佳服务器 ${bestConfig?.name}: ${bestPing}ms');

    // 如果找到更好的服务器且不是当前服务器，切换
    if (bestConfig != null &&
        bestConfig.id != currentConfig?.id &&
        bestPing < currentPing - 50) {
      // 延迟差超过50ms才切换
      print(
        '[DEBUG] 发现更好的服务器，延迟差：${currentPing - bestPing}ms，开始切换到 ${bestConfig.name}',
      );
      connect(bestConfig);
    } else {
      print('[DEBUG] 未发现明显更好的服务器（延迟差需>50ms），保持当前服务器');
    }
  }

  Future<void> pingConfig(VPNConfig config) async {
    try {
      print('测试延时: ${config.name}, 连接状态: $isConnected');
      final delay = await PingService.pingConfig(
        config,

        isConnected: isConnected,

        currentConfig: currentConfig,
      );

      final sanitized = _sanitizeLatency(config, delay);

      print('测试延时: ${config.name} -> ${sanitized}ms');

      _configPings[config.id] = sanitized;
    } catch (e) {
      print('延时测试失败: ${config.name}, 错误: $e');
      _configPings[config.id] = -1;
    }
    notifyListeners();
  }

  // 获取配置的延时
  int getConfigPing(String configId) {
    return _configPings[configId] ?? -1;
  }

  // 获取配置的延时文本
  String getConfigPingText(String configId) {
    final ping = getConfigPing(configId);
    return PingService.formatPing(ping);
  }

  // 获取配置的延时等级
  PingLevel getConfigPingLevel(String configId) {
    final ping = getConfigPing(configId);
    return PingService.getPingLevel(ping);
  }

  // ============== 其他功能 ==============

  void clearLogs() {
    _connectionManager.clearLogs();
    notifyListeners();
  }

  // ============== 登录链接便捷入口（Tailscale 优先） ==============

  /// 从现有日志中提取 Tailscale 登录链接（若存在）
  String? extractTailscaleLoginUrlFromLogs() {
    // 常见提示样式："Please visit https://login.tailscale.com/a/XXXX... to authenticate"
    final regex = RegExp(
      r'https?://[^\s]+tailscale[^\s]*',
      caseSensitive: false,
    );
    for (final line in logs.reversed) {
      final m = regex.firstMatch(line);
      if (m != null) {
        final url = m.group(0);
        if (url != null && url.contains('tailscale')) return url;
      }
    }
    return null;
  }

  /// 在未连接状态下，运行一次“最小 endpoints”探测以触发登录链接输出（仅当 endpoints 已配置且需要授权）
  /// 返回捕获到的登录 URL；若未获得则返回 null。
  Future<String?> probeLoginUrlOnce({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (isConnected || _connectionManager.isConnecting) return null; // 仅在未连接时执行

    // 生成一个极简配置，注入 endpoints（如 Tailscale），不启用 TUN，仅 basic inbounds/outbounds
    try {
      final current = currentConfig ?? configs.firstOrNull;
      if (current == null) return null;

      final cfg = await current.toSingBoxConfig(
        mode: _connectionManager.proxyMode,
        localPort: _connectionManager.localPort,
        useTun: false,
        tunStrictRoute: false,
        preferredTunStack: _connectionManager.useTun
            ? _singboxService.preferredTunStack
            : null,
        enableClashApi: false,
        clashApiPort: _connectionManager.clashApiPort,
        clashApiSecret: _connectionManager.clashApiSecret,
        enableIpv6: false,
      );

      // 若没有 endpoints 则无需探测
      final endpoints =
          (cfg['endpoints'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (endpoints.isEmpty) return null;

      // 暂存原日志回调并注入捕获
      final captured = <String>[];
      void capture(String s) => captured.add(s);
      final originalOnLog = _singboxService.onLog;
      _singboxService.onLog = (line) {
        capture(line);
        originalOnLog?.call(line);
      };

      // 启动并等待片刻产生日志
      final started = await _singboxService.start(cfg);
      if (!started) {
        _singboxService.onLog = originalOnLog; // 还原
        return null;
      }

      // 等待或提前捕获到链接
      final end = DateTime.now().add(timeout);
      String? url;
      final regex = RegExp(
        r'https?://[^\s]+tailscale[^\s]*',
        caseSensitive: false,
      );
      while (DateTime.now().isBefore(end)) {
        for (final line in List<String>.from(captured).reversed) {
          final m = regex.firstMatch(line);
          if (m != null) {
            url = m.group(0);
            break;
          }
        }
        if (url != null) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // 停止一次性探测实例
      await _singboxService.stop();
      _singboxService.onLog = originalOnLog; // 还原
      return url;
    } catch (_) {
      return null;
    }
  }

  /// UI 触发的统一流程：优先从日志提取；否则在未连接状态尝试一次探测；成功则返回URL
  Future<String?> showLoginLinkFlow() async {
    final fromLogs = extractTailscaleLoginUrlFromLogs();
    if (fromLogs != null) return fromLogs;
    final probed = await probeLoginUrlOnce();
    return probed;
  }

  // ============== 最小连通性检查（快速健康探测） ==============
  /// 返回检查结果文本：
  /// - 系统DNS解析（gstatic.com）
  /// - 本地端口占用情况（mixed-in 端口）
  /// - 路由模式/是否连接的简报
  Future<String> quickHealthCheck() async {
    final buf = StringBuffer();
    buf.writeln('快速健康探测');
    buf.writeln('- 连接状态: ${isConnected ? '已连接' : '未连接'}');
    buf.writeln('- 代理模式: ${proxyMode.name}');
    buf.writeln('- TUN: ${useTun ? '开启' : '关闭'}');
    // DNS 解析
    try {
      final res = await DnsManager().testDomainResolution('gstatic.com');
      if (res.success) {
        buf.writeln(
          '- DNS 解析: 正常 (${res.duration?.inMilliseconds ?? 0}ms) → ${res.resolvedAddresses.firstOrNull ?? ''}',
        );
      } else {
        buf.writeln('- DNS 解析: 失败 ${res.error ?? ''}');
      }
    } catch (e) {
      buf.writeln('- DNS 解析: 异常 $e');
    }
    // 端口检查（简单尝试绑定同端口判断占用）
    try {
      final s = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        localPort,
      );
      await s.close();
      buf.writeln('- 本地端口 ${localPort}: 可用');
    } catch (_) {
      buf.writeln('- 本地端口 ${localPort}: 已占用');
    }
    // Clash API 简报
    buf.writeln(
      '- Clash API: ${enableClashApi ? '启用' : '未启用'} @ 127.0.0.1:$clashApiPort',
    );
    return buf.toString();
  }

  // 刷新所有配置的ping
  Future<void> refreshAllPings() async {
    await _pingAllConfigs();
  }

  // 刷新单个配置的ping
  Future<void> refreshConfigPing(VPNConfig config) async {
    await pingConfig(config);
  }

  // 同步DNS管理器的设置
  void syncStrictRouteFromDnsManager() {
    // 从DNS管理器同步严格路由设置
    notifyListeners();
  }

  void syncLocalPortFromDnsManager() {
    // 从DNS管理器同步本地端口设置
    notifyListeners();
  }

  // DNS 设置更改后的通用通知入口，供 UI 调用，避免直接调用受保护的 notifyListeners
  void onDnsSettingsChanged() {
    notifyListeners();
  }

  // 获取连接源（使用字符串类型避免导入冲突）
  String get connectionSource {
    switch (_connectionSource) {
      case ConnectionSource.clashAPI:
        return 'Clash API';
      case ConnectionSource.system:
        return '系统';
    }
  }

  // 获取连接列表
  List<Map<String, dynamic>> get connections {
    return _connectionInfos.map((info) => info.toDisplayMap()).toList();
  }

  Future<void> resetPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _loadPreferences();
    notifyListeners();
  }

  Future<bool> requestElevation({String? reason}) async {
    return await PrivilegeManager.instance.requestElevation(
      reason: reason ?? '启用 TUN 模式需要管理员权限',
    );
  }

  static const int _suspiciousLatencyThresholdMs = 5;

  int _sanitizeLatency(VPNConfig config, int latency) {
    if (latency < 0) {
      return latency;
    }
    if (latency > _suspiciousLatencyThresholdMs) {
      return latency;
    }
    if (_isLocalOrPrivateHost(config.server)) {
      return latency;
    }

    print(
      '[DEBUG] Latency ${latency}ms looks suspicious for ${config.name}, mark as timeout',
    );
    return -1;
  }

  bool _isLocalOrPrivateHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed.toLowerCase() == 'localhost') {
      return true;
    }

    final parsed = InternetAddress.tryParse(trimmed);
    if (parsed == null) {
      return false;
    }

    if (parsed.isLoopback || parsed.isLinkLocal) {
      return true;
    }

    if (parsed.type == InternetAddressType.IPv4) {
      final parts = parsed.address.split('.').map(int.parse).toList();
      final first = parts[0];
      final second = parts[1];
      if (first == 10) {
        return true;
      }
      if (first == 192 && second == 168) {
        return true;
      }
      if (first == 172 && second >= 16 && second <= 31) {
        return true;
      }
      if (first == 169 && second == 254) {
        return true;
      }
    } else {
      final lower = parsed.address.toLowerCase();
      if (lower.startsWith('fc') || lower.startsWith('fd')) {
        return true;
      }
    }

    return false;
  }

  // ============== 私有方法 ==============

  /// 应用启动时批量测试所有配置的延时
  Future<void> _testAllConfigsOnStartup() async {
    // 延迟执行，避免影响UI初始化，并等待DLL加载完成
    await Future.delayed(Duration(milliseconds: 1500));

    if (configs.isEmpty) {
      print('[DEBUG] 没有配置需要测试延时');
      return;
    }

    print('[DEBUG] 开始批量测试所有配置的延时，共${configs.length}个');

    // 批量测试所有配置的延时
    await _pingAllConfigs();

    print('[DEBUG] 启动时批量延时测试完成');
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    _connectionManager.setProxyMode(
      ProxyMode.fromString(prefs.getString('proxy_mode') ?? 'rule'),
    );
    _connectionManager.setUseTun(prefs.getBool('use_tun') ?? false);
    _connectionManager.setTunStrictRoute(
      prefs.getBool('tun_strict_route') ?? false,
    );
    _connectionManager.setLocalPort(prefs.getInt('local_port') ?? 7890);
    _connectionManager.setAutoSystemProxy(
      prefs.getBool('auto_system_proxy') ?? false,
    );
    _connectionManager.setClashApi(
      prefs.getBool('enable_clash_api') ?? true,
      prefs.getInt('clash_api_port') ?? 9090,
      prefs.getString('clash_api_secret') ?? '',
    );

    _autoSelectBestServer = prefs.getBool('auto_select_best_server') ?? false;
    _autoRefreshEnabled = prefs.getBool('auto_refresh_enabled') ?? true;
    _pingIntervalMinutes = prefs.getInt('ping_interval_minutes') ?? 10;

    // 加载已保存的当前配置
    final currentConfigId = prefs.getString('current_config_id');
    if (currentConfigId != null) {
      final savedConfig = configs
          .where((c) => c.id == currentConfigId)
          .firstOrNull;
      if (savedConfig != null) {
        _configManager.setCurrentConfig(savedConfig);
      }
    }
  }

  Future<void> _savePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  void dispose() {
    _stopPingTimer();
    _stopDurationUpdateTimer();
    _stopConnectionUpdateTimer();
    _trafficService.stop();
    super.dispose();
  }
}
