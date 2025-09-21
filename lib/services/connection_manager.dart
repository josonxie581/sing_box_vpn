import 'dart:async';
import 'dart:io';
import '../models/vpn_config.dart';
import '../models/proxy_mode.dart';
import 'singbox_native_service.dart';
import 'improved_traffic_stats_service.dart';
import 'dns_manager.dart';
import 'windows_proxy_manager.dart';
import 'ping_service.dart';
import '../utils/privilege_manager.dart';

/// 连接状态
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// VPN连接管理服务
class ConnectionManager {
  static final ConnectionManager _instance = ConnectionManager._internal();
  factory ConnectionManager() => _instance;
  ConnectionManager._internal();

  // 服务依赖
  final SingBoxNativeService _singBoxService = SingBoxNativeService();
  final ImprovedTrafficStatsService _trafficService =
      ImprovedTrafficStatsService();
  final DnsManager _dnsManager = DnsManager();
  final WindowsProxyManager _proxyManager = WindowsProxyManager();

  // 连接状态
  ConnectionStatus _status = ConnectionStatus.disconnected;
  VPNConfig? _currentConfig;
  String _statusMessage = '未连接';
  final List<String> _logs = [];
  DateTime? _connectionStartTime;

  // 连接设置
  ProxyMode _proxyMode = ProxyMode.rule;
  bool _useTun = false;
  bool _tunStrictRoute = false;
  int _localPort = 0; // 将在 init() 中从 DnsManager 获取实际配置值
  bool _autoSystemProxy = false;
  bool _enableClashApi = true;
  int _clashApiPort = 9090;
  String _clashApiSecret = '';

  // Getters
  ConnectionStatus get status => _status;
  VPNConfig? get currentConfig => _currentConfig;
  String get statusMessage => _statusMessage;
  List<String> get logs => _logs;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isConnecting => _status == ConnectionStatus.connecting;
  bool get isDisconnecting => _status == ConnectionStatus.disconnecting;
  DateTime? get connectionStartTime => _connectionStartTime;

  ProxyMode get proxyMode => _proxyMode;
  bool get useTun => _useTun;
  bool get tunStrictRoute => _tunStrictRoute;
  int get localPort => _localPort;
  bool get autoSystemProxy => _autoSystemProxy;
  bool get enableClashApi => _enableClashApi;
  int get clashApiPort => _clashApiPort;
  String get clashApiSecret => _clashApiSecret;

  // 流量统计 Getters (从 ImprovedTrafficStatsService 获取)
  int get uploadBytes => _trafficService.currentData.totalUploadBytes;
  int get downloadBytes => _trafficService.currentData.totalDownloadBytes;
  int get uploadSpeed => _trafficService.currentData.uploadSpeed;
  int get downloadSpeed => _trafficService.currentData.downloadSpeed;

  /// 初始化
  Future<void> init() async {
    await _dnsManager.init();
    _localPort = _dnsManager.localPort;
    _tunStrictRoute = _dnsManager.strictRoute;

    _singBoxService.onLog = (log) {
      _addLog(log);
    };

    _singBoxService.onStatusChanged = (running) {
      if (running) {
        _updateStatus(ConnectionStatus.connected, '已连接');
      } else if (_status == ConnectionStatus.connected) {
        _updateStatus(ConnectionStatus.disconnected, '未连接');
      }
    };
  }

