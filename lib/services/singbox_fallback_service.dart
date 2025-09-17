import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// sing-box 回退服务（使用外部 exe）
class SingBoxFallbackService {
  Process? _process;
  String? _configPath;
  bool _isRunning = false;

  // 回调函数
  Function(String)? onLog;
  Function(bool)? onStatusChanged;

  /// 初始化服务
  Future<bool> initialize() async {
    onLog?.call('正在使用回退方案（外部 exe）');
    return true;
  }

  /// 获取 sing-box 可执行文件路径
  Future<String> getSingBoxPath() async {
    // 首先检查项目目录
    final currentDir = Directory.current.path;
    final localPath = path.join(currentDir, 'sing-box.exe');

    if (File(localPath).existsSync()) {
      return localPath;
    }

    // 检查应用数据目录
    final appDir = await getApplicationDocumentsDirectory();
    final singBoxDir = Directory(path.join(appDir.path, 'sing-box'));

    if (!await singBoxDir.exists()) {
      await singBoxDir.create(recursive: true);
    }

    return path.join(singBoxDir.path, 'sing-box.exe');
  }

  /// 检查 sing-box 是否已安装
  Future<bool> isSingBoxInstalled() async {
    final singBoxPath = await getSingBoxPath();
    return File(singBoxPath).exists();
  }

  /// 下载 sing-box（占位符实现）
  Future<bool> downloadSingBox() async {
    try {
      onLog?.call('请手动下载 sing-box.exe 并放置到项目根目录');
      onLog?.call('下载地址: https://github.com/SagerNet/sing-box/releases');

      // 这里可以实现自动下载逻辑
      // 暂时返回 false，让用户手动下载
      return false;
    } catch (e) {
      onLog?.call('下载失败: $e');
      return false;
    }
  }

  /// 生成配置文件
  Future<String> saveConfig(Map<String, dynamic> config) async {
    final appDir = await getApplicationDocumentsDirectory();
    final configDir = Directory(path.join(appDir.path, 'sing-box', 'configs'));

    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }

    final configFile = File(path.join(configDir.path, 'config.json'));
    await configFile.writeAsString(jsonEncode(config));

    return configFile.path;
  }

  /// 启动 sing-box
  Future<bool> start(Map<String, dynamic> config) async {
    if (_isRunning) {
      onLog?.call('sing-box 已经在运行');
      return false;
    }

    try {
      final singBoxPath = await getSingBoxPath();

      if (!await File(singBoxPath).exists()) {
        onLog?.call('sing-box 未找到，请先下载 sing-box.exe');
        onLog?.call('1. 访问: https://github.com/SagerNet/sing-box/releases');
        onLog?.call('2. 下载 Windows 版本');
        onLog?.call('3. 将 sing-box.exe 放到项目根目录');
        return false;
      }

      _configPath = await saveConfig(config);

      // 启动 sing-box 进程
      _process = await Process.start(singBoxPath, [
        'run',
        '-c',
        _configPath!,
      ], workingDirectory: path.dirname(singBoxPath));

      // 监听输出
      _process!.stdout.transform(utf8.decoder).listen((data) {
        onLog?.call(data.trim());
      });

      _process!.stderr.transform(utf8.decoder).listen((data) {
        onLog?.call('[错误] ${data.trim()}');
      });

      // 监听进程退出
      _process!.exitCode.then((exitCode) {
        onLog?.call('sing-box 已退出，退出码: $exitCode');
        _isRunning = false;
        onStatusChanged?.call(false);
      });

      _isRunning = true;
      onStatusChanged?.call(true);
      onLog?.call('sing-box 已启动');

      return true;
    } catch (e) {
      onLog?.call('启动失败: $e');
      return false;
    }
  }

  /// 停止 sing-box
  Future<bool> stop() async {
    if (!_isRunning || _process == null) {
      onLog?.call('sing-box 未运行');
      return false;
    }

    try {
      // Windows 平台使用 taskkill
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/PID', '${_process!.pid}']);
      } else {
        _process!.kill();
      }

      _isRunning = false;
      _process = null;
      onStatusChanged?.call(false);
      onLog?.call('sing-box 已停止');

      return true;
    } catch (e) {
      onLog?.call('停止失败: $e');
      return false;
    }
  }

  /// 重启 sing-box
  Future<bool> restart(Map<String, dynamic> config) async {
    await stop();
    await Future.delayed(const Duration(seconds: 1));
    return await start(config);
  }

  /// 获取运行状态
  bool get isRunning => _isRunning;

  /// 测试配置文件
  Future<bool> testConfig(Map<String, dynamic> config) async {
    try {
      final singBoxPath = await getSingBoxPath();

      if (!await File(singBoxPath).exists()) {
        onLog?.call('sing-box 未安装');
        return false;
      }

      final configPath = await saveConfig(config);

      final result = await Process.run(singBoxPath, [
        'check',
        '-c',
        configPath,
      ]);

      if (result.exitCode == 0) {
        onLog?.call('配置文件检查通过');
        return true;
      } else {
        onLog?.call('配置文件检查失败: ${result.stderr}');
        return false;
      }
    } catch (e) {
      onLog?.call('检查配置失败: $e');
      return false;
    }
  }

  /// 清理资源
  void dispose() {
    stop();
  }
}
