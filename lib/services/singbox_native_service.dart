import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'singbox_ffi.dart';

/// sing-box 原生服务管理类（使用 FFI）
class SingBoxNativeService {
  SingBoxFFI? _ffi; // 延迟加载，避免应用启动时就加载 DLL
  bool _initialized = false;
  bool _started = false; // 记录当前是否已成功执行 start
  Future<bool>? _initFuture; // 进行中的初始化（防止并发重入）

  // Batch B: 首段文件日志
  IOSink? _earlyFileLogSink; // 早期文件日志（捕捉 UI 不显示阶段）
  String? _preferredTunStack; // 最近一次成功的 TUN 栈（持久化加载）

  // 外部可写入/读取首选栈
  String? get preferredTunStack => _preferredTunStack;
  set preferredTunStack(String? v) => _preferredTunStack = v;

  // 回调函数
  Function(String)? onLog;
  Function(bool)? onStatusChanged;

  /// 初始化服务
  Future<bool> initialize() async {
    if (_initialized) return true;

    // 若已有正在进行的初始化，直接复用其 Future，避免并发再次触发 DLL 加载
    final existing = _initFuture;
    if (existing != null) {
      onLog?.call('INIT: 复用进行中的初始化 Future');
      return await existing;
    }

    final completer = Completer<bool>();
    _initFuture = completer.future;

    try {
      onLog?.call('INIT: 开始初始化 sing-box FFI');
      final sw = Stopwatch()..start();
      await _initEarlyFileLogger();
      _earlyFileLog('EARLY: 进入初始化流程');
      // 推迟真正的 DLL 加载到 Isolate.run 内部
      bool finished = false;
      Future(() async {
        while (!finished) {
          await Future.delayed(const Duration(seconds: 1));
          final s = sw.elapsed.inSeconds;
          if (finished) break;
          if (s == 2 || s == 4) {
            onLog?.call('INIT: 仍在初始化 (elapsed=${s}s)');
            _earlyFileLog('HEARTBEAT init ${s}s');
          }
          if (s > 8) break;
        }
      });
      int result = -999;
      try {
        result = await Isolate.run<int>(() {
          final ffi = SingBoxFFI.instance; // 这里触发动态库加载
          return ffi.init();
        }).timeout(const Duration(seconds: 5)); // 从10秒优化到5秒
      } on TimeoutException {
        onLog?.call('INIT: 超时 (>=5s) 可能 DLL 初始化被安全软件拦截');
        _earlyFileLog('TIMEOUT >=5s (疑似拦截)');
        return false;
      } finally {
        finished = true;
      }
      if (result == 0) {
        _initialized = true;
        _ffi = SingBoxFFI.instance;
        onLog?.call('sing-box 初始化成功 (${sw.elapsedMilliseconds}ms)');
        _earlyFileLog('SUCCESS init ${sw.elapsedMilliseconds}ms');
        _ffi!.setLogCallback((logLine) {
          _earlyFileLog(logLine);
          onLog?.call(logLine);
        });
        completer.complete(true);
        return true;
      } else {
        onLog?.call('sing-box 初始化失败: $result (${sw.elapsedMilliseconds}ms)');
        _earlyFileLog('FAIL result=$result');
        completer.complete(false);
        return false;
      }
    } catch (e) {
      onLog?.call('初始化异常: $e');
      _earlyFileLog('EXCEPTION $e');
      completer.complete(false);
      return false;
    } finally {
      // 只有真正完成并标记 _initialized 后才清空 _initFuture，防止多个等待者早于标记读取到 null 又重新发起
      if (_initialized) {
        _initFuture = null;
      } else {
        // 如果失败，也允许后续再次尝试，因此清空
        _initFuture = null;
      }
    }
  }

  /// 检查 sing-box 是否已安装（集成版始终可用）
  Future<bool> isSingBoxInstalled() async {
    // 集成版通过 FFI 动态库加载，无需外部可执行文件
    return true;
  }