  /// 连接VPN
  Future<bool> connect(VPNConfig config) async {
    if (_status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.connected) {
      return false;
    }

    _updateStatus(ConnectionStatus.connecting, '正在连接...');
    _currentConfig = config;

    try {
      // 运行时探测 IPv6 能力（仅在用户打开 IPv6 选项时才有意义）
      bool effectiveIpv6 = false;
      if (_dnsManager.enableIpv6) {
        // 用户请求启用 IPv6, 进行运行时探测, 若失败则自动降级并仅使用 IPv4
        final ok = await _dnsManager.detectIpv6Support();
        effectiveIpv6 = ok;
        if (!ok) {
          _addLog('IPv6 探测失败：将按 IPv4 模式运行');
        } else {
          _addLog('IPv6 探测成功：将启用 IPv6 地址');
        }
      }

      // 检查TUN权限
      if (_useTun && Platform.isWindows) {
        final isElevated = PrivilegeManager.instance.isElevated();
        if (!isElevated) {
          _updateStatus(ConnectionStatus.error, '需要管理员权限以启用 TUN');
          return false;
        }
      }

      // 分配端口
      final allocatedPort = await _allocateLocalPort(preferred: _localPort);
      if (allocatedPort == null) {
        _updateStatus(ConnectionStatus.error, '无法分配本地端口');
        return false;
      }
      _localPort = allocatedPort;

      // 生成配置
      final singBoxConfig = await config.toSingBoxConfig(
        mode: _proxyMode,
        localPort: _localPort,
        useTun: _useTun,
        tunStrictRoute: _tunStrictRoute,
        preferredTunStack: _singBoxService.preferredTunStack,
        enableClashApi: _enableClashApi,
        clashApiPort: _clashApiPort,
        clashApiSecret: _clashApiSecret,
        enableIpv6: effectiveIpv6,
      );

      // 启动服务
      final started = await _singBoxService.start(singBoxConfig);
      if (started) {
        _connectionStartTime = DateTime.now();
        _updateStatus(ConnectionStatus.connected, '已连接');

        // 配置 PingService 使用 Clash API
        PingService.setApiConfig(
          host: '127.0.0.1',
          port: _clashApiPort,
          secret: _clashApiSecret,
        );

        // 启动流量统计
        _trafficService.start(
          clashApiPort: _clashApiPort,
          clashApiSecret: _clashApiSecret,
          enableClashApi: _enableClashApi,
        );

        // 设置系统代理
        if (_autoSystemProxy && !_useTun) {
          await enableSystemProxy();
        }

        return true;
      } else {
        _updateStatus(ConnectionStatus.error, '连接失败');
        return false;
      }
    } catch (e) {
      _addLog('连接失败: $e');
      _updateStatus(ConnectionStatus.error, '连接失败');
      return false;
    }
  }

  /// 断开连接
  Future<bool> disconnect() async {
    if (_status == ConnectionStatus.disconnecting ||
        _status == ConnectionStatus.disconnected) {
      return false;
    }

    print("[DEBUG] 尝试断开VPN");

    _updateStatus(ConnectionStatus.disconnecting, '正在断开...');

    try {
      // 停止流量统计
      _trafficService.stop();

      // 停止服务
      final success = await _singBoxService.stop();

      if (success) {
        // 关闭系统代理
        if (_proxyManager.isSupported) {
          await _proxyManager.disableProxy();
        }

        // 注意：_currentConfig 的清空现在在 _updateStatus 中统一处理
        _updateStatus(ConnectionStatus.disconnected, '未连接');
        return true;
      } else {
        _updateStatus(ConnectionStatus.error, '断开失败');
        return false;
      }
    } catch (e) {
      _addLog('断开失败: $e');
      _updateStatus(ConnectionStatus.error, '断开失败');
      return false;
    }
  }

  /// 设置代理模式
  void setProxyMode(ProxyMode mode) {
    _proxyMode = mode;
  }

