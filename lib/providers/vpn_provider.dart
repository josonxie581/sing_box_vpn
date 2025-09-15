import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
// import 'dart:math'; // 已移除随机模拟逻辑
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as ffi_alloc;
import 'package:win32/win32.dart' as win32;

import '../models/vpn_config.dart';
import '../models/proxy_mode.dart';
import '../services/singbox_native_service.dart';
import '../services/windows_proxy_manager.dart';
import '../services/dns_manager.dart';
import '../services/daemon_client.dart';
import '../services/pac_file_manager.dart';
import '../services/ping_service.dart';
import '../services/connection_stats_service.dart';
import '../services/improved_traffic_stats_service.dart';
import '../utils/privilege_manager.dart';

/// 速度样本结构（用于速度平滑）
class _SpeedSample {
  final int up;
  final int down;
  final int dtMs; // 时间间隔 ms
  final DateTime time;
  _SpeedSample(this.up, this.down, this.dtMs, this.time);
}

/// VPN 状态管理
class VPNProvider extends ChangeNotifier {
  // ============== VPN Provider State ==============
  late final dynamic _singBoxService;
  List<VPNConfig> _configs = [];
  VPNConfig? _currentConfig;
  bool _isConnected = false;
  // 细粒度阶段标记：用于驱动动画（避免通过 status 文本模糊判断）
  bool _isConnecting = false; // 连接发起到成功/失败期间
  bool _isDisconnecting = false; // 断开发起到完成期间
  String _status = '未连接';
  List<String> _logs = [];
  // 日志降噪：系统代理模式下
  bool _suppressNoisyLogs = true;
  // ====== Notification Debounce: Reduce rebuild frequency ======
  Timer? _notifyDebounce;
  static const int _notifyIntervalMs = 250; // 聚合窗口 250ms
  bool _pendingNotify = false;
  void _scheduleNotify({bool immediate = false}) {
    if (immediate) {
      _notifyDebounce?.cancel();
      _pendingNotify = false;
      notifyListeners();
      return;
    }
    if (_pendingNotify) return;
    _pendingNotify = true;
    _notifyDebounce = Timer(
      const Duration(milliseconds: _notifyIntervalMs),
      () {
        _pendingNotify = false;
        notifyListeners();
      },
    );
  }

  // 模式 / 配置
  bool _autoSystemProxy = false; // 自动切换系统代理（默认关闭）
  bool _usePacFile = false; // 使用 PAC 文件
  ProxyMode _proxyMode = ProxyMode.rule; // 规则/全局
  final WindowsProxyManager _proxyManager = WindowsProxyManager();
  final DnsManager _dnsManager = DnsManager();
  final PacFileManager _pacManager = PacFileManager();

  // 系统代理状态缓存
  bool _systemProxyEnabled = false;
  String _systemProxyServer = '';

  // TUN / 权限
  bool _useTun = false;
  bool _tunStrictRoute = false; // strict_route A/B
  static const int _defaultLocalPort = 7890;
  int _localPort = _defaultLocalPort;
  bool _isWindowsAdmin = true;

  // 守护进程
  final FlashConnectVPNManager _vpnManager = FlashConnectVPNManager();
  bool _useDaemon = false;
  bool _sessionViaDaemon = false;

  // Clash API
  bool _enableClashApi = true;
  int _clashApiPort = 9090;
  String _clashApiSecret = '';

  // 流量统计：上传+当前速度
  int _uploadBytes = 0;
  int _downloadBytes = 0;
  int _uploadSpeed = 0; // bytes/s
  int _downloadSpeed = 0; // bytes/s
  DateTime _lastUpdateTime = DateTime.now();
  Timer? _trafficStatsTimer;

  // 会话级累计流量统计（不会因为重连而重置）
  int _sessionTotalUploadBytes = 0;
  int _sessionTotalDownloadBytes = 0;

  // 改进的流量统计服务
  final ImprovedTrafficStatsService _improvedTrafficService = ImprovedTrafficStatsService();
  bool _useImprovedTrafficStats = true;

  // ============== WebSocket 实时流量（Clash API）==============
  WebSocket? _clashTrafficSocket;
  StreamSubscription? _clashTrafficSub;
  bool _clashStreamActive = false;
  bool _clashTriedStream = false;
  DateTime? _clashLastFrameTime;
  int? _clashLastUp;
  int? _clashLastDown;
  // 数据累计/速度判断字段控制，使用 _clashWsInterpretAsSpeed 自动模式
  // 默认解释为速度。例外（Clash /traffic WebSocket 返回的为实时速度 B/s）
  bool _clashWsInterpretAsSpeed = true; // true=视为速度, false=视为累计或增量字节

  // ============== 速度平滑实现 ==============
  final List<_SpeedSample> _speedSamples = [];
  static const int _speedWindowMs = 1200; // 平滑窗口长度 ~1.2s
  static const int _minFrameIntervalMs = 80; // 小帧合并阈值
  int _pendingSmallFrameUp = 0;
  int _pendingSmallFrameDown = 0;
  int _pendingSmallFrameTime = 0; // 累积的微帧时间 (ms)

  // ============== 实际流量 (TUN) 接口统计 ==============
  // 用户可以选择显示真实的字节流速，使用 Windows Get-NetAdapterStatistics 查询，或通过 Clash API/守护进程。
  // 例如：每秒运行一次 PowerShell，或者通过 win32 FFI 优化性能，获取 ReceivedBytes / SentBytes 并计算流速。
  // 注意：在 Clash WebSocket 模式下，可以选择是否解释为速度（默认），否则使用 Clash API 的 WS 数据 -> 解释为实时速度。
  // 关闭 Clash 或未启用 WS 时，统计可能不完整（useInterfaceCounters=true 时）。
  bool _useInterfaceCounters = false; // 仅当用户需要“真实网卡流量”时开启
  String? _tunInterfaceName; // 连接时探测记录的 TUN 接口名称 (例如 "Wintun Gsou")
  int _ifLastRxBytes = 0; // 上次读取的接口接收字节（绝对值）
  int _ifLastTxBytes = 0; // 上次读取的接口发送字节（绝对值）
  DateTime? _ifLastReadTime; // 上次读取时间
  // 可注入的抓取函数（便于测试）: 返回 (rx, tx) 绝对累计字节；null 表示失败
  Future<(int, int)?> Function()? _interfaceCountersFetcher;

  // 对外暴露启用真实接口统计的方法，供 UI 调用
  void enableRealInterfaceCounters({String? interfaceName}) {
    _useInterfaceCounters = true;
    if (interfaceName != null && interfaceName.trim().isNotEmpty) {
      _tunInterfaceName = interfaceName.trim();
    }
  }

  // 对外暴露禁用真实接口统计的方法
  void disableRealInterfaceCounters() {
    _useInterfaceCounters = false;
  }

  bool get usingRealInterfaceCounters => _useInterfaceCounters;
  String? get tunInterfaceName => _tunInterfaceName;

  @visibleForTesting
  void setInterfaceCountersFetcher(Future<(int, int)?> Function() f) {
    _interfaceCountersFetcher = f;
  }

  @visibleForTesting
  Future<void> debugUpdateFromInterfaceOnce() async {
    await _updateTrafficFromInterface(force: true);
  }

  // ============== 连接统计 ==============
  Map<String, Map<String, dynamic>> _connectionHistory = {};
  DateTime? _connectionStartTime;
  Duration _connectionDuration = Duration.zero;
  int _activeConnections = 0;
  List<Map<String, dynamic>> _connections = [];
  ConnectionSource _connectionSource = ConnectionSource.clashAPI;

  // 延时 / Ping
  Map<String, int> _configPings = {};
  Timer? _pingTimer;
  bool _isPingingAll = false;
  bool _clashApiAutoRetried = false; // 端口探测自动重试标志

  // 状态监控定时器
  Timer? _statusMonitorTimer;

  // 自动选择最佳服务器
  bool _autoSelectBestServer = false;

  // Ping 间隔时间（分钟）
  int _pingIntervalMinutes = 10;

  // 历史流量（用于统计/回归分析/速度计算）
  int _lastUploadBytes = 0;
  int _lastDownloadBytes = 0;
  // 连接统计相关 _connectionHistory/_connectionStartTime/_connectionDuration/_activeConnections 等

  // ================= 速度平滑内部实现 =================
  void _recordSpeedSample(int upDelta, int downDelta, int dtMs) {
    if (dtMs <= 0) return;
    if (dtMs < _minFrameIntervalMs) {
      _pendingSmallFrameUp += upDelta;
      _pendingSmallFrameDown += downDelta;
      _pendingSmallFrameTime += dtMs;
      if (_pendingSmallFrameTime < _minFrameIntervalMs) return;
      upDelta = _pendingSmallFrameUp;
      downDelta = _pendingSmallFrameDown;
      dtMs = _pendingSmallFrameTime;
      _pendingSmallFrameUp = 0;
      _pendingSmallFrameDown = 0;
      _pendingSmallFrameTime = 0;
    }
    final now = DateTime.now();
    _speedSamples.add(_SpeedSample(upDelta, downDelta, dtMs, now));
    final cutoff = now.millisecondsSinceEpoch - _speedWindowMs;
    while (_speedSamples.isNotEmpty &&
        _speedSamples.first.time.millisecondsSinceEpoch < cutoff) {
      _speedSamples.removeAt(0);
    }
    int sumUp = 0, sumDown = 0, sumTime = 0;
    for (final s in _speedSamples) {
      sumUp += s.up;
      sumDown += s.down;
      sumTime += s.dtMs;
    }
    if (sumTime <= 0) return;
    final smoothUp = (sumUp * 1000 / sumTime).round();
    final smoothDown = (sumDown * 1000 / sumTime).round();
    final instantUp = upDelta > 0 ? (upDelta * 1000 / dtMs).round() : 0;
    final instantDown = downDelta > 0 ? (downDelta * 1000 / dtMs).round() : 0;
    int finalUp = instantUp;
    int finalDown = instantDown;
    if (smoothUp > 0 && instantUp > smoothUp * 6)
      finalUp = (smoothUp * 35 ~/ 10); // 3.5x 封顶
    if (smoothDown > 0 && instantDown > smoothDown * 6)
      finalDown = (smoothDown * 35 ~/ 10);
    _uploadSpeed = finalUp;
    _downloadSpeed = finalDown;
  }

  // Getters
  List<VPNConfig> get configs => _configs;
  VPNConfig? get currentConfig => _currentConfig;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isDisconnecting => _isDisconnecting;
  bool get isBusy => _isConnecting || _isDisconnecting;
  String get status => _status;
  List<String> get logs => _logs;
  bool get autoSystemProxy => _autoSystemProxy;
  bool get usePacFile => _usePacFile;
  ProxyMode get proxyMode => _proxyMode;
  bool get useTun => _useTun;
  bool get tunStrictRoute => _tunStrictRoute;
  int get localPort => _localPort;

  /// 同步DNS管理器的端口设置
  void syncLocalPortFromDnsManager() {
    final newPort = _dnsManager.localPort;
    if (_localPort != newPort) {
      _localPort = newPort;
      notifyListeners();
    }
  }

  void syncStrictRouteFromDnsManager() {
    final newStrictRoute = _dnsManager.strictRoute;
    if (_tunStrictRoute != newStrictRoute) {
      _tunStrictRoute = newStrictRoute;
      notifyListeners();
    }
  }
  bool get isWindowsAdmin => _isWindowsAdmin;
  bool get useDaemon => _useDaemon;
  bool get enableClashApi => _enableClashApi;
  int get clashApiPort => _clashApiPort;

  /// 获取 TUN 模式可用性状态
  TunAvailability get tunAvailability {
    if (!Platform.isWindows) {
      return TunAvailability.notSupported;
    }
    return PrivilegeManager.instance.checkTunAvailability();
  }

  /// 请求权限提升（用于 UI 调用）
  Future<bool> requestElevation({String? reason}) async {
    return await PrivilegeManager.instance.requestElevation(
      reason: reason ?? '启用 TUN 模式需要管理员权限',
    );
  }

  // 系统代理状态相关 Getters
  bool get isSystemProxyEnabled => _systemProxyEnabled;
  String get systemProxyServer => _systemProxyServer;
  bool get isSystemProxySupported => _proxyManager.isSupported;

  // 流量统计 Getters - 返回会话级累计流量 + 当前连接流量
  int get uploadBytes => _sessionTotalUploadBytes + _uploadBytes;
  int get downloadBytes => _sessionTotalDownloadBytes + _downloadBytes;
  int get uploadSpeed => _uploadSpeed;
  int get downloadSpeed => _downloadSpeed;
  // 平均速度（会话总字节数 / 时长）
  int get averageUploadSpeed => _connectionDuration.inSeconds > 0
      ? ((uploadBytes) / _connectionDuration.inSeconds).round()
      : 0;
  int get averageDownloadSpeed => _connectionDuration.inSeconds > 0
      ? ((downloadBytes) / _connectionDuration.inSeconds).round()
      : 0;
  int get totalBytes => uploadBytes + downloadBytes;
  Duration get connectionDuration => _connectionDuration;
  int get activeConnections => _activeConnections;
  List<Map<String, dynamic>> get connections => _connections;

  // 流量统计设置 Getters
  bool get useImprovedTrafficStats => _useImprovedTrafficStats;

  // 延时相关 Getters
  Map<String, int> get configPings => _configPings;
  bool get isPingingAll => _isPingingAll;
  bool get autoSelectBestServer => _autoSelectBestServer;
  int get pingIntervalMinutes => _pingIntervalMinutes;

  // 连接统计相关 Getters
  ConnectionSource get connectionSource => _connectionSource;

  VPNProvider() {
    _initService();
  }

  bool _disposed = false; // 供后台异步任务检测，避免已释放后继续操作

  /// 初始化服务（智能选择集成版本或回退版本）
  ///
  void _initService() {
    // 仅使用集成版本（必须有 singbox.dll）
    _singBoxService = SingBoxNativeService();
    _addLog('使用 sing-box 集成版本');
    _init();
  }

