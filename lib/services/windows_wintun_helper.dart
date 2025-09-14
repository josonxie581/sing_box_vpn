import 'dart:io';

/// Windows 平台 Wintun 辅助工具
class WindowsWintunHelper {
  /// 检测是否存在指定名称的 Wintun 网卡（默认 "Gsou Tunnel"）
  static Future<bool> isAdapterPresent({String name = 'Gsou Tunnel'}) async {
    if (!Platform.isWindows) return true;
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Get-NetAdapter -Name \'' +
            name +
            '\' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name',
      ]).timeout(const Duration(seconds: 5));

      if (result.exitCode == 0) {
        final out = (result.stdout ?? '').toString().trim();
        return out.toLowerCase() == name.toLowerCase();
      }
      return false;
    } catch (_) {
      // 如果 PowerShell 不可用，返回未知，不阻塞
      return true;
    }
  }
}