  /// 生成配置文件路径
  Future<String> getConfigPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final configDir = Directory(path.join(appDir.path, 'sing-box', 'configs'));

    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }

    return path.join(configDir.path, 'config.json');
  }

  /// 保存配置
  Future<String> saveConfig(Map<String, dynamic> config) async {
    final configPath = await getConfigPath();
    final configFile = File(configPath);
    await configFile.writeAsString(jsonEncode(config));
    return configPath;
  }

  /// 启动 sing-box
  Future<bool> start(Map<String, dynamic> config) async {
    if (!_initialized) {
      if (!await initialize()) {
        return false;
      }
    }

    _ffi ??= SingBoxFFI.instance;
    if (_ffi!.isRunning) {
      onLog?.call('sing-box 已经在运行');
      return false;
    }

    try {
      _earlyFileLog('PHASE-S0 start() entered');
      // 启动前输出关键信息，便于诊断 TUN/DNS 路由参数
      try {
        final inbounds =
            (config['inbounds'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        final tun = inbounds.firstWhere(
          (e) => e['type'] == 'tun',
          orElse: () => <String, dynamic>{},
        );
        if (tun.isNotEmpty) {
          onLog?.call(
            'TUN 即将启用: stack=${tun['stack']}, auto_route=${tun['auto_route']}, strict_route=${tun['strict_route']}, mtu=${tun['mtu']}, iface=${tun['interface_name'] ?? ''}',
          );
        } else {
          onLog?.call('未启用 TUN 入站');
        }
        _earlyFileLog('PHASE-S1 tun inspection done');
        final dns = (config['dns'] as Map<String, dynamic>?);
        if (dns != null) {
          final servers = (dns['servers'] as List?)?.length ?? 0;
          if (Platform.isWindows) {
            final stack = (tun['stack'] ?? '').toString().toLowerCase();
            // gvisor 栈不需要真实 Wintun 设备，跳过 PowerShell 以避免高延迟导致“假卡死”
            if (stack == 'gvisor') {
              onLog?.call('TUN 适配器状态(预启动): gVisor 模式跳过物理适配器探测');
            } else {
              try {
                final ifaceName = (tun['interface_name'] ?? 'Wintun Gsou')
                    .toString();
                final ps = await Process.run('powershell.exe', [
                  '-NoProfile',
                  '-NonInteractive',
                  '-ExecutionPolicy',
                  'Bypass',
                  '-Command',
                  'Get-NetAdapter -Name "' +
                      ifaceName +
                      '" -ErrorAction SilentlyContinue | Select-Object -Property Status, MacAddress, LinkSpeed | Format-List',
                ]).timeout(const Duration(seconds: 3));
                final txt = (ps.stdout ?? '').toString().trim();
                if (txt.isNotEmpty) {
                  onLog?.call('TUN 适配器状态(预启动): ' + txt.replaceAll('\n', ' | '));
                } else {
                  onLog?.call('TUN 适配器状态(预启动): 未找到 ' + ifaceName);
                }
              } catch (_) {}
            }
          }
          onLog?.call(
            'DNS 配置: servers=$servers, strategy=${dns['strategy'] ?? ''}',
          );
        }
        final route = (config['route'] as Map<String, dynamic>?);
        if (route != null) {
          final rulesCount = (route['rules'] as List?)?.length ?? 0;
          onLog?.call('路由规则数: $rulesCount, final=${route['final'] ?? ''}');
        }
        _earlyFileLog('PHASE-S2 pre-start logging done');
      } catch (_) {}

      // 将配置转换为 JSON
      final configJson = jsonEncode(config);

      // 启动服务（放到后台 Isolate，避免阻塞 UI），并设置超时保护
      Future<int> _startOnce(String json, {Duration? timeout}) async {
        return await Isolate.run<int>(() {
          final ffi = SingBoxFFI.instance;
          return ffi.start(json);
        }).timeout(timeout ?? const Duration(seconds: 8)); // 从20秒优化到8秒
      }

      final startSw = Stopwatch()..start();
      // 心跳：2s / 4s / 6s 若仍未返回，提示仍在等待，便于区分死锁 vs 纯耗时
      final heartbeatMarks = <int>{2, 4, 6}; // 更快的反馈
      int result = -99;
      bool finished = false;
      Future(() async {
        while (!finished) {
          await Future.delayed(const Duration(seconds: 1));
          final elapsed = startSw.elapsed.inSeconds;
          if (!finished && heartbeatMarks.contains(elapsed)) {
            onLog?.call('START PROGRESS: sing-box 仍在启动 (elapsed=${elapsed}s)');
          }
          if (elapsed > 10) break; // 超过 10s 不再刷心跳，避免刷屏
        }
      });
      _earlyFileLog('PHASE-S3 calling ffi.start');
      result = await _startOnce(configJson);
      _earlyFileLog('PHASE-S4 ffi.start returned code=$result');
      finished = true;

      switch (result) {
        case 0:
          onLog?.call('sing-box 启动成功');
          onStatusChanged?.call(true);
          _started = true;
          _captureTunStackSuccess(config);
          // 健康探测已移除
          return true;
        case -1:
          onLog?.call('sing-box 已经在运行');
          return false;
        case -2:
          final detail = _ffi!.getLastError();
          onLog?.call(detail.isEmpty ? '配置解析失败' : '配置解析失败: $detail');
          return false;
        case -3:
          final detail = _ffi!.getLastError();
          onLog?.call(detail.isEmpty ? '创建实例失败' : '创建实例失败: $detail');
          return false;
        case -4:
          var detail = _ffi!.getLastError();
          onLog?.call(detail.isEmpty ? '启动失败' : '启动失败: $detail');
          // Windows TUN 兜底：若为 Wintun/接口配置相关错误，自动回退为 gvisor 再试一次
          try {
            if (Platform.isWindows) {
              Map<String, dynamic>? maybeTun = (config['inbounds'] as List?)
                  ?.cast<Map<String, dynamic>>()
                  .firstWhere(
                    (e) => (e['type'] == 'tun'),
                    orElse: () => <String, dynamic>{},
                  );
              if (maybeTun != null && maybeTun.isNotEmpty) {
                final err = detail.toLowerCase();
                // gVisor 未编译提示，需要反向回退到 system；其他仍按原策略回退到 gvisor
                final gvisorMissing = err.contains('gvisor is not included');
                final suspect =
                    err.contains('tun') ||
                    err.contains('wintun') ||
                    err.contains('open interface') ||
                    err.contains('configure tun') ||
                    gvisorMissing;
                if (suspect) {
                  final originalStack = (maybeTun['stack'] ?? '').toString();
                  if (gvisorMissing && originalStack == 'gvisor') {
                    onLog?.call('回退策略: gVisor 不可用 → system');
                    maybeTun['stack'] = 'system';
                  } else if (originalStack == 'gvisor') {
                    onLog?.call('回退策略: gvisor 启动失败 → 尝试 system 栈');
                    maybeTun['stack'] = 'system';
                  } else if (originalStack == 'system') {
                    onLog?.call('回退策略: system 启动失败 → 尝试 gvisor 栈');
                    maybeTun['stack'] = 'gvisor';
                  } else {
                    onLog?.call('回退策略: 未知栈=$originalStack → 尝试 gvisor');
                    maybeTun['stack'] = 'gvisor';
                  }
                  maybeTun['strict_route'] = false;
                  maybeTun['auto_route'] = true;
                  onLog?.call('回退策略: 关闭 strict_route 以提高兼容性');
                  // 重新编码并启动
                  final retryJson = jsonEncode(config);
                  result = await _startOnce(
                    retryJson,
                    timeout: const Duration(seconds: 8), // 优化重试超时
                  );
                  if (result == 0) {
                    onLog?.call('回退后 TUN 启动成功 (stack=${maybeTun['stack']})');
                    onStatusChanged?.call(true);
                    _started = true;
                    _captureTunStackSuccess(config);
                    // 健康探测已移除
                    return true;
                  }
                  // 第二次再失败：尝试第三种（若有）
                  if (result != 0) {
                    final secondStack = maybeTun['stack'];
                    // 如果刚尝试 system，换 gvisor；如果刚尝试 gvisor，换 system
                    final alt = secondStack == 'gvisor' ? 'system' : 'gvisor';
                    if (alt != secondStack) {
                      onLog?.call('回退策略: 再次失败 → 最后尝试 $alt 栈');
                      maybeTun['stack'] = alt;
                      final thirdJson = jsonEncode(config);
                      final third = await _startOnce(
                        thirdJson,
                        timeout: const Duration(seconds: 6), // 优化第三次尝试超时
                      );
                      if (third == 0) {
                        onLog?.call('第二次回退成功 (stack=${maybeTun['stack']})');
                        onStatusChanged?.call(true);
                        _started = true;
                        _captureTunStackSuccess(config);
                        // 健康探测已移除
                        return true;
                      }
                    }
                  }
                  // 再取一次错误详情
                  detail = _ffi!.getLastError();
                  onLog?.call(
                    detail.isEmpty ? '回退后仍启动失败' : '回退后仍启动失败: $detail',
                  );
                }
              }
            }
          } catch (_) {}
          return false;
        default:
          final detail = _ffi!.getLastError();
          onLog?.call(
            detail.isEmpty ? '未知错误: $result' : '未知错误($result): $detail',
          );
          return false;
      }
    } catch (e) {
      if (e is TimeoutException) {
        onLog?.call('启动超时：TUN/Wintun 初始化耗时过长，准备尝试回退到 gvisor 并重试...');
        // 超时时也尝试一次 gvisor 回退
        try {
          final inbounds =
              (config['inbounds'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
          final tun = inbounds.firstWhere(
            (e) => e['type'] == 'tun',
            orElse: () => <String, dynamic>{},
          );
          if (tun.isNotEmpty && (tun['stack'] != 'gvisor')) {
            tun['stack'] = 'gvisor';
            tun['strict_route'] = false;
            tun['auto_route'] = true;
            onLog?.call('第二次回退: 关闭 strict_route 以提高兼容性');
            final retryJson = jsonEncode(config);
            final result = await Isolate.run<int>(() {
              final ffi = SingBoxFFI.instance;
              return ffi.start(retryJson);
            }).timeout(const Duration(seconds: 8)); // 优化停止超时
            if (result == 0) {
              onLog?.call('回退 gvisor 后启动成功');
              onStatusChanged?.call(true);
              _started = true;
              _captureTunStackSuccess(config);
              // 健康探测已移除
              return true;
            }
            final detail = _ffi!.getLastError();
            onLog?.call(
              detail.isEmpty ? '回退后仍启动失败（超时路径）' : '回退后仍启动失败（超时路径）: $detail',
            );
          }
        } catch (_) {}
        try {
          _ffi?.stop();
        } catch (_) {}
        return false;
      }
      onLog?.call('启动异常: $e');
      return false;
    }
  }

  /// 停止 sing-box
  Future<bool> stop() async {
    _ffi ??= SingBoxFFI.instance;
    if (!_ffi!.isRunning) {
      onLog?.call('sing-box 未运行');
      return false;
    }

    try {
      final result = _ffi!.stop();
      _started = false;
      // 健康探测已移除

      switch (result) {
        case 0:
          onLog?.call('sing-box 已停止');
          onStatusChanged?.call(false);
          return true;
        case -1:
          onLog?.call('sing-box 未运行');
          return false;
        case -2:
          onLog?.call('停止失败');
          return false;
        default:
          onLog?.call('未知错误: $result');
          return false;
      }
    } catch (e) {
      onLog?.call('停止异常: $e');
      return false;
    }
  }

  /// 重启 sing-box
  Future<bool> restart(Map<String, dynamic> config) async {
    await stop();
    await Future.delayed(const Duration(milliseconds: 300)); // 从1秒优化到300毫秒
    return await start(config);
  }

  /// 获取运行状态
  bool get isRunning => _ffi?.isRunning ?? false;

  /// 测试配置
  Future<bool> testConfig(Map<String, dynamic> config) async {
    try {
      _ffi ??= SingBoxFFI.instance;
      final configJson = jsonEncode(config);
      // 在后台 Isolate 执行验证并设置超时，避免阻塞 UI 线程
      final result = await Isolate.run<int>(() {
        final ffi = SingBoxFFI.instance;
        return ffi.testConfig(configJson);
      }).timeout(const Duration(seconds: 5)); // 优化配置测试超时

      if (result == 0) {
        onLog?.call('-配置验证通过');
        return true;
      } else {
        final detail = _ffi!.getLastError();
        onLog?.call(
          detail.isEmpty ? '配置验证失败: $result' : '配置验证失败($result): $detail',
        );
        return false;
      }
    } catch (e) {
      if (e is TimeoutException) {
        onLog?.call('配置验证超时：请检查 TUN/Wintun 及配置内容');
        return false;
      }
      onLog?.call('配置验证异常: $e');
      return false;
    }
  }

  /// 清理资源
  void dispose() {
    if (_initialized) {
      try {
        _ffi?.cleanup();
      } catch (_) {}
      _initialized = false;
    }
    // 健康探测已移除
    _closeEarlyFileLogger();
  }

  // 对外暴露：手动触发一次健康探测
  Future<bool> probeHealthOnce() async {
    return true; // 健康探测功能已移除，始终返回成功
  }

  // 对外暴露：清除首选 TUN 栈（下次生成配置回到默认）
  Future<bool> clearPreferredTunStack() async {
    try {
      _preferredTunStack = null;
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory(path.join(dir.path, 'sing-box'));
      final prefFile = File(path.join(logDir.path, 'preferred_stack.txt'));
      if (await prefFile.exists()) await prefFile.delete();
      onLog?.call('已清除首选 TUN 栈');
      return true;
    } catch (e) {
      onLog?.call('清除首选 TUN 栈失败: $e');
      return false;
    }
  }

  // 调试：外部写入 early 文件日志
  void debugEarly(String line) {
    _earlyFileLog('[EXT] $line');
  }

  // ================= Batch B: 健康探测 & 首选栈持久化 & 早期文件日志 =================

  Future<void> _initEarlyFileLogger() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory(path.join(dir.path, 'sing-box'));
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      final file = File(path.join(logDir.path, 'early_start.log'));
      final sink = file.openWrite(mode: FileMode.append);
      _earlyFileLogSink = sink;
      _earlyFileLog('=== Session ${DateTime.now().toIso8601String()} ===');
      // 加载首选栈
      try {
        final prefFile = File(path.join(logDir.path, 'preferred_stack.txt'));
        if (await prefFile.exists()) {
          final content = (await prefFile.readAsString()).trim();
          if (content == 'gvisor' || content == 'system') {
            _preferredTunStack = content;
            onLog?.call('加载首选 TUN 栈: $_preferredTunStack');
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  void _closeEarlyFileLogger() {
    try {
      _earlyFileLogSink?.close();
    } catch (_) {}
    _earlyFileLogSink = null;
  }

  void _earlyFileLog(String line) {
    try {
      _earlyFileLogSink?.writeln('[${DateTime.now().toIso8601String()}] $line');
    } catch (_) {}
  }

  // 健康探测功能已完全移除

  Future<void> _captureTunStackSuccess(Map<String, dynamic> config) async {
    try {
      final inbounds =
          (config['inbounds'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final tun = inbounds.firstWhere(
        (e) => e['type'] == 'tun',
        orElse: () => <String, dynamic>{},
      );
      if (tun.isEmpty) return;
      final stack = (tun['stack'] ?? '').toString();
      if (stack != 'gvisor' && stack != 'system') return;
      if (_preferredTunStack == stack) return; // 无需重复写入
      _preferredTunStack = stack;
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory(path.join(dir.path, 'sing-box'));
      if (!await logDir.exists()) await logDir.create(recursive: true);
      final prefFile = File(path.join(logDir.path, 'preferred_stack.txt'));
      await prefFile.writeAsString(stack);
      onLog?.call('保存首选 TUN 栈: $stack');
    } catch (_) {}
  }
}
