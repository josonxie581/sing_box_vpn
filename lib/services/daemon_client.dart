import 'dart:async';

/// 守护进程客户端（已废弃）：移除 TCP 通信，保留空实现以兼容旧调用点
/// 说明：当前应用在启动时即请求管理员权限，并通过内置 Go DLL 直接创建/管理 TUN，
/// 无需与外部守护进程进行任何 TCP 通信。
class DaemonClient {
  /// 始终返回 false：不再通过端口探测守护进程
  static Future<bool> isDaemonRunning() async => false;

  /// 无操作：不再支持安装外部守护进程
  static Future<bool> installDaemon() async => false;

  /// 连接/断开均为空操作
  Future<bool> connect() async => false;
  Future<void> disconnect() async {}

  /// TUN 管理改由 FFI 内核直接处理，这里固定失败
  Future<bool> createTUN(Map<String, dynamic> config) async => false;
  Future<bool> destroyTUN() async => false;

  /// 心跳固定为 false
  Future<bool> ping() async => false;

  /// 旧版诊断接口：返回最小占位信息，明确指示已移除守护进程模式
  Future<Map<String, dynamic>> quickDiagnostics() async => <String, dynamic>{
        'daemon_mode': 'removed',
        'daemon_running': false,
        'note': '应用已内置内核并需管理员权限运行，不再通过 TCP 与守护进程通信',
        'timestamp': DateTime.now().toIso8601String(),
      };

  /// 流量统计：固定 0
  Future<Map<String, int>> getTrafficStats() async => <String, int>{'up': 0, 'down': 0};
}

/// 闪连风格管理器（占位空实现）：迁移期保留类型，所有操作均为 no-op
class FlashConnectVPNManager {
  DaemonClient get diagnosticsClient => DaemonClient();
  Future<bool> initialize() async => false;
  Future<bool> startVPN(Map<String, dynamic> config) async => false;
  Future<bool> stopVPN() async => false;
  Future<bool> isConnected() async => false;
  Future<void> dispose() async {}
}

