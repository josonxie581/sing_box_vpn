import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// sing-box 服务管理类
class SingBoxService {
  Process? _process;
  String? _configPath;
  bool _isRunning = false;

  // 回调函数
  Function(String)? onLog;
  Function(bool)? onStatusChanged;

  /// 获取 sing-box 可执行文件路径
  Future<String> getSingBoxPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final singBoxDir = Directory(path.join(appDir.path, 'sing-box'));

    if (!await singBoxDir.exists()) {
      await singBoxDir.create(recursive: true);
    }

    // Windows 平台的 sing-box 可执行文件
    return path.join(singBoxDir.path, 'sing-box.exe');
  }

  /// 检查 sing-box 是否已安装
  Future<bool> isSingBoxInstalled() async {
    final singBoxPath = await getSingBoxPath();
    return File(singBoxPath).exists();
  }

  /// 下载 sing-box
  Future<bool> downloadSingBox() async {
    try {
      // TODO: 实现下载 sing-box 的逻辑
      // 可以从 GitHub releases 下载最新版本
      // https://github.com/SagerNet/sing-box/releases

      onLog?.call('正在下载 sing-box...');

      // 这里需要实现实际的下载逻辑
      // 1. 获取最新版本信息
      // 2. 下载对应的 Windows 版本
      // 3. 解压到指定目录

      return true;
    } catch (e) {
      onLog?.call('下载失败: $e');
      return false;
    }
  }

  /// 生成配置文件
  Future<String> generateConfig(Map<String, dynamic> config) async {
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
  Future<bool> start(String configPath) async {
    if (_isRunning) {
      onLog?.call('sing-box 已经在运行');
      return false;
    }

    try {
      final singBoxPath = await getSingBoxPath();

      if (!await File(singBoxPath).exists()) {
        onLog?.call('sing-box 未安装');
        return false;
      }

      if (!await File(configPath).exists()) {
        onLog?.call('配置文件不存在');
        return false;
      }

      _configPath = configPath;

      // 启动 sing-box 进程
      _process = await Process.start(singBoxPath, [
        'run',
        '-c',
        configPath,
      ], workingDirectory: path.dirname(singBoxPath));

      // 监听输出
      _process!.stdout.transform(utf8.decoder).listen((data) {
        onLog?.call(data);
      });

      _process!.stderr.transform(utf8.decoder).listen((data) {
        onLog?.call('[错误] $data');
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
  Future<bool> restart() async {
    if (_configPath == null) {
      onLog?.call('没有配置文件');
      return false;
    }

    await stop();
    await Future.delayed(const Duration(seconds: 1));
    return await start(_configPath!);
  }

  /// 获取运行状态
  bool get isRunning => _isRunning;

  /// 测试配置文件
  Future<bool> testConfig(String configPath) async {
    try {
      final singBoxPath = await getSingBoxPath();

      if (!await File(singBoxPath).exists()) {
        onLog?.call('sing-box 未安装');
        return false;
      }

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