  /// 初始化
  Future<void> _init() async {
    // 设置回调
    _singBoxService.onLog = (log) {
      _addLog(log);
    };

    _singBoxService.onStatusChanged = (running) {
      // 当使用守护进程 (daemon) 建立 TUN 会话时，忽略本地 sing-box 服务的状态回调，
      // 以免其把 daemon 已连接状态错误覆盖为“未连接”（本地内核实际上未启动）。
      if (_sessionViaDaemon) {
        return;
      }
      _isConnected = running;
      _status = running ? '已连接' : '未连接';
      notifyListeners();
    };

    // 初始化 DNS 管理器
    await _dnsManager.init();

    // 从DNS管理器同步本地端口设置
    _localPort = _dnsManager.localPort;

    // 从DNS管理器同步strictRoute设置
    _tunStrictRoute = _dnsManager.strictRoute;

    // 加载配置
    await loadConfigs();

    // 读取偏好设置
    try {
      final prefs = await SharedPreferences.getInstance();
      // 系统代理默认关闭，避免首次启动改动系统设置
      _autoSystemProxy = prefs.getBool('auto_system_proxy') ?? false;
      _usePacFile = prefs.getBool('use_pac_file') ?? false;
      final savedMode = prefs.getString('proxy_mode') ?? 'rule';
      _proxyMode = ProxyMode.fromString(savedMode);

      // 加载会话级累计流量统计
      _sessionTotalUploadBytes = prefs.getInt('session_total_upload') ?? 0;
      _sessionTotalDownloadBytes = prefs.getInt('session_total_download') ?? 0;

      // 加载流量统计方式设置
      _useImprovedTrafficStats = prefs.getBool('use_improved_traffic_stats') ?? true;

      // TUN 模式：检查是否是首次启动
      final isFirstLaunch = prefs.getBool('app_initialized') ?? true;
      if (isFirstLaunch) {
        // 首次启动，默认关闭 TUN
        _useTun = false;
        await prefs.setBool('use_tun', false);
        await prefs.setBool('app_initialized', false);
        _addLog('首次启动，TUN 模式默认关闭');

        // 生成示例 PAC 文件
        final pacCreated = await _pacManager.createSamplePacFiles();
        if (pacCreated) {
          _addLog('已创建示例 PAC 文件，用户可自行修改');
        } else {
          _addLog('创建示例 PAC 文件失败');
        }
      } else {
        // 非首次启动，读取上次保存的状态
        _useTun = prefs.getBool('use_tun') ?? false;
        _addLog('已加载 TUN 开关状态 use_tun=${_useTun ? 'on' : 'off'}');
      }
      // strictRoute和localPort已在DNS Manager初始化后同步，这里不再重复读取
      // _tunStrictRoute = prefs.getBool('dns_strict_route') ?? false;  // 已移至DNS Manager同步
      _localPort = prefs.getInt('local_port') ?? _defaultLocalPort;
      // 守护进程模式已移除：强制关闭，避免走 daemon 分支
      _useDaemon = false;
      _enableClashApi = prefs.getBool('enable_clash_api') ?? true;
      _clashApiPort = prefs.getInt('clash_api_port') ?? 9090;
      _clashApiSecret = prefs.getString('clash_api_secret') ?? '';
      _autoSelectBestServer = prefs.getBool('auto_select_best_server') ?? false;
      _pingIntervalMinutes = prefs.getInt('ping_interval_minutes') ?? 10;

      // 计算 Windows 管理员权限
      await _computeWindowsAdmin();
      // 已移除本地 Wintun.dll 探测

      // 只有当用户启用了 TUN 模式，且缺少管理员权限时，才需要守护进程
      if (Platform.isWindows && _useTun && !_isWindowsAdmin && !_useDaemon) {
        // TUN 模式需要管理员权限或守护进程
        // 这里不自动启用守护进程，让用户在界面上选择
        _addLog('TUN 模式需要管理员权限');
      }

      // 恢复当前选中的配置
      final currentConfigId = prefs.getString('current_config_id');
      if (currentConfigId != null && _configs.isNotEmpty) {
        final config = _configs.firstWhere(
          (c) => c.id == currentConfigId,
          orElse: () => _configs.first,
        );
        _currentConfig = config;
        _addLog('已恢复配置 ${config.name}');
      }

      // 启动时清理遗留的系统代理（如果发现是本应用设置的本地代理 127.0.0.1:[当前端口/默认端口]）
      if (_proxyManager.isSupported) {
        try {
          final enabled = _proxyManager.getProxyEnabled();
          final server = _proxyManager.getProxyServer();
          final autoUrl = _proxyManager.getAutoConfigURL();
          if ((enabled && _isOurProxy(server)) ||
              (autoUrl.isNotEmpty && autoUrl.contains(_pacManager.pacUrl))) {
            final p = _parseLoopbackPort(server);
            _addLog(
              "检测到系统代理遗留 (server=$server, pac=$autoUrl, localPort=${p ?? 'n/a'})，已自动清理",
            );

            await _proxyManager.disableProxy();
          }
        } catch (_) {}
      }

      // 启动延时检测定时器（每5分钟自动更新一次）
      _startPingTimer();

      // 初始化系统代理状态缓存
      _updateSystemProxyStatus();
    } catch (_) {}
  }

  /// 计算 Windows 管理员权限（进程是否提升）
  Future<void> _computeWindowsAdmin() async {
    if (!Platform.isWindows) {
      _isWindowsAdmin = true;
      return;
    }
    bool elevated = false;
    try {
      final tokenHandlePtr = ffi_alloc.calloc<ffi.IntPtr>();
      final opened = win32.OpenProcessToken(
        win32.GetCurrentProcess(),
        win32.TOKEN_QUERY,
        tokenHandlePtr,
      );
      if (opened != 0) {
        final hToken = tokenHandlePtr.value;
        final elevation = ffi_alloc.calloc<ffi.Uint32>();
        final retLen = ffi_alloc.calloc<ffi.Uint32>();
        final ok = win32.GetTokenInformation(
          hToken,
          win32.TokenElevation,
          elevation.cast(),
          ffi.sizeOf<ffi.Uint32>(),
          retLen,
        );
        if (ok != 0) {
          elevated = elevation.value != 0;
        }
        win32.CloseHandle(hToken);
        ffi_alloc.calloc.free(elevation);
        ffi_alloc.calloc.free(retLen);
      }
      ffi_alloc.calloc.free(tokenHandlePtr);
    } catch (_) {
      elevated = false;
    }
    _isWindowsAdmin = elevated;
    notifyListeners();
  }

  // _computeWintunPresence 已删除

  /// 添加日志
  bool _shouldSuppressLog(String raw) {
    if (!_suppressNoisyLogs) return false;
    // 仅在非 TUN + 系统代理场景降噪
    if (_useTun) return false;
    final l = raw.toLowerCase();
    if (l.contains('outbound/block[block]')) return true;
    if (l.contains('operation not permitted')) return true;
    if (l.contains('raw-read tcp 127.0.0.1') && l.contains('aborted'))
      return true;
    if (l.contains('write tcp 127.0.0.1') && l.contains('aborted')) return true;
    return false;
  }

