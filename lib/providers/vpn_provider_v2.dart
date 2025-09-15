import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../models/vpn_config.dart';
import '../models/proxy_mode.dart';
import '../services/config_manager.dart';
import '../services/connection_manager.dart';
import '../services/improved_traffic_stats_service.dart';
import '../services/ping_service.dart';
import '../utils/privilege_manager.dart';

/// 精简版VPN Provider
/// 职责明确：仅作为UI和服务之间的桥梁
class VPNProviderV2 extends ChangeNotifier {
  // 服务实例
  final ConfigManager _configManager = ConfigManager();
  final ConnectionManager _connectionManager = ConnectionManager();
  final ImprovedTrafficStatsService _trafficService =
      ImprovedTrafficStatsService();

  // Ping服务
  final Map<String, int> _configPings = {};
  Timer? _pingTimer;
  bool _isPingingAll = false;
  int _pingIntervalMinutes = 10;
  bool _autoSelectBestServer = false;

  // 连接时长定时器
  Timer? _durationUpdateTimer;

  // 构造函数
  VPNProviderV2() {
    _init();
  }

  // 初始化
  Future<void> _init() async {
    await _configManager.loadConfigs();
    await _connectionManager.init();
    await _loadPreferences();

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
  int get pingIntervalMinutes => _pingIntervalMinutes;

  // 其他属性
  int get activeConnections => 0; // 暂时返回0，后续可以从ConnectionManager获取实际值

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
    final success = await _connectionManager.connect(config);

    if (success) {
      print('[DEBUG] VPN连接成功，不再测试延时');

      // 启动自动选择最佳服务器（但不立即测试）
      if (_autoSelectBestServer) {
        _startPingTimer();
      }

      // 启动连接时长更新定时器
      _startDurationUpdateTimer();
    }

    notifyListeners();
    return success;
  }

  Future<bool> disconnect() async {
    _stopPingTimer();
    _stopDurationUpdateTimer();
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
    _connectionManager.setProxyMode(mode);
    await _savePreference('proxy_mode', mode.name);
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

    if (enabled && isConnected) {
      _startPingTimer();
    } else {
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

    // 只有在启用自动选择最佳服务器时才启动定时器
    if (!_autoSelectBestServer) {
      print('[DEBUG] 自动选择最佳服务器功能未启用，不启动延时测试定时器');
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

  Future<void> _pingAllConfigs() async {
    if (_isPingingAll) return;

    _isPingingAll = true;
    notifyListeners();

    for (final config in configs) {
      try {
        final delay = await PingService.pingConfig(
          config,
          isConnected: isConnected,
          currentConfig: currentConfig,
        );
        _configPings[config.id] = delay;
      } catch (e) {
        _configPings[config.id] = -1;
      }
    }

    // 自动选择最佳服务器（仅在启用自动选择功能时）
    if (_autoSelectBestServer && isConnected) {
      print('[DEBUG] 自动选择最佳服务器功能已启用，开始选择最佳服务器');
      _selectBestServer();
    } else if (isConnected) {
      print('[DEBUG] 自动选择最佳服务器功能未启用，跳过切换');
    }

    _isPingingAll = false;
    notifyListeners();
  }

  void _selectBestServer() {
    if (!_autoSelectBestServer) {
      print('[DEBUG] 自动选择最佳服务器功能未启用，取消选择');
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
      print('延时结果: ${config.name} -> ${delay}ms');
      _configPings[config.id] = delay;
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

  // 获取连接源（使用字符串类型避免导入冲突）
  String get connectionSource => 'Clash API';

  // 获取连接列表（暂时返回空列表）
  List<Map<String, dynamic>> get connections => [];

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

  // ============== 私有方法 ==============

  /// 应用启动时测试当前选中配置的延时
  Future<void> _testAllConfigsOnStartup() async {
    // 延迟执行，避免影响UI初始化
    await Future.delayed(Duration(milliseconds: 500));

    // 获取当前选中的配置
    final current = currentConfig ?? configs.firstOrNull;
    if (current == null) return;

    print('[DEBUG] 开始测试当前配置的延时: ${current.name}');

    // 测试当前配置的延时
    PingService.pingConfig(current, isConnected: false, currentConfig: null)
        .then((delay) {
          // 保存延时结果
          _configPings[current.id] = delay;
          print('[DEBUG] 延时数据已保存: ${current.id} -> ${delay}ms');
          print('[DEBUG] 当前所有延时数据: $_configPings');

          if (delay > 0) {
            print('[DEBUG] 启动延时测试完成: ${current.name} -> ${delay}ms');
            print('[DEBUG] 准备更新UI显示延时');
          } else {
            print('[DEBUG] 启动延时测试失败: ${current.name}');
          }

          // 强制UI更新
          notifyListeners();
          print('[DEBUG] UI更新通知已发送');

          // 验证数据是否正确保存
          final savedPing = getConfigPing(current.id);
          print('[DEBUG] 验证保存的延时: ${savedPing}ms');

          // 额外的UI刷新
          Future.delayed(Duration(milliseconds: 100), () {
            notifyListeners();
            print('[DEBUG] 延迟UI更新通知已发送');
          });
        })
        .catchError((error) {
          print('[DEBUG] 启动延时测试异常: ${current.name} -> $error');
          _configPings[current.id] = -1;
          notifyListeners();
        });
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
    _trafficService.stop();
    super.dispose();
  }
}