  /// 重新加载当前配置（用于切换代理模式等需要生效新的路由规则的场景）
  /// 简单实现：若已连接则平滑重启 sing-box （尽量保持端口不变）
  Future<bool> reloadCurrentConfig() async {
    if (!isConnected || _currentConfig == null) {
      return false;
    }
    _addLog('正在重载配置以应用新的模式: ${_proxyMode.name}');
    try {
      bool effectiveIpv6 = false;
      if (_dnsManager.enableIpv6) {
        final ok = await _dnsManager.detectIpv6Support();
        effectiveIpv6 = ok;
        if (!ok) {
          _addLog('IPv6 探测失败(重载)：继续按 IPv4 模式');
        } else {
          _addLog('IPv6 探测成功(重载)：启用 IPv6');
        }
      }
      final cfg = await _currentConfig!.toSingBoxConfig(
        mode: _proxyMode,
        localPort: _localPort,
        useTun: _useTun,
        tunStrictRoute: _tunStrictRoute,
        preferredTunStack: _singBoxService.preferredTunStack,
        enableClashApi: _enableClashApi,
        clashApiPort: _clashApiPort,
        clashApiSecret: _clashApiSecret,
        enableIpv6: effectiveIpv6,
      );
      // 停止但保持状态
      final stopped = await _singBoxService.stop();
      if (!stopped) {
        _addLog('配置重载: 停止原实例失败');
        return false;
      }
      final started = await _singBoxService.start(cfg);
      if (started) {
        _addLog('配置重载成功，模式=${_proxyMode.name}');
        return true;
      } else {
        _addLog('配置重载失败：重新启动未成功');
        // 尝试恢复
        try {
          final oldCfg = await _currentConfig!.toSingBoxConfig(
            mode: _proxyMode,
            localPort: _localPort,
            useTun: _useTun,
            tunStrictRoute: _tunStrictRoute,
            preferredTunStack: _singBoxService.preferredTunStack,
            enableClashApi: _enableClashApi,
            clashApiPort: _clashApiPort,
            clashApiSecret: _clashApiSecret,
            enableIpv6: effectiveIpv6,
          );
          await _singBoxService.start(oldCfg);
        } catch (_) {}
        return false;
      }
    } catch (e) {
      _addLog('配置重载异常: $e');
      return false;
    }
  }

  /// 设置TUN模式
  void setUseTun(bool enabled) {
    _useTun = enabled;
    if (_useTun) {
      // 启用 TUN 时强制关闭系统代理自动配置
      if (_autoSystemProxy && _proxyManager.isSupported) {
        // 立即尝试关闭系统代理（忽略异常）
        disableSystemProxy();
      }
      _autoSystemProxy = false;
    }
  }

  /// 设置TUN严格路由
  void setTunStrictRoute(bool enabled) {
    _tunStrictRoute = enabled;
  }

  /// 设置本地端口
  void setLocalPort(int port) {
    _localPort = port;
  }

  /// 设置自动系统代理
  void setAutoSystemProxy(bool enabled) {
    _autoSystemProxy = enabled;
    if (_autoSystemProxy) {
      // 开启系统代理时关闭 TUN
      _useTun = false;
    } else {
      // 关闭系统代理则尝试清理
      if (_proxyManager.isSupported) {
        disableSystemProxy();
      }
    }
  }

  /// 设置Clash API
  void setClashApi(bool enabled, int port, String secret) {
    _enableClashApi = enabled;
    _clashApiPort = port;
    _clashApiSecret = secret;
  }

  /// 清空日志
  void clearLogs() {
    _logs.clear();
  }

  // Private methods

  void _updateStatus(ConnectionStatus status, String message) {
    _status = status;
    _statusMessage = message;

    // 修复：当状态变为断开连接时，清空当前配置
    // 这样可以确保自动断开时也能正确清理状态
    if (status == ConnectionStatus.disconnected) {
      _currentConfig = null;
      _connectionStartTime = null;
      print("[DEBUG] _updateStatus: 状态变为断开，清空currentConfig");
    }
  }

  void _addLog(String log) {
    _logs.add('[${DateTime.now().toString().substring(11, 19)}] $log');
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
  }

  Future<int?> _allocateLocalPort({required int preferred}) async {
    try {
      final server = await ServerSocket.bind('127.0.0.1', preferred);
      final port = server.port;
      await server.close();
      return port;
    } catch (e) {
      // 端口被占用，尝试随机端口
      try {
        final server = await ServerSocket.bind('127.0.0.1', 0);
        final port = server.port;
        await server.close();
        return port;
      } catch (e) {
        return null;
      }
    }
  }

  Future<void> enableSystemProxy() async {
    if (_proxyManager.isSupported) {
      await _proxyManager.enableProxy(port: _localPort);
    }
  }

  /// 关闭系统代理（公开给上层进行互斥控制）
  Future<void> disableSystemProxy() async {
    try {
      if (_proxyManager.isSupported) {
        await _proxyManager.disableProxy();
      }
    } catch (_) {
      // 忽略关闭失败
    }
  }
}