  void _addLog(String log) {
    if (_shouldSuppressLog(log)) {
      return; // 降噪：跳过高频无害错误日志
    }
    final line = '[${DateTime.now().toString().substring(11, 19)}] $log';
    print(line); // 控制台输出
    _logs.add(line);
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }
    _scheduleNotify(); // 替换直接 notify，提高性能
  }

  /// 加载配置
  Future<void> loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = prefs.getString('vpn_configs');

      if (configsJson != null) {
        final List<dynamic> decoded = jsonDecode(configsJson);
        _configs = decoded.map((e) => VPNConfig.fromJson(e)).toList();
        _deduplicateConfigIds();
        notifyListeners();
      }
    } catch (e) {
      _addLog('加载配置失败: $e');
    }
  }

  /// 保存配置
  Future<void> saveConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = jsonEncode(_configs.map((e) => e.toJson()).toList());
      await prefs.setString('vpn_configs', configsJson);
    } catch (e) {
      _addLog('保存配置失败: $e');
    }
  }

  /// 添加配置
  Future<void> addConfig(VPNConfig config) async {
    _configs.add(config);
    _deduplicateConfigIds();
    await saveConfigs();
    // 检测新配置的延迟
    _pingSingleConfig(config);
    notifyListeners();
  }

  /// 删除配置
  Future<void> deleteConfig(int index) async {
    if (index >= 0 && index < _configs.length) {
      final config = _configs[index];
      _configPings.remove(config.id); // 删除对应的延迟记录
      _configs.removeAt(index);
      await saveConfigs();
      notifyListeners();
    }
  }

  /// 删除所有配置
  Future<void> deleteAllConfigs() async {
    // 如果当前连接状态，先断开连接
    if (_isConnected) {
      await disconnect();
    }

    // 清空所有配置和相关数据
    _configs.clear();
    _configPings.clear();
    _currentConfig = null;

    // 保存配置并通知更新
    await saveConfigs();
    notifyListeners();

    _addLog('成功删除所有配置');
  }

  /// 更新配置
  Future<void> updateConfig(int index, VPNConfig config) async {
    if (index >= 0 && index < _configs.length) {
      _configs[index] = config;
      _deduplicateConfigIds();
      await saveConfigs();
      notifyListeners();
    }
  }

  /// 确保所有配置 ID 唯一，避免旧版本毫秒时间戳冲突导致多个节点共享同一 ping 记录
  void _deduplicateConfigIds() {
    final seen = <String>{};
    bool changed = false;
    for (int i = 0; i < _configs.length; i++) {
      final cfg = _configs[i];
      if (seen.contains(cfg.id)) {
        // 生成一个新的实例以获取新ID
        final newCfg = VPNConfig(
          name: cfg.name,
          type: cfg.type,
          server: cfg.server,
          port: cfg.port,
          settings: cfg.settings,
          enabled: cfg.enabled,
        );
        _configs[i] = newCfg;
        changed = true;
      } else {
        seen.add(cfg.id);
      }
    }
    if (changed) {
      _addLog('检测到重复配置 ID，已自动更换为新 ID');
      // 保存在调用方进行，这里不直接 await 以避免嵌套
    }
  }

  /// 导入订阅链接
  Future<bool> importFromLink(String link) async {
    try {
      String content = _extractFirstLink(link.trim()) ?? link.trim();
      final config = VPNConfig.fromSubscriptionLink(content);
      if (config != null) {
        await addConfig(config);
        _addLog('成功导入配置: ${config.name}');
        return true;
      } else {
        _addLog('无法解析订阅链接');
        return false;
      }
    } catch (e) {
      _addLog('导入失败: $e');
      return false;
    }
  }

  /// 批量导入订阅
  Future<int> importFromSubscription(String content) async {
    try {
      int imported = 0;
      final links = _extractAllLinks(content);
      for (final link in links) {
        if (await importFromLink(link)) imported++;
      }

      _addLog('成功导入配置: $imported');
      return imported;
    } catch (e) {
      _addLog('批量导入失败: $e');
      return 0;
    }
  }

  // 从任意文本中提取首个支持的链接，并消除内部空白（换行、空格等）
  String? _extractFirstLink(String text) {
    text = _normalizeSchemes(text);
    final re = RegExp(
      r"(hysteria2|vmess|vless|trojan|tuic|hy2|ss)://[-A-Za-z0-9\._~:/?#\[\]@!$&'()+,;=%\s]+",
      caseSensitive: false,
      multiLine: true,
    );
    final matches = re.allMatches(text).toList();
    if (matches.isEmpty) return null;

    // 归一化所有候选链接
    final candidates = matches
        .map((m) => m.group(0)!)
        .map((s) => s.replaceAll(RegExp(r'\s+'), ''))
        .toList();

    // 协议优先级（前者优先）
    const priority = [
      'vless',
      'vmess',
      'trojan',
      'tuic',
      'hysteria2',
      'hy2',
      'ss',
    ];

    String? best;
    int bestRank = 999;
    for (final c in candidates) {
      final lower = c.toLowerCase();
      int rank = 999;
      for (int i = 0; i < priority.length; i++) {
        final scheme = priority[i];
        if (lower.startsWith('$scheme://')) {
          rank = i;
          break;
        }
      }
      if (rank < bestRank) {
        best = c;
        bestRank = rank;
      }
    }
    return best ?? candidates.first;
  }

  // 从任意文本中提取所有支持的链接（归一化空白）
  List<String> _extractAllLinks(String text) {
    text = _normalizeSchemes(text);
    final re = RegExp(
      r"(hysteria2|vmess|vless|trojan|tuic|hy2|ss)://[-A-Za-z0-9\._~:/?#\[\]@!$&'()+,;=%\s]+",
      caseSensitive: false,
      multiLine: true,
    );
    return re
        .allMatches(text)
        .map((m) => m.group(0)!)
        .map((s) => s.replaceAll(RegExp(r'\s+'), ''))
        .toList();
  }

  // 归一化被空白字符拆开的协议头（例?"v l e s s : / /" -> "vless://"），避免误提取为 ss
  String _normalizeSchemes(String text) {
    var out = text;
    final replacements = <RegExp, String>{
      RegExp(r"v\s*l\s*e\s*s\s*s\s*:\s*/\s*/", caseSensitive: false):
          'vless://',
      RegExp(r"v\s*m\s*e\s*s\s*s\s*:\s*/\s*/", caseSensitive: false):
          'vmess://',
      RegExp(r"t\s*r\s*o\s*j\s*a\s*n\s*:\s*/\s*/", caseSensitive: false):
          'trojan://',
      RegExp(r"t\s*u\s*i\s*c\s*:\s*/\s*/", caseSensitive: false): 'tuic://',
      RegExp(r"h\s*y\s*2\s*:\s*/\s*/", caseSensitive: false): 'hy2://',
      RegExp(
        r"h\s*y\s*s\s*t\s*e\s*r\s*i\s*a\s*2\s*:\s*/\s*/",
        caseSensitive: false,
      ): 'hysteria2://',
      // 注意: ss 放最后，避免 vless 中的 "ss" 误替换；上面 vless 已先被修复
      RegExp(r"s\s*s\s*:\s*/\s*/", caseSensitive: false): 'ss://',
    };
    replacements.forEach((re, val) {
      out = out.replaceAll(re, val);
    });
    return out;
  }

  /// 连接 VPN
  Future<bool> connect(VPNConfig config) async {
    try {
      final swTotal = Stopwatch()..start();
      _addLog(
        'CONNECT: 开始连接 -> config=${config.name} 模式=${_proxyMode.name} useTun=$_useTun',
      );
      _addLog(
        'CONNECT: 环境快照 useDaemon=$_useDaemon isAdmin=$_isWindowsAdmin strictRoute=$_tunStrictRoute',
      );
      _isConnecting = true;
      _isDisconnecting = false; // 避免残留
      // 只有当需要使用 TUN 模式且启用了守护进程时，才走守护进程分支
      if (Platform.isWindows && _useTun && _useDaemon) {
        // 提前设置“正在连接”状态（之前缺失导致 UI 中央按钮第一次不变）
        _status = '正在连接...';
        _sessionViaDaemon = true; // 先标记：避免本地回调覆盖状态
        notifyListeners();
        _addLog('CONNECT: TUN模式 + 守护进程 -> daemon 分支');
        final ok = await _connectWithDaemon(config);
        // _connectWithDaemon 内部已在成功时设置 _isConnected/_status
        if (!ok) {
          // 失败恢复标记，允许后续本地模式再次尝试
          _sessionViaDaemon = false;
        }
        _isConnecting = false;
        notifyListeners();
        return ok;
      }
      // 早期阶段标记
      try {
        _singBoxService.debugEarly('PHASE0 connect entry');
      } catch (_) {}
      _status = '正在连接...';
      notifyListeners();

      // 1. 分配/校验本地监听端口（防止默认端口被其他进程或残留实例占用）
      final allocated = await _allocateLocalPort(preferred: _localPort);
      if (allocated != _localPort) {
        _addLog('本地端口 ${_localPort} 被占用，切换到可用端口 $allocated');
        _localPort = allocated;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('local_port', _localPort);
        } catch (_) {}
      } else {
        _addLog('使用本地端口: $_localPort');
      }

      // 初始化 sing-box
      _status = '正在初始化...';
      notifyListeners();
      final swInit = Stopwatch()..start();
      if (!await _singBoxService.initialize()) {
        _status = '初始化失败';
        notifyListeners();
        _isConnecting = false;
        return false;
      }
      _addLog('CONNECT: 初始化完成 ${swInit.elapsedMilliseconds}ms');

      // 检查 sing-box 是否安装
      _status = '正在检查环境...';
      notifyListeners();
      if (!await _singBoxService.isSingBoxInstalled()) {
        _addLog('sing-box 未安装，请下载 sing-box.exe');
        _status = 'sing-box 未安装';
        notifyListeners();
        _isConnecting = false;
        return false;
      }

      // Windows 下：若启用 TUN 但没有使用守护进程，需要检查管理员权限
      if (Platform.isWindows && _useTun && !_useDaemon) {
        // 使用新的权限管理器检查权限
        final bool isElevated = PrivilegeManager.instance.isElevated();
        if (!isElevated) {
          _status = '需要管理员权限以启用 TUN';
          _addLog('TUN 模式需要管理员权限，请在UI中选择自动提权或手动以管理员身份运行');
          notifyListeners();
          _isConnecting = false;
          return false;
        }
        _addLog('TUN 模式：使用管理员权限直接运行');
      }

      // 生成配置（使用当前代理模式，初始 MTU 可高, 后续根据探测回退）
      int? dynamicTunMtu; // 运行期可能调整的 MTU
      final singBoxConfig = await config.toSingBoxConfig(
        mode: _proxyMode,
        localPort: _localPort,
        useTun: _useTun,
        tunStrictRoute: _tunStrictRoute,
        preferredTunStack: _singBoxService.preferredTunStack,
        enableClashApi: _enableClashApi,
        clashApiPort: _clashApiPort,
        clashApiSecret: _clashApiSecret,
        tunMtu: dynamicTunMtu,
        enableIpv6: _dnsManager.enableIpv6,
      );
      _addLog(
        'CONNECT: ClashAPI enable=${_enableClashApi} port=${_clashApiPort}',
      );
      if (_useTun) {
        try {
          final inb =
              (singBoxConfig['inbounds'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
          _addLog('诊断: 初始 inbounds 列表: ' + inb.map((e) => e['type']).join(','));
          final tun = inb.firstWhere(
            (e) => e['type'] == 'tun',
            orElse: () => const {},
          );
          if (tun.isEmpty) {
            _addLog('诊断: 生成阶段未发现 TUN inbound (useTun=true)');
          } else {
            _addLog(
              '诊断: 生成阶段包含 TUN inbound stack=${tun['stack']} mtu=${tun['mtu']} auto_route=${tun['auto_route']}',
            );
          }
        } catch (e) {
          _addLog('诊断: 检查 TUN inbound 时异常 $e');
        }
      }
      if (_useTun) {
        final inboundList =
            (singBoxConfig['inbounds'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        final hasTun = inboundList.any((e) => (e['type'] == 'tun'));
        if (!hasTun) {
          _addLog('诊断: useTun=true 但配置缺少 TUN inbound -> 注入补丁');
          // Windows 也加上 IPv6 地址，避免 IPv6 流量绕过（此前仅 IPv4 导致 YouTube/QUIC IPv6 走系统栈）
          inboundList.insert(0, {
            'tag': 'tun-in',
            'type': 'tun',
            if (Platform.isWindows) 'interface_name': 'Gsou Adapter Tunnel',
            'address': ['172.19.0.1/30'],
            'mtu': 4064,
            'auto_route': true,
            'strict_route': _tunStrictRoute,
            'stack': Platform.isWindows ? 'system' : 'system',
          });
          singBoxConfig['inbounds'] = inboundList;
          try {
            final encoder = const JsonEncoder.withIndent('  ');
            final tmp = File(
              '${Directory.systemTemp.path}/gsou_config_after_inject.json',
            );
            await tmp.writeAsString(encoder.convert(singBoxConfig));
            _addLog('TUN 注入后配置已写出: ${tmp.path}');
          } catch (e) {
            _addLog('写出注入后配置失败: $e');
          }
        } else {
          _addLog('诊断: 已检测到 TUN inbound');
        }
      }
      try {
        _singBoxService.debugEarly('PHASE1 config generated');
      } catch (_) {}

      // 若用户选择 TUN + 全局模式，在 Windows 下尽量避免强制走 system(Wintun) 栈
      // 当前默认就是 gvisor，无需切换；这里仅在检测到 inbounds 中存在 type=tun 且 stack=system 时做一次网卡存在性快速校验
      // 移除系统适配器强校验，交由守护进程或底层自行处理

      // 测试配置
      _status = '正在验证配置...';
      notifyListeners();
      final swTest = Stopwatch()..start();
      if (!await _singBoxService.testConfig(singBoxConfig)) {
        _status = '配置无效';
        notifyListeners();
        _isConnecting = false;
        return false;
      }
      _addLog('CONNECT: **配置验证通过 ${swTest.elapsedMilliseconds}ms');
      try {
        _singBoxService.debugEarly('PHASE2 testConfig ok');
      } catch (_) {}

      // 启动服务
      _status = '正在启动服务...';
      notifyListeners();
      final swStart = Stopwatch()..start();
      final started = await _singBoxService.start(singBoxConfig);
      _sessionViaDaemon = false; // 本地 FFI 启动
      if (started) {
        try {
          _singBoxService.debugEarly('PHASE3 start returned success');
        } catch (_) {}
        // 输出 experimental.clash_api 注入结果
        try {
          final exp = (singBoxConfig['experimental'] as Map<String, dynamic>?);
          if (exp != null && exp.containsKey('clash_api')) {
            _addLog(
              'CONNECT: experimental.clash_api 已注入 -> ${exp['clash_api']}',
            );
          } else {
            _addLog(
              'CONNECT: 未发现 experimental.clash_api (enableClashApi=${_enableClashApi})',
            );
          }
        } catch (e) {
          _addLog('CONNECT: 检查 clash_api 注入异常: $e');
        }
        _currentConfig = config;
        _isConnected = true;
        _status = '已连接';
        final totalMs = swTotal.elapsedMilliseconds;
        // 持久化当前配置 ID，确保断开或重启后仍保持当前选择
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('current_config_id', config.id);
        } catch (_) {}
        // PAC 和系统代理将使用 sing-box 启动成功后配置，确保端口分配正确

        // ============== 轻量系统代理启用逻辑（替换原复杂 PAC / 连通性测试，来源于精简 provider ==============
        // 目标：降低 CPU 占用，仅在需要时设置 WinINET 代理；不再启用 PAC 服务 / 周期性测试
        // 条件：开启自动系统代理 && 平台支持 && 未使用 TUN
        if (_autoSystemProxy && _proxyManager.isSupported && !_useTun) {
          final ok = await _proxyManager.enableProxy(port: _localPort);
          if (ok) {
            _addLog('已开启系统代理 (轻量): 127.0.0.1:$_localPort');
          } else {
            _addLog('开启系统代理失败 (轻量)');
          }
          // 异步后台再进行多次确认与必要的重试，提升启动后立即可用的成功率
          // 不阻塞主连接流程
          unawaited(_ensureSystemProxyEnabled());
        } else {
          if (_useTun) {
            _addLog('TUN 模式下跳过系统代理 (轻量)');
          } else if (!_autoSystemProxy) {
            _addLog('系统代理未启用 (轻量)');
          } else if (!_proxyManager.isSupported) {
            _addLog('平台不支持系统代理 (轻量)');
          }
        }
        // ======================================================================================

        // 启动流量统计定时器和状态监控
        _startTrafficStatsTimer();
        _startStatusMonitor();
        if (_enableClashApi) {
          _openClashTrafficStream();
        }
        _addLog(
          'CONNECT: 启动成功 用时 start=${swStart.elapsedMilliseconds}ms total=${totalMs}ms',
        );
        _isConnecting = false;
        _isConnecting = false;
        notifyListeners();

        // ========== TUN 连通性探测 & MTU 回退逻辑 ==========
        if (_useTun) {
          unawaited(_postTunConnectivityProbe(config));
        }
        return true;
      } else {
        // 如果启用 Clash API 可能因为内核不支持导致失败—自动回退一层
        if (_enableClashApi) {
          _addLog('检测到启动失败，尝试关闭 Clash API 后回退重试一遍..');
          try {
            singBoxConfig['experimental']?.remove('clash_api');
          } catch (_) {}
          final retry = await _singBoxService.start(singBoxConfig);
          if (retry) {
            _addLog('关闭 Clash API 后重试成功 -> 恢复默认配置');
            _enableClashApi = false;
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('enable_clash_api', false);
            } catch (_) {}
            _sessionViaDaemon = false;
            _currentConfig = config;
            _isConnected = true;
            _status = '已连接';
            _startTrafficStatsTimer();
            _startStatusMonitor();
            if (_enableClashApi) {
              _openClashTrafficStream();
            }
            notifyListeners();
            return true;
          } else {
            _addLog('关闭 Clash API 后重试失败');
            // 特判：clash api is not included
            try {
              final lastErr = _singBoxService.getLastErrorString?.call();
              if (lastErr != null &&
                  lastErr.contains('clash api is not included')) {
                _addLog(
                  '提示: 当前 DLL 未编译 clash_api。请执行: dart run tools/prebuild.dart --force --ref v1.12.5',
                );
              }
            } catch (_) {}
          }
        }
        try {
          _singBoxService.debugEarly('PHASE3 start returned failure');
        } catch (_) {}
        _status = '连接失败';
        notifyListeners();
        _isConnecting = false;
        return false;
      }
    } catch (e) {
      _addLog('连接失败: $e');
      try {
        _singBoxService.debugEarly('EXCEPTION connect $e');
      } catch (_) {}
      _status = '连接失败';
      notifyListeners();
      _isConnecting = false;
      return false;
    }
  }

  // ================= TUN 连通性探测与 MTU 回退 =================
  // 设计目标：解决“偶尔无法访问 Google”问题，常见根因可能是 MTU 过大导致 TLS 首包碎片/丢包
  // 策略：连接成功后异步依次测试若干域名/地址连通性，失败则回退 MTU 并自动重建连接（有限次数）
  Future<void> _postTunConnectivityProbe(VPNConfig cfg) async {
    if (!_useTun || !_isConnected) return;
    const probeHosts = ['www.google.com', 'www.gstatic.com'];
    // MTU 回退序列（首个为当前默认 4064，然后快速降到常见安全值）
    final mtuPlan = <int>[4064, 1500, 1480, 1400, 1280];
    int attempt = 0;
    bool success = false;
    int appliedMtuIndex = 0; // 当前使用的 mtuPlan 索引
    // 辅助函数：TCP 443 探测 + DNS 解析
    Future<bool> _probeOnce(String host) async {
      try {
        final ips = await InternetAddress.lookup(
          host,
        ).timeout(const Duration(seconds: 5));
        if (ips.isEmpty) return false;
        final ip = ips.first;
        final socket = await Socket.connect(
          ip,
          443,
          timeout: const Duration(seconds: 5),
        );
        socket.destroy();
        return true;
      } catch (_) {
        return false;
      }
    }

    // 若默认 MTU 就成功，不做任何动作；若失败则逐步降级 MTU
    while (attempt < mtuPlan.length && !_disposed) {
      final mtu = mtuPlan[attempt];
      appliedMtuIndex = attempt;
      _addLog('[TUN探测] 尝试 MTU=$mtu (attempt=${attempt + 1}/${mtuPlan.length})');
      // 如果不是第一次（默认 MTU）且需要回退 -> 重连使用新 MTU
      if (attempt > 0) {
        // 防抖：确保之前连接仍在（可能用户已手动断开）
        if (!_isConnected) break;
        _addLog('[TUN探测] 需要回退 MTU 到 ${mtuPlan[attempt - 1]}');
        await disconnect();
        await Future.delayed(const Duration(milliseconds: 350));
        final ok = await _reconnectWithTunMtu(cfg, mtu: mtu);
        if (!ok) {
          _addLog(
            '[TUN探测] 使用 MTU=${mtuPlan[attempt]} 失败，尝试回退到 ${mtuPlan[attempt - 1]}',
          );
          attempt++;
          continue;
        }
      }

      // 连接稳定后执行多主机探测
      bool batchOk = true;
      for (final h in probeHosts) {
        final ok = await _probeOnce(h);
        _addLog('[TUN探测] host=$h 结果=${ok ? 'OK' : 'FAIL'}');
        if (!ok) {
          batchOk = false;
          break;
        }
      }
      if (batchOk) {
        success = true;
        break;
      }
      attempt++;
    }
    if (success) {
      final finalMtu = mtuPlan[appliedMtuIndex];
      _addLog('[TUN探测] 连通性良好 (MTU=$finalMtu)');
    } else {
      _addLog(
        '[TUN探测] 所有 MTU 方案仍未通过初始探测，保留最后尝试 MTU=${mtuPlan[appliedMtuIndex]}',
      );
    }
  }

  // 使用指定 MTU 重建配置并连接（保持当前其它参数不变）
  Future<bool> _reconnectWithTunMtu(VPNConfig cfg, {required int mtu}) async {
    try {
      if (!_useTun) return false;
      final singBoxConfig = await cfg.toSingBoxConfig(
        mode: _proxyMode,
        localPort: _localPort,
        useTun: true,
        tunStrictRoute: _tunStrictRoute,
        preferredTunStack: _singBoxService.preferredTunStack,
        enableClashApi: _enableClashApi,
        clashApiPort: _clashApiPort,
        clashApiSecret: _clashApiSecret,
        tunMtu: mtu,
        enableIpv6: _dnsManager.enableIpv6,
      );
      // 仅测试与启动，无需再次端口分配
      if (!await _singBoxService.testConfig(singBoxConfig)) {
        _addLog('[TUN探测] MTU=$mtu testConfig 未通过');
        return false;
      }
      final started = await _singBoxService.start(singBoxConfig);
      if (started) {
        _currentConfig = cfg;
        _isConnected = true;
        _status = '已连接';
        _startTrafficStatsTimer();
        _startStatusMonitor();
        if (_enableClashApi) _openClashTrafficStream();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _addLog('[TUN探测] 使用 MTU=$mtu 重连异常: $e');
      return false;
    }
  }

  // 确保系统代理真正启用：针对启动后首次 enable 可能因 WinINET 刷新/注册表传播延迟导致读取未及时更新
  // - attempts: 最大尝试次数
  // 策略：首次延迟 ~120ms，然后指数递增 (150ms, 320ms, 600ms...) 再试 enable + 读取状态
  Future<void> _ensureSystemProxyEnabled({int attempts = 3}) async {
    if (!_autoSystemProxy || _useTun || !_proxyManager.isSupported) return;
    // 给予 sing-box 端口 listen 与注册表写入一个最小缓冲
    await Future.delayed(const Duration(milliseconds: 120));
    for (var i = 1; i <= attempts; i++) {
      try {
        final ok = await _proxyManager.enableProxy(port: _localPort);
        _updateSystemProxyStatus();
        final statusOk = _systemProxyEnabled;
        if (ok && statusOk) {
          _addLog('系统代理确认启用成功 (attempt $i/$attempts)');
          return;
        } else {
          _addLog('系统代理尝试 $i/$attempts: enable=$ok status=$statusOk');
        }
      } catch (e) {
        _addLog('系统代理尝试 $i/$attempts 异常: $e');
      }
      if (i < attempts) {
        final delay = Duration(milliseconds: 150 + (i * i) * 170);
        await Future.delayed(delay);
      }
    }
    if (!_systemProxyEnabled) {
      _addLog('系统代理多次尝试后仍未确认启用，必要时手动切换一次开关。');
    }
  }

  /// 设置 Clash API 开�?
  Future<void> setEnableClashApi(bool enabled) async {
    _enableClashApi = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enable_clash_api', enabled);
    } catch (_) {}
    notifyListeners();
    if (_isConnected && _currentConfig != null) {
      _addLog('Clash API 关闭后重试成功');
      final cfg = _currentConfig!;
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 400));
      await connect(cfg);
    }
  }

  /// 设置 Clash API 端口
  Future<void> setClashApiPort(int port) async {
    if (port <= 0 || port > 65535) return;
    _clashApiPort = port;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('clash_api_port', port);
    } catch (_) {}
    notifyListeners();
  }

  /// 诊断 Clash API 状态：主动探测 127.0.0.1:port/connections
  Future<void> debugClashApiStatus() async {
    _addLog(
      '[diag] ClashAPI 开启状态: ${_enableClashApi} port=$_clashApiPort secretLen=${_clashApiSecret.length} connected=$_isConnected',
    );
    if (!_isConnected) {
      _addLog('[diag] 当前未连接，无法检测运行时端口');
      return;
    }
    try {
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      client.connectionTimeout = const Duration(seconds: 3);
      final uri = Uri.parse('http://127.0.0.1:$_clashApiPort/connections');
      final req = await client.getUrl(uri);
      if (_clashApiSecret.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $_clashApiSecret');
      }
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      _addLog('[diag] HTTP ${resp.statusCode} len=${body.length}');
      if (resp.statusCode == 200) {
        _addLog(
          '[diag] bodyPreview: ${body.substring(0, body.length > 180 ? 180 : body.length)}',
        );
      }
      client.close();
    } catch (e) {
      _addLog('[diag] 访问 Clash API 失败: $e');
      if (!_enableClashApi) {
        _addLog('[diag] 提示: clash_api 已被自动禁用，可调用 forceReenableClashApi() 重试');
      }
    }
  }

  /// 强制重新启用 Clash API 并重连（绕过曾经的失败回退�?
  Future<void> forceReenableClashApi() async {
    if (_enableClashApi) {
      _addLog('forceReenableClashApi: Clash API 已开启，无需强制');
    } else {
      _addLog('forceReenableClashApi: 强制启用 Clash API');
      await setEnableClashApi(true);
    }
    if (_isConnected && _currentConfig != null) {
      final cfg = _currentConfig!;
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 400));
      await connect(cfg);
    }
  }

  /// 设置是否启用 TUN
  Future<void> setUseTun(bool enabled) async {
    if (_useTun == enabled) return;
    final prev = _useTun;
    _useTun = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('use_tun', enabled);
    } catch (_) {}
    _addLog('切换 TUN: $prev -> $enabled');
    // 互斥：开启 TUN 时强制关闭自动系统代理（仅修改 flag 与实际代理状态）
    if (enabled && _autoSystemProxy) {
      _addLog('关闭 TUN -> 关闭自动系统代理（仅修改 flag）');
      _autoSystemProxy = false; // 直接改内部状态避免循环调用
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auto_system_proxy', false);
      } catch (_) {}
      if (_proxyManager.isSupported) {
        try {
          final ok = await _proxyManager.disableProxy();
          if (ok) {
            _addLog('已关闭系统代理（互斥）');
          }
          await _pacManager.stopPacServer();
        } catch (e) {
          _addLog('关闭系统代理(互斥)时异常: $e');
        }
      }
    } else if (!enabled) {
      // 从 TUN 模式关闭 -> 自动打开系统代理
      if (_proxyManager.isSupported) {
        _autoSystemProxy = true;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('auto_system_proxy', true);
        } catch (_) {}
        _addLog('关闭 TUN -> 自动启用系统代理');
        try {
          final ok = await _proxyManager.enableProxy(port: _localPort);
          if (ok) {
            _addLog('系统代理已自动开启 (TUN关闭) 127.0.0.1:$_localPort');
            // 后台再做一次确认重试
            unawaited(_ensureSystemProxyEnabled());
          } else {
            _addLog('系统代理自动开启失败 (TUN关闭)');
          }
        } catch (e) {
          _addLog('系统代理自动开启异常 (TUN关闭): $e');
        }
      } else {
        _addLog('关闭 TUN 后尝试启用系统代理，但平台不支持');
      }
    }

    // 更新系统代理状态缓存并通知 UI
    _updateSystemProxyStatus();
    notifyListeners();
    // 若当前已连接，需要重新建立以应用 TUN 变化
    if (_isConnected && _currentConfig != null) {
      _addLog('TUN 状态变化，重新连接以应用新配置');
      final cfg = _currentConfig!;
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 400));
      await connect(cfg);
    }
  }

  /// 设置 strict_route A/B
  Future<void> setTunStrictRoute(bool enabled) async {
    _tunStrictRoute = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dns_strict_route', enabled);
    } catch (_) {}
    _addLog('已设置 strict_route=${enabled} (重新连接后生效)');
    notifyListeners();
  }

  /// 手动触发一次健康探测（UI 按钮调试用）
  Future<void> manualHealthProbe() async {
    try {
      final ok = await _singBoxService.probeHealthOnce();
      _addLog('手动健康探测: ${ok ? '成功' : '失败'}');
    } catch (e) {
      _addLog('手动健康探测异常: $e');
    }
  }

  /// 清除记录的首选 TUN 栈（下次连接时使用默认策略）
  Future<void> clearPreferredTunStack() async {
    try {
      final ok = await _singBoxService.clearPreferredTunStack();
      if (ok) {
        _addLog('已清除首选 TUN 栈（下次连接使用默认策略）');
      }
    } catch (e) {
      _addLog('清除首选 TUN 栈异常: $e');
    }
  }

  /// 断开 VPN
  Future<bool> disconnect() async {
    try {
      _isDisconnecting = true;
      _isConnecting = false; // 防止并发
      _status = '正在断开...';
      notifyListeners();

      bool success = false;
      if (_sessionViaDaemon) {
        success = await _vpnManager.stopVPN();
        _addLog(success ? '?(daemon) 断开成功' : '?(daemon) 断开失败');
      } else {
        success = await _singBoxService.stop();
        _addLog(success ? '?(local) 断开成功' : '?(local) 断开失败');
      }

      if (success) {
        // 关闭系统代理（轻量版，不再关闭 PAC 服务器）
        if (_proxyManager.isSupported) {
          try {
            final enabled = _proxyManager.getProxyEnabled();
            final server = _proxyManager.getProxyServer();
            if (enabled && _isOurProxy(server)) {
              final ok = await _proxyManager.disableProxy();
              if (ok) _addLog('已关闭系统代理（轻量）');
            }
          } catch (e) {
            _addLog('关闭系统代理异常（轻量）: $e');
          }
        }
        _isConnected = false;
        _status = '未连接';
        // _currentConfig = null; // 保留当前配置，不要清�?
        _connectionStartTime = null;
        _sessionViaDaemon = false;
        // 停止流量统计定时器和状态监控
        _stopTrafficStatsTimer();
        _stopStatusMonitor();
        _isDisconnecting = false;
        notifyListeners();
        return true;
      } else {
        _status = '断开失败';
        _isDisconnecting = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _addLog('断开失败: $e');
      _status = '断开失败';
      _isDisconnecting = false;
      notifyListeners();
      return false;
    }
  }

  /// 重置所有应用偏好设置（不删除已导入的配置，可选参数控制）
  /// [includeConfigs]
  Future<void> resetPreferences({bool includeConfigs = false}) async {
    try {
      _addLog('正在重置偏好设置...');
      final prefs = await SharedPreferences.getInstance();

      // 若不清除配置，备份配置相关键
      String? configsBackup;
      if (!includeConfigs) {
        configsBackup = prefs.getString('vpn_configs');
      }

      // 直接清空所有键
      await prefs.clear();

      // 恢复配置数据（如果需要保留）
      if (!includeConfigs && configsBackup != null) {
        await prefs.setString('vpn_configs', configsBackup);
      } else if (includeConfigs) {
        _configs.clear();
        _configPings.clear();
        _currentConfig = null;
      }

      // 内存状态回到初始默认值
      _autoSystemProxy = false;
      _usePacFile = false;
      _proxyMode = ProxyMode.rule; // 默认规则模式
      _useTun = false;
      _tunStrictRoute = false;
      _localPort = _defaultLocalPort;
      _useDaemon = false;
      _enableClashApi = true; // 恢复默认打开，便于重新尝试
      _clashApiPort = 9090;
      _clashApiSecret = '';
      _autoSelectBestServer = false;
      _pingIntervalMinutes = 10;
      _currentConfig = null;
      _connectionStartTime = null;

      // 停止可能的连接
      if (_isConnected) {
        await disconnect();
      }

      notifyListeners();
      _addLog("重置偏好设置${includeConfigs ? '（包括配置）' : ''}");
      _addLog('内存状态已恢复到初始默认值');
    } catch (e) {
      _addLog('重置偏好设置失败: $e');
    }
  }

  /// 切换连接状态
  Future<void> toggleConnection(VPNConfig config) async {
    if (_isConnected && _currentConfig == config) {
      await disconnect();
    } else {
      if (_isConnected) {
        await disconnect();
        await Future.delayed(const Duration(seconds: 1));
      }
      await connect(config);
    }
  }

  /// 设置当前配置（不连接）
  Future<void> setCurrentConfig(VPNConfig config) async {
    _currentConfig = config;

    // 保存当前配置ID到SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_config_id', config.id);
    } catch (e) {
      _addLog('保存当前配置失败: $e');
    }

    notifyListeners();
    _addLog('已选择配置: ${config.name}');
  }

  /// 清空日志
  void clearLogs() {
    _logs.clear();
    _scheduleNotify();
  }

  // 上面如果存在旧版 dispose 定义已移除，仅保留此处最终实现

  /// 切换是否使用守护进程模式（影响 TUN 权限路径）
  Future<void> setUseDaemon(bool enabled) async {
    // 守护进程模式已移除，强制为 false
    if (_useDaemon == false && enabled == false) return;
    _useDaemon = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('use_daemon', false);
    } catch (_) {}
    _addLog('守护进程模式已移除：始终使用内置内核');
    notifyListeners();
    // 若当前已连接，不触发断连重连，保持现状
  }

  /// 切换自动系统代理偏好
  Future<void> setAutoSystemProxy(bool enabled) async {
    // 互斥：若试图开启系统代理但当前�?TUN 模式，先关闭 TUN
    if (enabled && _useTun) {
      _addLog('启用系统代理 -> 关闭 TUN 以避免冲突');
      // 直接修改状态，避免递归调用 setUseTun 引起重复重连�?
      final prevTun = _useTun;
      _useTun = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('use_tun', false);
      } catch (_) {}
      if (prevTun && _isConnected && _currentConfig != null) {
        _addLog('因互斥关闭 TUN，重新连接以应用');
        final cfg = _currentConfig!;
        await disconnect();
        await Future.delayed(const Duration(milliseconds: 300));
        await connect(cfg);
      }
    }
    _autoSystemProxy = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_system_proxy', enabled);
    } catch (_) {}
    notifyListeners();

    // 即时应用（轻量逻辑�?
    if (_isConnected && _proxyManager.isSupported) {
      if (enabled && !_useTun) {
        final ok = await _proxyManager.enableProxy(port: _localPort);
        if (ok) _addLog('已开启系统代理（轻量模式）: 127.0.0.1:$_localPort');
      } else {
        try {
          final enabledSys = _proxyManager.getProxyEnabled();
          final server = _proxyManager.getProxyServer();
          if (enabledSys && _isOurProxy(server)) {
            final ok = await _proxyManager.disableProxy();
            if (ok) _addLog('已关闭系统代理（轻量模式）');
          }
        } catch (e) {
          _addLog('关闭系统代理异常（轻量模式）: $e');
        }
      }
    }

    // 更新系统代理状态缓存
    _updateSystemProxyStatus();
  }

  /// 切换 PAC 文件模式
  Future<void> setUsePacFile(bool enabled) async {
    // 轻量模式下：忽略 PAC 文件切换，仅保存标志（以便未来可能恢复原功能�?
    _usePacFile = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('use_pac_file', enabled);
    } catch (_) {}
    _addLog("PAC 模式${enabled ? '已启用（当前系统代理未生效）' : '已关闭'}");
    notifyListeners();
  }

  /// 切换代理模式
  Future<void> setProxyMode(ProxyMode mode) async {
    if (_proxyMode == mode) return;

    _proxyMode = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('proxy_mode', mode.value);
    } catch (_) {}

    _addLog('切换到${mode.name}模式');
    notifyListeners();

    // 如果已连接，需要重新连接以应用新的规则
    if (_isConnected && _currentConfig != null) {
      _addLog('应用新的代理模式，正在重新连�?..');
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      await connect(_currentConfig!);
    }
  }

  /// 分配可用本地端口（起始于 preferred，随后递增扫描）
  Future<int> _allocateLocalPort({
    int preferred = _defaultLocalPort,
    int maxTries = 10,
  }) async {
    Future<bool> _isFree(int port, {bool quickCheck = true}) async {
      try {
        final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
        await server.close();

        // 快速模式只检查IPv4，节省时间
        if (quickCheck) {
          return true;
        }

        // 完整模式检查IPv6
        final server6 = await ServerSocket.bind(InternetAddress.anyIPv6, port);
        await server6.close();
        return true;
      } catch (_) {
        return false;
      }
    }

    if (await _isFree(preferred)) return preferred;
    for (int i = 1; i < maxTries; i++) {
      final cand = preferred + i;
      if (await _isFree(cand)) return cand;
    }
    // 兜底：让系统选一个空闲端口（临时端口）
    try {
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final p = tmp.port;
      await tmp.close();
      return p;
    } catch (_) {
      return preferred; // 实在失败保留原端口
    }
  }

  /// 启动流量统计定时器
  void _startTrafficStatsTimer() {
    _stopTrafficStatsTimer(); // 确保只有一个定时器
    resetTrafficStats(); // 重置统计数据
    _connectionStartTime = DateTime.now(); // 记录连接开始时间

    if (_useImprovedTrafficStats) {
      // 使用改进的流量统计服务
      _improvedTrafficService.onTrafficUpdate = (data) {
        _uploadBytes = data.totalUploadBytes;
        _downloadBytes = data.totalDownloadBytes;
        _uploadSpeed = data.uploadSpeed;
        _downloadSpeed = data.downloadSpeed;
        _scheduleNotify();
      };

      _improvedTrafficService.start(
        clashApiPort: _clashApiPort,
        clashApiSecret: _clashApiSecret,
        enableClashApi: _enableClashApi,
      );
    } else {
      // 使用原有的流量统计逻辑
      _updateConnectionsData(force: true); // 获取真实连接数据（首次可更新速度）
      // 若用户已开启真实网卡统计且尚未确定接口名，尝试探测
      if (_useInterfaceCounters && _tunInterfaceName == null) {
        _detectTunInterfaceName();
      }
      _trafficStatsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        // 定时仅调用统一入口，内部根据是否有 WS 决定是否更新速度
        _updateTrafficStats();
      });

      // 若启用 Clash API，尝试建立实时流 (WebSocket)
      if (_enableClashApi) {
        _openClashTrafficStream();
      }
    }
  }

  /// 停止流量统计定时器
  void _stopTrafficStatsTimer() {
    // 在停止前，将当前流量累加到会话总计中
    _sessionTotalUploadBytes += _uploadBytes;
    _sessionTotalDownloadBytes += _downloadBytes;

    // 保存会话级流量统计到本地存储
    _saveSessionTrafficStats();

    if (_useImprovedTrafficStats) {
      // 停止改进的流量统计服务
      _improvedTrafficService.stop();
      _improvedTrafficService.onTrafficUpdate = null;
    } else {
      // 停止原有的流量统计逻辑
      _trafficStatsTimer?.cancel();
      _trafficStatsTimer = null;
      _closeClashTrafficStream();
    }

    _connections.clear(); // 清空连接列表
  }

  /// 保存会话级流量统计到本地存储
  Future<void> _saveSessionTrafficStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('session_total_upload', _sessionTotalUploadBytes);
      await prefs.setInt('session_total_download', _sessionTotalDownloadBytes);
    } catch (e) {
      debugPrint('保存会话流量统计失败: $e');
    }
  }

  /// 更新流量统计（优先使用真实数据）
  void _updateTrafficStats() {
    if (!_isConnected) return;
    final now = DateTime.now();
    final timeDiff = now.difference(_lastUpdateTime).inMilliseconds;
    if (timeDiff >= 1000) {
      // 每秒更新一次
      // 更新连接时长
      if (_connectionStartTime != null) {
        _connectionDuration = now.difference(_connectionStartTime!);
      }
      // 统一策略：若启用 Clash API -> 优先使用 WS/HTTP；仅在 Clash 关闭时才考虑 daemon / 系统统计
      if (_enableClashApi) {
        // 若 WebSocket 已建立则实时更新中，这里只处理 HTTP 轮询兜底（方法内部会自动跳过 WS 活跃时的轮询）
        _updateTrafficFromClashAPI();
        // 仍需刷新连接列表，但不要覆盖 WS 平滑速度
        _updateConnectionsData(updateGlobalSpeed: false);
        // 若用户要求真实接口统计，且 Clash WS 活跃，则仅用接口统计补充累计字节，不覆盖速度
        if (_useInterfaceCounters) {
          // 仅在当前无 WebSocket 速度增量时，用接口统计补充“可视速度”，不写入累计总量，防止混入系统级字节
          _updateTrafficFromInterface(aggregateIntoGlobal: false);
        }
      } else if (_useDaemon && _sessionViaDaemon) {
        // Clash API 关闭时才使用守护进程聚合统计
        _updateTrafficFromDaemon();
        _updateConnectionsData();
        if (_useInterfaceCounters) {
          _updateTrafficFromInterface(aggregateIntoGlobal: false);
        }
      } else {
        // 回退：系统连接级统计（可能粒度较粗） +（可选）真实接口统计
        _updateConnectionsData();
        if (_useInterfaceCounters) {
          _updateTrafficFromInterface(
            aggregateIntoGlobal: true,
          ); // 替代 Clash/Daemon 来源，允许作为后备
        }
      }

      _lastUpdateTime = now;
      _scheduleNotify();
    }
  }

  // ========== 通过 Windows 网卡统计真实流量 ==========
  Future<void> _updateTrafficFromInterface({
    bool force = false,
    bool aggregateIntoGlobal = true,
  }) async {
    if (!_useInterfaceCounters) return;
    if (!_isConnected) return;
    // 与更新节奏对齐：默认 1s 内只取一次，除非 force
    if (!force && _ifLastReadTime != null) {
      final diff = DateTime.now().difference(_ifLastReadTime!).inMilliseconds;
      if (diff < 800) return; // 节流
    }
    try {
      // 确保已知道接口名；若未知尝试探测一次
      if (_tunInterfaceName == null) {
        await _detectTunInterfaceName();
        if (_tunInterfaceName == null) return; // 仍未找到
      }
      final fetcher =
          _interfaceCountersFetcher ?? _defaultInterfaceCountersFetcher;
      final tuple = await fetcher();
      if (tuple == null) return;
      final (rxAbs, txAbs) = tuple;
      if (rxAbs < 0 || txAbs < 0) return;
      if (_ifLastRxBytes == 0 && _ifLastTxBytes == 0) {
        _ifLastRxBytes = rxAbs;
        _ifLastTxBytes = txAbs;
        _ifLastReadTime = DateTime.now();
        return; // 首次仅建立基线
      }
      final now = DateTime.now();
      final dtMs = now.difference(_ifLastReadTime ?? now).inMilliseconds;
      if (dtMs <= 0) return;
      final rxDelta = rxAbs - _ifLastRxBytes;
      final txDelta = txAbs - _ifLastTxBytes;
      // 处理可能的 64bit wrap 或重置（负增量）
      final safeRxDelta = rxDelta >= 0 ? rxDelta : 0;
      final safeTxDelta = txDelta >= 0 ? txDelta : 0;
      if (aggregateIntoGlobal) {
        _uploadBytes += safeTxDelta;
        _downloadBytes += safeRxDelta;
      }
      // 当 Clash WS 未提供速度（或未启用 Clash API），由此计算速度和平滑
      final shouldCalcSpeed = !_enableClashApi || !_clashStreamActive;
      if (shouldCalcSpeed) {
        _recordSpeedSample(safeTxDelta, safeRxDelta, dtMs);
      }
      _ifLastRxBytes = rxAbs;
      _ifLastTxBytes = txAbs;
      _ifLastReadTime = now;
    } catch (e) {
      // 失败静默（可加一次日志）
      debugPrint('接口统计获取失败: $e');
    }
  }

  // 默认抓取器：调用 PowerShell Get-NetAdapterStatistics
  Future<(int, int)?> _defaultInterfaceCountersFetcher() async {
    final name = _tunInterfaceName;
    if (name == null || name.isEmpty) return null;
    try {
      final ps = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        // 注意：Dart 字符串中 $ 需要转义为 \$ 以避免被当作插值；PowerShell 将接收 $s 变量。
        "& { \$s = Get-NetAdapterStatistics -Name '" +
            name +
            "' -ErrorAction SilentlyContinue; if(\$s){ Write-Output \$s.ReceivedBytes; Write-Output \$s.SentBytes } }",
      ]).timeout(const Duration(seconds: 2));
      final out = (ps.stdout ?? '').toString().trim();
      if (out.isEmpty) return null;
      final lines = out
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.length < 2) return null;
      final rx = int.tryParse(lines[0].trim());
      final tx = int.tryParse(lines[1].trim());
      if (rx == null || tx == null) return null;
      return (rx, tx);
    } catch (_) {
      return null;
    }
  }

  // 探测 TUN 接口名：优先用户配置，其次匹配包含 Wintun 的网卡。
  Future<void> _detectTunInterfaceName() async {
    if (_tunInterfaceName != null) return;
    try {
      final ps = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        '& { Get-NetAdapter | Where-Object { \$_.Name -like "*Wintun*" -or \$_.InterfaceDescription -like "*Wintun*" } | Select-Object -First 1 -ExpandProperty Name }',
      ]).timeout(const Duration(seconds: 2));
      final name = (ps.stdout ?? '').toString().trim();
      if (name.isNotEmpty) {
        _tunInterfaceName = name;
        _addLog('检测到 TUN 接口: $name (用于真实流量统计)');
      }
    } catch (_) {}
  }

  /// 从守护进程更新流量统计
  Future<void> _updateTrafficFromDaemon() async {
    try {
      final daemonClient = DaemonClient();
      final stats = await daemonClient.getTrafficStats();

      if (stats != null) {
        final now = DateTime.now();
        final timeDiff = now.difference(_lastUpdateTime).inSeconds;

        if (timeDiff > 0) {
          // 计算上传和下载的增量
          final uploadIncrement =
              (stats['uploadTotal'] as int) - _lastUploadBytes;
          final downloadIncrement =
              (stats['downloadTotal'] as int) - _lastDownloadBytes;

          // 更新累计流量
          _uploadBytes += uploadIncrement > 0 ? uploadIncrement : 0;
          _downloadBytes += downloadIncrement > 0 ? downloadIncrement : 0;

          // 计算实时速度 (bytes/s)
          if (timeDiff > 0) {
            _uploadSpeed = (uploadIncrement / timeDiff).round();
            _downloadSpeed = (downloadIncrement / timeDiff).round();
          }

          // 更新历史数据
          _lastUploadBytes = stats['uploadTotal'] as int;
          _lastDownloadBytes = stats['downloadTotal'] as int;
        }
      }
    } catch (e) {
      // 静默处理错误，避免影响UI更新
      debugPrint('从守护进程获取流量统计失败: $e');
    }
  }

  /// Directly update traffic statistics from Clash API
  Future<void> _updateTrafficFromClashAPI() async {
    // If WS real-time stream is enabled, do not execute HTTP polling to avoid duplicate statistics
    if (_clashStreamActive && _clashTrafficSocket != null) return;
    try {
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      client.connectionTimeout = const Duration(seconds: 2);

      final request = await client.get('127.0.0.1', _clashApiPort, '/traffic');
      if (_clashApiSecret.isNotEmpty) {
        request.headers.add('Authorization', 'Bearer $_clashApiSecret');
      }

      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      if (response.statusCode == 200) {
        final data = await response.transform(utf8.decoder).join();
        final lines = data
            .trim()
            .split('\n')
            .where((line) => line.isNotEmpty)
            .toList();

        if (lines.isNotEmpty) {
          // Take the last line of data
          final lastLine = lines.last;
          final stats = json.decode(lastLine) as Map<String, dynamic>;

          final now = DateTime.now();
          final timeDiff = now.difference(_lastUpdateTime).inSeconds;

          final currentUpload = stats['up'] as int;
          final currentDownload = stats['down'] as int;

          if (timeDiff > 0 && _lastUploadBytes > 0) {
            // Calculate increment and speed
            final uploadIncrement = currentUpload - _lastUploadBytes;
            final downloadIncrement = currentDownload - _lastDownloadBytes;

            _uploadBytes += uploadIncrement > 0 ? uploadIncrement : 0;
            _downloadBytes += downloadIncrement > 0 ? downloadIncrement : 0;

            _uploadSpeed = uploadIncrement > 0
                ? (uploadIncrement / timeDiff).round()
                : 0;
            _downloadSpeed = downloadIncrement > 0
                ? (downloadIncrement / timeDiff).round()
                : 0;
          }

          _lastUploadBytes = currentUpload;
          _lastDownloadBytes = currentDownload;
        }
      }
      client.close();
    } catch (e) {
      // Silently handle errors to avoid affecting UI updates
      debugPrint('Failed to get traffic statistics from Clash API: $e');
    }
  }

  // ========= Clash API WebSocket 实时流量 =========
  Future<void> _openClashTrafficStream() async {
    if (_clashStreamActive || _clashTrafficSocket != null) return;
    if (!_enableClashApi) return;
    if (_clashTriedStream && !_isConnected) return;
    if (!_isConnected) return;
    _clashTriedStream = true;
    final url = 'ws://127.0.0.1:$_clashApiPort/traffic';
    try {
      _addLog('ClashWS: 尝试连接 $url');
      final headers = <String, dynamic>{};
      if (_clashApiSecret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_clashApiSecret';
      }
      _clashTrafficSocket = await WebSocket.connect(url, headers: headers);
      _clashStreamActive = true;
      _clashLastFrameTime = null;
      _clashLastUp = null;
      _clashLastDown = null;
      _clashWsInterpretAsSpeed = true;
      _addLog('ClashWS: 连接成功 (实时流量)');
      // 帧聚合窗口
      const int _wsAggregateWindowMs = 220;
      int _aggUp = 0;
      int _aggDown = 0;
      DateTime _aggStart = DateTime.now();
      void _flushAgg({bool force = false}) {
        final now = DateTime.now();
        final dt = now.difference(_aggStart).inMilliseconds;
        if ((dt >= _wsAggregateWindowMs && (_aggUp > 0 || _aggDown > 0)) ||
            force) {
          if (dt > 0) {
            _recordSpeedSample(_aggUp, _aggDown, dt);
          }
          _aggUp = 0;
          _aggDown = 0;
          _aggStart = now;
          _scheduleNotify();
        }
      }

      _clashTrafficSub = _clashTrafficSocket!.listen(
        (event) {
          try {
            if (event is String) {
              final data = jsonDecode(event) as Map<String, dynamic>;
              final up = data['up'] as int?; // 累计或增量上传
              final down = data['down'] as int?; // 累计或增量下载
              if (up == null || down == null) return;
              final now = DateTime.now();
              if (_clashLastFrameTime == null) {
                _clashLastFrameTime = now;
                _clashLastUp = up;
                _clashLastDown = down;
                if (!_clashWsInterpretAsSpeed) {
                  _uploadBytes = up;
                  _downloadBytes = down;
                }
                _scheduleNotify();
                return;
              }
              final dtMs = now.difference(_clashLastFrameTime!).inMilliseconds;
              if (dtMs <= 0) return;
              final lastUp = _clashLastUp ?? up;
              final lastDown = _clashLastDown ?? down;
              if (_clashWsInterpretAsSpeed &&
                  (up > 64 * 1024 * 1024 || down > 64 * 1024 * 1024)) {
                _clashWsInterpretAsSpeed = false;
                _addLog('ClashWS: 检测到数值超过4MB，切换为累计模式');
                _uploadBytes = up;
                _downloadBytes = down;
              }
              int upDeltaBytes;
              int downDeltaBytes;
              if (_clashWsInterpretAsSpeed) {
                upDeltaBytes = (up * dtMs / 1000).round();
                downDeltaBytes = (down * dtMs / 1000).round();
                if (upDeltaBytes > 0) _uploadBytes += upDeltaBytes;
                if (downDeltaBytes > 0) _downloadBytes += downDeltaBytes;
              } else {
                upDeltaBytes = up - lastUp;
                downDeltaBytes = down - lastDown;
                if (upDeltaBytes < 0 || downDeltaBytes < 0) {
                  _addLog('ClashWS: 累计模式出现回退，跳过本帧并重置基线');
                  _clashLastFrameTime = now;
                  _clashLastUp = up;
                  _clashLastDown = down;
                  return;
                }
                // 防止数据回退：只有当新值大于当前值时才更新
                if (up > _uploadBytes) _uploadBytes = up;
                if (down > _downloadBytes) _downloadBytes = down;
              }
              _aggUp += upDeltaBytes;
              _aggDown += downDeltaBytes;
              _flushAgg();
              _clashLastFrameTime = now;
              _clashLastUp = up;
              _clashLastDown = down;
            }
          } catch (e) {
            debugPrint('ClashWS: 解析消息失败 $e');
          }
        },
        onDone: () {
          _addLog('ClashWS: 连接关闭 code=${_clashTrafficSocket?.closeCode}');
          _flushAgg(force: true);
          _clashStreamActive = false;
          _clashTrafficSocket = null;
          _clashTrafficSub?.cancel();
          _clashTrafficSub = null;
        },
        onError: (err) {
          _addLog('ClashWS: 发生错误 $err');
          _flushAgg(force: true);
          _clashStreamActive = false;
          _clashTrafficSocket = null;
          _clashTrafficSub?.cancel();
          _clashTrafficSub = null;
        },
        cancelOnError: true,
      );
    } catch (e) {
      _addLog('ClashWS: 连接失败 $e (回退 HTTP 轮询)');
      _clashStreamActive = false;
      _clashTrafficSocket = null;
    }
  }

  void _closeClashTrafficStream() {
    try {
      _clashTrafficSub?.cancel();
      _clashTrafficSub = null;
      _clashTrafficSocket?.close();
      _clashTrafficSocket = null;
    } catch (_) {}
    _clashStreamActive = false;
    _clashLastFrameTime = null;
    _clashLastUp = null;
    _clashLastDown = null;
  }

  /// 更新单个连接的实时信息（时长和速度相关）
  Map<String, dynamic> _updateConnectionRealTimeInfo(
    Map<String, dynamic> connection,
  ) {
    final updatedConnection = Map<String, dynamic>.from(connection);
    final connectionId = connection['id'] ?? '';
    final now = DateTime.now();

    // 实时更新连接时长
    if (connection['startTime'] is DateTime) {
      final startTime = connection['startTime'] as DateTime;
      updatedConnection['duration'] = now.difference(startTime);
    } else if (connection['startTime'] == null) {
      // 如果没有开始时间，设置一个（向后兼容）
      final startTime = now.subtract(Duration(minutes: 1)); // 假设已连接1分钟
      updatedConnection['startTime'] = startTime;
      updatedConnection['duration'] = Duration(minutes: 1);
    }

    // 移除系统连接模拟流量：SYSTEM 规则连接不再伪造字节/速度，保持真实（可能为空或无增量）

    // 计算单个连接的速度
    if (connectionId.isNotEmpty) {
      final currentUploadBytes = updatedConnection['uploadBytes'] ?? 0;
      final currentDownloadBytes = updatedConnection['downloadBytes'] ?? 0;

      // 检查是否有历史数据
      if (_connectionHistory.containsKey(connectionId)) {
        final history = _connectionHistory[connectionId]!;
        final lastUploadBytes = history['uploadBytes'] ?? 0;
        final lastDownloadBytes = history['downloadBytes'] ?? 0;
        final lastUpdateTime = history['updateTime'] as DateTime? ?? now;

        // 获取速度历史记录
        final speedHistory =
            history['speedHistory'] as List<Map<String, dynamic>>? ?? [];

        // 计算时间差（毫秒）
        final timeDiff = now.difference(lastUpdateTime).inMilliseconds;

        if (timeDiff > 500) {
          // 最小间隔 500ms，避免频繁计算
          // 计算字节增量
          final uploadIncrement = currentUploadBytes - lastUploadBytes;
          final downloadIncrement = currentDownloadBytes - lastDownloadBytes;

          int uploadSpeed = 0;
          int downloadSpeed = 0;

          // 判断是否为 TUN 模式连接（通过 rule 和 target 判断）。
          // 已移除 isTunConnection 分支，统一使用稳定速度算法

          // 统一使用稳定速度算法（无模拟数据）
          uploadSpeed = _calculateStableSpeed(
            uploadIncrement,
            timeDiff,
            speedHistory,
            'upload',
            connection,
          );
          downloadSpeed = _calculateStableSpeed(
            downloadIncrement,
            timeDiff,
            speedHistory,
            'download',
            connection,
          );

          updatedConnection['uploadSpeed'] = uploadSpeed;
          updatedConnection['downloadSpeed'] = downloadSpeed;

          // 更新速度历史记录（保留最近 10 次记录）
          speedHistory.add({
            'upload': uploadSpeed,
            'download': downloadSpeed,
            'timestamp': now.millisecondsSinceEpoch,
          });
          if (speedHistory.length > 10) {
            speedHistory.removeAt(0);
          }

          // 更新历史记录
          _connectionHistory[connectionId] = {
            'uploadBytes': currentUploadBytes,
            'downloadBytes': currentDownloadBytes,
            'updateTime': now,
            'speedHistory': speedHistory,
          };
        } else {
          // 时间间隔太短，保持之前的速度
          final lastSpeed = speedHistory.isNotEmpty
              ? speedHistory.last
              : {'upload': 0, 'download': 0};
          updatedConnection['uploadSpeed'] = lastSpeed['upload'] ?? 0;
          updatedConnection['downloadSpeed'] = lastSpeed['download'] ?? 0;
        }
      } else {
        // 第一次记录，速度为 0
        updatedConnection['uploadSpeed'] = 0;
        updatedConnection['downloadSpeed'] = 0;

        // 初始化历史记录
        _connectionHistory[connectionId] = {
          'uploadBytes': currentUploadBytes,
          'downloadBytes': currentDownloadBytes,
          'updateTime': now,
          'speedHistory': <Map<String, dynamic>>[],
        };
      }
    }

    return updatedConnection;
  }

  /// 计算稳定的速度值（用于 TUN 模式）
  int _calculateStableSpeed(
    int increment,
    int timeDiff,
    List<Map<String, dynamic>> speedHistory,
    String type, // 'upload' or 'download'
    Map<String, dynamic> connection,
  ) {
    // 如果增量为 0 或负数，检查是否应该保持活跃状态
    if (increment <= 0) {
      // 检查最近的速度历史，如果最近有活动，逐渐衰减速度
      if (speedHistory.isNotEmpty) {
        final recentSpeeds = speedHistory.length > 3
            ? speedHistory
                  .sublist(speedHistory.length - 3)
                  .map((h) => h[type] as int? ?? 0)
                  .toList()
            : speedHistory.map((h) => h[type] as int? ?? 0).toList();
        final avgRecentSpeed =
            recentSpeeds.fold(0, (sum, speed) => sum + speed) /
            recentSpeeds.length;

        if (avgRecentSpeed > 1024) {
          // 如果平均速度超过 1KB/s，逐渐衰减速度（每次乘以 0.8）
          final decayed = (avgRecentSpeed * 0.8).round();
          // 限制返回范围，避免过度衰减或异常值
          return decayed.clamp(0, (avgRecentSpeed * 1).round());
        }
      }
      return 0;
    }

    // 检查是否为异常大的增量：超过阈值视为抖动，采用前一次速度或限制上限
    final maxReasonableIncrement = timeDiff * 10 * 1024; // 对应 ~10MB/s
    if (increment > maxReasonableIncrement) {
      if (speedHistory.isNotEmpty) {
        final last = speedHistory.last[type] as int? ?? 0;
        return last; // 保持上一速度，避免跳变
      }
      // 若无历史，使用阈值上限对应速度
      final capped = ((maxReasonableIncrement * 1000) / timeDiff).round();
      return capped;
    }

    // 计算基础速度（bytes/s）
    final rawSpeed = ((increment * 1000) / timeDiff).round();

    // 使用移动平均平滑速度
    if (speedHistory.isNotEmpty) {
      final recentSpeeds = speedHistory.length > 5
          ? speedHistory
                .sublist(speedHistory.length - 5)
                .map((h) => h[type] as int? ?? 0)
                .toList()
          : speedHistory.map((h) => h[type] as int? ?? 0).toList();
      recentSpeeds.add(rawSpeed);

      // 计算加权移动平均（最新值权重更高）
      int weightedSum = 0;
      int totalWeight = 0;
      for (int i = 0; i < recentSpeeds.length; i++) {
        final weight = i + 1; // 权重递增
        weightedSum += recentSpeeds[i] * weight;
        totalWeight += weight;
      }

      final smoothedSpeed = totalWeight > 0
          ? (weightedSum ~/ totalWeight)
          : rawSpeed;

      // 限制速度在合理范围内
      return smoothedSpeed.clamp(
        0,
        type == 'upload' ? 5 * 1024 * 1024 : 20 * 1024 * 1024,
      );
    }

    // 第一次计算，限制在合理范围内
    return rawSpeed.clamp(
      0,
      type == 'upload' ? 5 * 1024 * 1024 : 20 * 1024 * 1024,
    );
  }

  // _generateRealisticSpeed 和 _simulateSystemConnectionTraffic 已移除（去除模拟显示逻辑）

  /// 生成/更新连接数据（优先使用真实数据）
  DateTime _lastConnectionsFetch = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _connectionsFetchIntervalMs = 3000; // 3s 节流

  Future<void> _updateConnectionsData({
    bool updateGlobalSpeed = true,
    bool force = false,
  }) async {
    try {
      final now = DateTime.now();
      if (!force &&
          now.difference(_lastConnectionsFetch).inMilliseconds <
              _connectionsFetchIntervalMs) {
        return;
      }
      final stats = await ConnectionStatsService.getConnectionStats(
        clashApiPort: _clashApiPort,
        clashApiSecret: _clashApiSecret,
      );
      _lastConnectionsFetch = DateTime.now();

      if (stats != null && stats.connections.isNotEmpty) {
        // 使用真实连接数据并计算实时信息
        // _addLog(
        //   '连接数据更新: 成功获取 ${stats.connections.length} 个连接 (来源: ${stats.source})',
        // );
        _connections = stats.connections
            .map((conn) => _updateConnectionRealTimeInfo(conn.toDisplayMap()))
            .toList();
        // 限制列表大小，防止长期运行增长
        const int maxConnections = 500;
        if (_connections.length > maxConnections) {
          _connections = _connections.sublist(0, maxConnections);
        }
        _connectionSource = stats.source;
        _activeConnections = _connections.length;

        // 计算真实流量统计
        final totalUpload = stats.connections.totalUploadBytes;
        final totalDownload = stats.connections.totalDownloadBytes;

        if (totalUpload > 0 || totalDownload > 0) {
          // 计算速度（基于字节增量和时间差）仅在需要并且没有 WS 实时流时执行
          if (updateGlobalSpeed && !_clashStreamActive) {
            final now = DateTime.now();
            final dt = now.difference(_lastUpdateTime).inMilliseconds;
            if (dt > 0 && (_lastUploadBytes > 0 || _lastDownloadBytes > 0)) {
              final upInc = totalUpload - _lastUploadBytes;
              final downInc = totalDownload - _lastDownloadBytes;
              _uploadSpeed = ((upInc * 1000) / dt).round();
              _downloadSpeed = ((downInc * 1000) / dt).round();
            }
          }
          // 更新累计字节（防止回退，只在新值更大时更新）
          if (totalUpload > _uploadBytes) _uploadBytes = totalUpload;
          if (totalDownload > _downloadBytes) _downloadBytes = totalDownload;
          _lastUploadBytes = totalUpload;
          _lastDownloadBytes = totalDownload;
        }
      } else {
        // 如果连接中但没有真实数据，记录日志并保持空列表
        if (_isConnected && _connections.isEmpty) {
          _addLog('连接数据更新: 无法获取连接数据 (Clash API 可能未启用或端口错误)');
        } else if (_connections.isNotEmpty) {
          // 如果没有真实数据，但有已存在的连接，更新它们的实时信息
          // _addLog('连接数据更新: 使用已存在的 ${_connections.length} 个连接数进行更新');
          _connections = _connections
              .map((conn) => _updateConnectionRealTimeInfo(conn))
              .toList();
        }
      }

      _scheduleNotify();
    } catch (e) {
      print('更新连接数据失败: $e');

      // 如果连接中但没有连接数据，记录错误信息
      if (_isConnected && _connections.isEmpty) {
        _addLog('错误: 连接统计获取失败: $e');
      } else if (_connections.isNotEmpty) {
        // 错误时更新已有连接的实时信息
        _connections = _connections
            .map((conn) => _updateConnectionRealTimeInfo(conn))
            .toList();
        notifyListeners();
      }
    }
  }

  /// 设置流量统计方式
  Future<void> setUseImprovedTrafficStats(bool useImproved) async {
    if (_useImprovedTrafficStats == useImproved) return;

    final wasConnected = _isConnected;

    // 如果正在连接，先停止统计
    if (wasConnected) {
      _stopTrafficStatsTimer();
    }

    _useImprovedTrafficStats = useImproved;

    // 保存设置
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_improved_traffic_stats', useImproved);

    // 如果之前已连接，重启统计
    if (wasConnected) {
      _startTrafficStatsTimer();
    }

    notifyListeners();
  }

  /// 重置当前连接流量统计（保留会话级累计）
  void resetTrafficStats() {
    // 重置改进的流量统计服务
    if (_useImprovedTrafficStats) {
      _improvedTrafficService.reset();
    }

    // 重置当前连接的统计（不累加到会话总计，因为_stopTrafficStatsTimer已经处理了）
    _uploadBytes = 0;
    _downloadBytes = 0;
    _uploadSpeed = 0;
    _downloadSpeed = 0;
    _lastUploadBytes = 0;
    _lastDownloadBytes = 0;
    _connectionDuration = Duration.zero;
    _connectionStartTime = null;
    _lastUpdateTime = DateTime.now();
    _activeConnections = 0;
    _connections.clear();
    _connectionHistory.clear(); // 清空连接历史记录
    notifyListeners();
  }

  /// 完全重置所有流量统计（包括会话级累计）
  Future<void> resetAllTrafficStats() async {
    _uploadBytes = 0;
    _downloadBytes = 0;
    _uploadSpeed = 0;
    _downloadSpeed = 0;
    _lastUploadBytes = 0;
    _lastDownloadBytes = 0;
    _sessionTotalUploadBytes = 0;
    _sessionTotalDownloadBytes = 0;
    _connectionDuration = Duration.zero;
    _connectionStartTime = null;
    _lastUpdateTime = DateTime.now();
    _activeConnections = 0;
    _connections.clear();
    _connectionHistory.clear();

    // 清除持久化存储中的会话级流量统计
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_total_upload');
      await prefs.remove('session_total_download');
    } catch (e) {
      debugPrint('清除会话流量统计失败: $e');
    }

    notifyListeners();
  }

  /// 格式化字节数为可读字符串
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// 格式化速度为可读字符串
  static String formatSpeed(int bytesPerSecond) {
    return '${formatBytes(bytesPerSecond)}/s';
  }

  /// 格式化连接时长为可读字符串
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours.toString().padLeft(1, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    // 停止流量统计定时器
    _stopTrafficStatsTimer();
    // 停止延时检测定时器
    _stopPingTimer();
    // 停止状态监控定时器
    _stopStatusMonitor();
    // 清理系统代理：如果当前系统代理是本应用设置的 127.0.0.1:[当前端口/默认端口]，则尝试关闭
    if (_proxyManager.isSupported) {
      try {
        final enabled = _proxyManager.getProxyEnabled();
        final server = _proxyManager.getProxyServer();
        if (enabled && _isOurProxy(server)) {
          _proxyManager.disableProxy();
        }
      } catch (_) {}
    }
    _singBoxService.dispose();
    super.dispose();
  }

  // （已在文件顶部实现 _recordSpeedSample 与 _SpeedSample，此处删除重复实现）

  // ---------------- 内部辅助：系统代理识别 ----------------
  int? _parseLoopbackPort(String server) {
    // 兼容 IE/WinINET 代理字符串，如：
    //   "127.0.0.1:7890"
    //   "http=127.0.0.1:7890;https=127.0.0.1:7890;socks=127.0.0.1:7890"
    final m = RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(server.trim());
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  bool _isOurProxy(String server) {
    final p = _parseLoopbackPort(server);
    if (p == null) return false;
    return p == _localPort || p == _defaultLocalPort;
  }

  /// 使用守护进程模式连接（TUN）
  Future<bool> _connectWithDaemon(VPNConfig config) async {
    try {
      _addLog('CONNECT(daemon): 准备生成 sing-box 配置 useTun=$_useTun');
      // 保持用户选择的 TUN 状态（不再强制开启）
      var singBoxConfig = await config.toSingBoxConfig(
        mode: _proxyMode,
        localPort: _localPort,
        useTun: _useTun,
        tunStrictRoute: _tunStrictRoute,
        preferredTunStack: _singBoxService.preferredTunStack,
        enableClashApi: _enableClashApi,
        clashApiPort: _clashApiPort,
        clashApiSecret: _clashApiSecret,
        enableIpv6: _dnsManager.enableIpv6,
      );
      _addLog(
        'CONNECT(daemon): ClashAPI enable=${_enableClashApi} port=${_clashApiPort}',
      );

      // 防御性修正：若出现误拼写 experimmental -> experimental
      if (singBoxConfig.containsKey('experimmental')) {
        _addLog("CONNECT(daemon): 发现 'experimmental' -> 自动更正为 'experimental'");
        // 不要覆盖已有 experimental
        singBoxConfig.putIfAbsent(
          'experimental',
          () => singBoxConfig['experimmental'],
        );
        singBoxConfig.remove('experimmental');
      }

      // 如果 clash_api 已被之前回退禁用但用户希望强制启用，可在外部调用 forceReenableClashApi
      if (!_enableClashApi) {
        _addLog(
          'CONNECT(daemon): 当前 enableClashApi=false — 不会注入 clash_api；如需启用请调用 forceReenableClashApi()',
        );
      }

      // 如果启用 clash_api 且 experimental 键缺失，补一个空结构以便注入
      if (_enableClashApi && !singBoxConfig.containsKey('experimental')) {
        _addLog('CONNECT(daemon): 缺少 experimental 键，自动补充一个 Map');
        singBoxConfig['experimental'] = <String, dynamic>{};
      }

      // 再次确认 clash_api 注入（理论上 toSingBoxConfig 已做，但给出冗余保障）
      if (_enableClashApi) {
        try {
          final exp = (singBoxConfig['experimental'] as Map<String, dynamic>);
          exp.putIfAbsent(
            'clash_api',
            () => {
              'external_controller': '127.0.0.1:$_clashApiPort',
              'secret': _clashApiSecret,
            },
          );
        } catch (e) {
          _addLog('CONNECT(daemon): 再次注入 clash_api 失败: $e');
        }
      }

      // 写出发送前最终配置（便于诊断 9090 未监听）
      try {
        final encoder = const JsonEncoder.withIndent('  ');
        final path =
            '${Directory.systemTemp.path}/gsou_config_daemon_final.json';
        await File(path).writeAsString(encoder.convert(singBoxConfig));
        _addLog('CONNECT(daemon): 最终配置写出 $path');
      } catch (e) {
        _addLog('CONNECT(daemon): 写出最终配置失败 $e');
      }
      if (_useTun) {
        try {
          final inb =
              (singBoxConfig['inbounds'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
          final tun = inb.firstWhere(
            (e) => e['type'] == 'tun',
            orElse: () => const {},
          );
          if (tun.isEmpty) {
            _addLog('诊断(daemon): 生成阶段未发现 TUN inbound (useTun=true)');
          } else {
            _addLog(
              '诊断(daemon): 生成阶段包含 TUN inbound stack=${tun['stack']} mtu=${tun['mtu']} auto_route=${tun['auto_route']}',
            );
          }
        } catch (e) {
          _addLog('诊断(daemon): 检查 TUN inbound 时异常 $e');
        }
      }
      List inboundList = (singBoxConfig['inbounds'] as List?) ?? [];
      final hasTun = inboundList.any((e) => e is Map && e['type'] == 'tun');
      if (!hasTun && _useTun) {
        _addLog('诊断(daemon): useTun=true 但配置缺少 TUN inbound -> 注入补丁');
        inboundList = List.from(inboundList);
        inboundList.insert(0, {
          'tag': 'tun-in',
          'type': 'tun',
          if (Platform.isWindows) 'interface_name': 'Gsou Adapter Tunnel',
          'address': ['172.19.0.1/30'],
          'mtu': 4064,
          'auto_route': true,
          'strict_route': _tunStrictRoute,
          'stack': Platform.isWindows ? 'system' : 'system',
        });
        singBoxConfig['inbounds'] = inboundList;
        try {
          final encoder = const JsonEncoder.withIndent('  ');
          final tmp = File(
            '${Directory.systemTemp.path}/gsou_config_after_inject_daemon.json',
          );
          await tmp.writeAsString(encoder.convert(singBoxConfig));
          _addLog('TUN 注入（daemon）配置已写出 ${tmp.path}');
        } catch (e) {
          _addLog('写出注入（daemon）配置失败: $e');
        }
      } else {
        _addLog(
          '诊断(daemon): 已检测到 TUN inbound=${hasTun} inbounds=${inboundList.length}',
        );
      }
      _addLog('CONNECT(daemon): 配置生成完成, inbounds=${inboundList.length}');

      // 与守护进程交互创建 TUN
      bool ok = await _vpnManager.startVPN(singBoxConfig);
      if (!ok && _enableClashApi) {
        _addLog('CONNECT(daemon): 启动失败，尝试关闭 Clash API 回退重试');
        // 构建去掉 clash_api 的配置再试一遍
        singBoxConfig = await config.toSingBoxConfig(
          mode: _proxyMode,
          localPort: _localPort,
          useTun: _useTun,
          tunStrictRoute: _tunStrictRoute,
          preferredTunStack: _singBoxService.preferredTunStack,
          enableClashApi: false,
          enableIpv6: _dnsManager.enableIpv6,
        );
        ok = await _vpnManager.startVPN(singBoxConfig);
        if (ok) {
          _addLog('CONNECT(daemon): 关闭 Clash API 后重试成功 -> 自动回退');
          _enableClashApi = false;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('enable_clash_api', false);
          } catch (_) {}
        }
      }
      if (!ok) {
        _addLog('CONNECT(daemon): 守护进程创建 TUN 失败');

        return false;
      }
      _addLog('CONNECT(daemon): 守护进程启动成功，后续获取状态');
      // 输出 experimental.clash_api 注入结果（仅当仍启用）
      try {
        final exp = (singBoxConfig['experimental'] as Map<String, dynamic>?);
        if (exp != null && exp.containsKey('clash_api')) {
          _addLog(
            'CONNECT(daemon): experimental.clash_api 注入 -> ${exp["clash_api"]}',
          );
        } else {
          _addLog(
            'CONNECT(daemon): 未发现 experimental.clash_api (enableClashApi=$_enableClashApi)',
          );
        }
      } catch (e) {
        _addLog('CONNECT(daemon): 检查 clash_api 注入异常: $e');
      }
      try {
        final status = await _vpnManager.diagnosticsClient.quickDiagnostics();
        _addLog('CONNECT(daemon): quickDiagnostics => ${jsonEncode(status)}');
      } catch (e) {
        _addLog('CONNECT(daemon): quickDiagnostics 异常: $e');
      }

      _currentConfig = config;
      _isConnected = true;
      _status = '已连接';
      _sessionViaDaemon = true; // 保持守护进程会话标记，避免本地回调覆盖
      _connectionStartTime = DateTime.now();
      // 守护进程模式启动流量统计和状态监控
      _startTrafficStatsTimer();
      _startStatusMonitor();
      if (_enableClashApi) {
        _openClashTrafficStream();
      }
      // 自动端口探测（Clash API），连接建立后异步验证 9090 /version 是否可达
      if (_enableClashApi) {
        _addLog('CONNECT(daemon): 启动后异步验证 Clash API 端口 $_clashApiPort');
        _verifyClashApiPortOnce();
      } else {
        _addLog('CONNECT(daemon): Clash API 已禁用，跳过端口自动验证');
      }
      _addLog('CONNECT(daemon): 连接成功');
      notifyListeners();
      return true;
    } catch (e) {
      _addLog('CONNECT(daemon) 异常: $e');
      return false;
    }
  }

  // ---------------- Clash API 端口自动验证 ----------------
  // (字段已前置声明 bool _clashApiAutoRetried)
  Future<void> _verifyClashApiPortOnce() async {
    // 延迟 1s 等待 sing-box 初始化
    await Future.delayed(const Duration(seconds: 1));
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final uri = Uri.parse('http://127.0.0.1:$_clashApiPort/version');
      final req = await client.getUrl(uri);
      final resp = await req.close();
      final text = await resp.transform(const Utf8Decoder()).join();
      if (resp.statusCode == 200) {
        _addLog('ClashAPI探测: 端口=$_clashApiPort OK version=$text');
        return;
      }
      _addLog('ClashAPI探测: 非 200 状态 code=${resp.statusCode} body=$text');
    } catch (e) {
      _addLog('ClashAPI探测: 请求失败 $e');
    }
    if (!_clashApiAutoRetried && _enableClashApi) {
      _clashApiAutoRetried = true;
      _addLog('ClashAPI 探测失败，尝试自动重试一次');
      // 自动快速重连一次（禁用->再启用）
      try {
        await disconnect();
        // 强制 re-enable（即便标志仍为 true，走一个刷新流程）
        _enableClashApi = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('enable_clash_api', true);
        await connect(_currentConfig!);
      } catch (e) {
        _addLog('ClashAPI探测: 自动重试流程异常 $e');
      }
    } else {
      if (!_enableClashApi) {
        _addLog('ClashAPI 探测: 已被禁用，跳过自动重试');
      } else {
        _addLog('ClashAPI 探测: 已尝试自动重试或不符合重试条件，停止重试');
      }
    }
  }

  /// 测试方法：手动创建 PAC 文件
  Future<void> testCreatePacFiles() async {
    _addLog('开始测试创建 PAC 文件...');
    final success = await _pacManager.createSamplePacFiles();
    if (success) {
      _addLog('创建 PAC 文件成功');
    } else {
      _addLog('创建 PAC 文件失败');
    }
  }

  /// 测试方法：测试 GFWList PAC 文件加载
  void testGfwListPac() {
    _addLog('🔍 测试 GFWList PAC 文件加载...');
    final gfwContent = _pacManager.loadCustomPacFile(
      'D:\\TEMP\\VPN\\sing_box_vpn\\gfwlist.pac',
      _localPort,
    );
    if (gfwContent != null) {
      _addLog('GFWList PAC 文件读取成功');
      // 检查端口是否正确替换
      if (gfwContent.contains('127.0.0.1:$_localPort')) {
        _addLog('端口替换正确');
      } else {
        _addLog('端口替换不正确');
      }
    } else {
      _addLog('读取 GFWList PAC 文件失败');
    }
  }

  // ================ 延时管理相关方法 ================

  /// 启动延时检测定时器（每 N 分钟自动检测一次）
  void _startPingTimer() {
    _stopPingTimer(); // 确保只有一个定时器

    // 启动时立即检测一次
    if (_configs.isNotEmpty) {
      _pingAllConfigs();
    }

    // 设置定时器，使用可调间隔时间执行
    _pingTimer = Timer.periodic(Duration(minutes: _pingIntervalMinutes), (
      timer,
    ) {
      if (_configs.isNotEmpty) {
        _pingAllConfigs();
      }
    });
  }

  /// 停止延时检测定时器
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// 检测所有配置的延时
  Future<void> _pingAllConfigs() async {
    if (_isPingingAll || _configs.isEmpty) return;

    _isPingingAll = true;
    notifyListeners();

    try {
      _addLog('开始检测所有服务器延时 (共 ${_configs.length} 个，智能并发)...');

      int lastNotify = DateTime.now().millisecondsSinceEpoch;
      int successCount = 0;
      final total = _configs.length;

      await PingService.pingConfigsWithProgress(
        _configs,
        isConnected: _isConnected,
        currentConfig: _currentConfig,
        onEach: (cfg, ping) {
          _configPings[cfg.id] = ping;
          if (ping > 0) successCount++;
          final now = DateTime.now().millisecondsSinceEpoch;
          // 节流 UI 刷新：约 120ms 或完成时通知
          if (now - lastNotify > 120 || successCount == total) {
            lastNotify = now;
            notifyListeners();
          }
        },
        onProgress: (done, total) {
          if (done == total) {
            _addLog('延时检测完成: $successCount/$total 个服务器可达');
          } else if (done % 10 == 0) {
            _addLog('进度: $done/$total');
          }
        },
      );

      // 延时检测完成后，尝试自动选择最佳服务器
      if (_autoSelectBestServer) {
        await _autoSelectBestServerInternal();
      }
    } catch (e) {
      _addLog('延时检测失败: $e');
    } finally {
      _isPingingAll = false;
      notifyListeners();
    }
  }

  /// 检测单个配置的延时
  Future<void> _pingSingleConfig(VPNConfig config) async {
    try {
      final ping = await PingService.pingConfig(config, isConnected: _isConnected, currentConfig: _currentConfig);
      _configPings[config.id] = ping;
      notifyListeners();

      if (ping > 0) {
        _addLog('${config.name} 延时: ${PingService.formatPing(ping)}');
      } else {
        _addLog('${config.name} 连接超时');
      }
    } catch (e) {
      _addLog('检测 ${config.name} 延时失败: $e');
    }
  }

  /// 手动刷新所有配置的延时
  Future<void> refreshAllPings() async {
    await _pingAllConfigs();
  }

  /// 启动连接状态监控定时器
  void _startStatusMonitor() {
    _stopStatusMonitor(); // 确保只有一个定时器

    // 每 10 秒检查一次状态
    _statusMonitorTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkConnectionStatus();
    });

    // 立即检查一次
    _checkConnectionStatus();
  }

  /// 停止连接状态监控定时器
  void _stopStatusMonitor() {
    _statusMonitorTimer?.cancel();
    _statusMonitorTimer = null;
  }

  /// 检查连接状态是否与实际运行状态一致
  void _checkConnectionStatus() {
    try {
      bool actualRunning = false;

      if (_sessionViaDaemon) {
        // 守护进程模式：这里可以添加检查守护进程状态的逻辑
        // 暂时跳过，保持当前状态
        return;
      } else {
        // 本地模式：检查 sing-box 是否真正在运行
        actualRunning = _singBoxService.isRunning;
      }

      // 如果状态不一致，自动同步
      if (_isConnected != actualRunning) {
        _addLog(
          '检测到状态不一致 UI显示=${_isConnected ? "已连接" : "未连接"}, 实际运行=${actualRunning ? "运行中" : "已停止"}',
        );

        if (!actualRunning && _isConnected) {
          // sing-box 已停止但 UI 显示连接中，更新为断开状态
          _addLog('sing-box 已停止，自动同步为断开状态');
          _isConnected = false;
          _status = '连接已断开';
          // _currentConfig = null; // 保留当前配置，不要清除
          _connectionStartTime = null;
          _stopTrafficStatsTimer();
          // 注意：不停止状态监控，继续监控以便检测恢复

          // 清理系统代理
          if (_proxyManager.isSupported) {
            final enabled = _proxyManager.getProxyEnabled();
            final server = _proxyManager.getProxyServer();
            if (enabled &&
                (_isOurProxy(server) || server.contains(_pacManager.pacUrl))) {
              _proxyManager.disableProxy().then((ok) {
                if (ok) _addLog('已清理系统代理设置');
              });
            }
          }

          // 停止 PAC 服务
          _pacManager.stopPacServer();

          notifyListeners();
        } else if (actualRunning && !_isConnected) {
          // sing-box 在运行但 UI 显示未连接（这种情况较少见，但也需要处理）
          _addLog('检测到 sing-box 正在运行但 UI 状态未同步，已标记为已连接');
          _isConnected = true;
          _status = '已连接';
          // 注意：这里不恢复 _currentConfig，因为我们不知道具体连接的是哪个配置
          notifyListeners();
        }
      }
    } catch (e) {
      // 静默处理异常，避免影响正常使用
      _addLog('状态监控检查异常: $e');
    }
  }

  /// 手动刷新单个配置的延时
  Future<void> refreshConfigPing(VPNConfig config) async {
    await _pingSingleConfig(config);
  }

  /// 获取配置的延时
  int getConfigPing(String configId) {
    return _configPings[configId] ?? -1;
  }

  /// 获取配置的延时文本
  String getConfigPingText(String configId) {
    final ping = getConfigPing(configId);
    return PingService.formatPing(ping);
  }

  /// 获取配置的延时等级
  PingLevel getConfigPingLevel(String configId) {
    final ping = getConfigPing(configId);
    return PingService.getPingLevel(ping);
  }

  /// 根据延时排序配置
  List<VPNConfig> get configsSortedByPing {
    final configsWithPing = _configs
        .map((config) => {'config': config, 'ping': getConfigPing(config.id)})
        .toList();

    // 排序：延时从小到大，超时的放在最后
    configsWithPing.sort((a, b) {
      final pingA = a['ping'] as int;
      final pingB = b['ping'] as int;

      // 超时的排在后面
      if (pingA < 0 && pingB >= 0) return 1;
      if (pingB < 0 && pingA >= 0) return -1;
      if (pingA < 0 && pingB < 0) return 0;

      return pingA.compareTo(pingB);
    });

    return configsWithPing.map((item) => item['config'] as VPNConfig).toList();
  }

  /// 设置自动选择最佳服务器
  Future<void> setAutoSelectBestServer(bool enabled) async {
    _autoSelectBestServer = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_select_best_server', enabled);
    } catch (_) {}
    _addLog('自动选择最佳服务器: ${enabled ? '已启用' : '已关闭'}');
    notifyListeners();
  }

  /// 设置延时检测间隔时间
  Future<void> setPingIntervalMinutes(int minutes) async {
    if (minutes < 1 || minutes > 60) return; // 限制 1-60 分钟之间

    _pingIntervalMinutes = minutes;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ping_interval_minutes', minutes);
    } catch (_) {}

    // 重启定时器以使用新的间隔时间
    _startPingTimer();

    _addLog('延时检测间隔: $minutes 分钟');
    notifyListeners();
  }

  /// 自动选择延时最好的服务器内部实现
  Future<void> _autoSelectBestServerInternal() async {
    if (!_autoSelectBestServer || _configs.isEmpty) {
      return;
    }

    // 获取延时排序后的配置列表
    final sortedConfigs = configsSortedByPing;

    // 找到第一个有效延时的配置（延时 >= 0）
    VPNConfig? bestConfig;
    for (final config in sortedConfigs) {
      final ping = getConfigPing(config.id);
      if (ping >= 0) {
        bestConfig = config;
        break;
      }
    }

    if (bestConfig != null && bestConfig.id != _currentConfig?.id) {
      _addLog(
        '自动选择最佳服务器: ${bestConfig.name} (${getConfigPingText(bestConfig.id)})',
      );

      // 仅更新当前配置，不强制断开重连
      _currentConfig = bestConfig;

      // 保存当前配置ID到 SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('current_config_id', bestConfig.id);
      } catch (e) {
        _addLog('保存当前配置失败: $e');
      }

      notifyListeners();

      // 只记录检测到更优服务器，但不自动切换连接
      // 用户下次手动连接时会使用新的最佳服务器
      if (_isConnected) {
        _addLog('检测到更优服务器 ${bestConfig.name}，下次连接时将自动使用');
      }
    }
  }

  /// 更新系统代理状态缓存
  void _updateSystemProxyStatus() {
    final oldEnabled = _systemProxyEnabled;
    final oldServer = _systemProxyServer;

    if (_proxyManager.isSupported) {
      try {
        _systemProxyEnabled = _proxyManager.getProxyEnabled();
        _systemProxyServer = _proxyManager.getProxyServer();
        // _addLog(
        //   'DEBUG: 系统代理状态更改 - 启用: $oldEnabled -> $_systemProxyEnabled, 服务: $oldServer -> $_systemProxyServer',
        // );
      } catch (e) {
        _addLog('更新系统代理状态失败: $e');
        _systemProxyEnabled = false;
        _systemProxyServer = '';
      }
    } else {
      _systemProxyEnabled = false;
      _systemProxyServer = '';
    }

    // 如果状态发生变化，通知 UI 更新
    if (oldEnabled != _systemProxyEnabled || oldServer != _systemProxyServer) {
      _addLog('DEBUG: 系统代理状态改变，通知 UI 更新');
      notifyListeners();
    }
  }
}
