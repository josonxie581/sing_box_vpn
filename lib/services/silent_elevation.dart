import 'dart:io';
import 'dart:convert'; // Added for JsonEncoder.withIndent
import 'package:flutter/foundation.dart';

/// 静默提权服务 - 模仿闪连的实现方式
/// 使用批处理脚本实现 UAC 提权，但隐藏提权过程
class SilentElevation {
  static const String _elevateScript = r'tools\silent_elevate.bat';

  /// 静默启动需要管理员权限的程序
  /// [executable] 要运行的程序路径
  /// [arguments] 程序参数列表
  /// [hideWindow] 是否隐藏窗口（默认true，模仿闪连）
  static Future<bool> runAsAdmin(
    String executable,
    List<String> arguments, {
    bool hideWindow = true,
  }) async {
    if (!Platform.isWindows) {
      debugPrint('Silent elevation is only supported on Windows');
      return false;
    }

    try {
      // 检查提权脚本是否存在
      final scriptFile = File(_elevateScript);
      if (!scriptFile.existsSync()) {
        debugPrint('Elevation script not found: $_elevateScript');
        return false;
      }

      // 构建命令参数
      final cmdArgs = <String>[_elevateScript, executable, ...arguments];

      debugPrint('Silent elevation: ${cmdArgs.join(' ')}');

      // 启动静默提权
      // 启动进程（不需要保存引用，避免未使用变量告警）
      await Process.start(
        'cmd',
        ['/c', ...cmdArgs],
        mode: ProcessStartMode.detached, // 分离进程，不等待完成
      );

      // 等待一小段时间确保进程启动
      await Future.delayed(const Duration(milliseconds: 500));

      return true;
    } catch (e) {
      debugPrint('Failed to run silent elevation: $e');
      return false;
    }
  }

  /// 启动 VPN 服务（使用静默提权）
  static Future<bool> startVPNService() async {
    final serviceExe =
        '${Directory.current.path}\\service\\singbox_service.exe';

    // 检查服务程序是否存在
    if (!File(serviceExe).existsSync()) {
      debugPrint('Service executable not found: $serviceExe');
      return false;
    }

    return await runAsAdmin(serviceExe, ['start-silent']);
  }

  /// 安装 VPN 服务（使用静默提权）
  static Future<bool> installVPNService() async {
    final serviceExe =
        '${Directory.current.path}\\service\\singbox_service.exe';

    if (!File(serviceExe).existsSync()) {
      debugPrint('Service executable not found: $serviceExe');
      return false;
    }

    return await runAsAdmin(serviceExe, ['install']);
  }

  /// 创建 TUN 设备（直接提权方式）
  /// 这是闪连可能使用的方式：直接提权创建 TUN
  static Future<bool> createTUNDirect(Map<String, dynamic> config) async {
    // 创建临时配置文件
    final tempDir = Directory.systemTemp;
    final configFile = File('${tempDir.path}\\singbox_temp_config.json');

    try {
      // 写入配置
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );

      // 直接以管理员权限启动 sing-box
      final singboxExe = '${Directory.current.path}\\windows\\singbox.exe';

      return await runAsAdmin(singboxExe, [
        'run',
        '-c',
        configFile.path,
        '--disable-color',
      ]);
    } finally {
      // 清理临时文件
      try {
        await configFile.delete();
      } catch (_) {}
    }
  }
}

/// 闪连风格的 TUN 管理器
/// 核心思路：用户无感知的管理员权限获取
class FlashConnectStyleTunManager {
  bool _isElevated = false;
  Process? _tunProcess;

  /// 检查是否已提权
  bool get isElevated => _isElevated;

  /// 启动 TUN 模式（模仿闪连的用户体验）
  Future<bool> startTUN(Map<String, dynamic> config) async {
    try {
      // 方式1: 通过静默提权直接启动
      debugPrint('Starting TUN with silent elevation...');

      final success = await SilentElevation.createTUNDirect(config);

      if (success) {
        _isElevated = true;
        debugPrint('TUN started successfully with elevated privileges');

        // 可以在这里启动监控进程状态的逻辑
        _startTUNMonitoring();

        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Failed to start TUN: $e');
      return false;
    }
  }

  /// 停止 TUN
  Future<bool> stopTUN() async {
    try {
      if (_tunProcess != null) {
        _tunProcess!.kill();
        await _tunProcess!.exitCode;
        _tunProcess = null;
      }

      _isElevated = false;
      return true;
    } catch (e) {
      debugPrint('Failed to stop TUN: $e');
      return false;
    }
  }

  /// 监控 TUN 进程状态
  void _startTUNMonitoring() {
    // 可以实现进程监控、自动重启等逻辑
    // 类似闪连的稳定性保障
  }
}

// 使用示例
/*
final tunManager = FlashConnectStyleTunManager();

// 用户点击连接，体验类似闪连
final success = await tunManager.startTUN({
  "inbounds": [{
    "type": "tun",
    "interface_name": "Gsou Tunnel",
    "stack": "system",  // 使用 Wintun
    "auto_route": true,
  }]
});

if (success) {
  print('Connected! (like 闪连)');
}
*/
