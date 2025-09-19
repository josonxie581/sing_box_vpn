import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'singbox_ffi.dart';
import '../models/vpn_config.dart';

/// sing-box 原生服务管理类（使用 FFI）
class SingBoxNativeService {
  SingBoxFFI? _ffi; // 延迟加载，避免应用启动时就加载 DLL
  bool _initialized = false;
  // ignore: unused_field
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

  // 已存在 isRunning getter，避免重复定义

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
        // 在主线程中直接初始化，避免Isolate导致的重复加载
        _ffi = SingBoxFFI.instance;
        result = _ffi!.init();
        finished = true;
      } catch (e) {
        onLog?.call('初始化失败: $e');
        _earlyFileLog('INIT EXCEPTION: $e');
        finished = true;
        return false;
      }

      if (result == 0) {
        _initialized = true;
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
                final ifaceName = (tun['interface_name'] ?? 'sing-box')
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
                  // onLog?.call('TUN 适配器状态(预启动): 未找到 ' + ifaceName);
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

      // 直接在主线程启动服务，避免Isolate导致DLL重复加载
      Future<int> _startOnce(String json, {Duration? timeout}) async {
        return _ffi!.start(json);
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
            final result = _ffi!.start(retryJson);
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

    print("[DEBUG] 尝试停止VPN");

    try {
      // 为防止原生层因网络/DNS阻塞导致长时间卡住，增加快速路径：
      // 1) 先调用 stop()
      // 2) 若 2 秒内未返回成功，则调用 cleanup() 进行兜底清理
      int result = -999;
      try {
        result = _ffi!.stop();
      } catch (e) {
        // 继续走兜底
      }
      if (result != 0) {
        // 当 Stop 返回非 0，尝试使用 cleanup 强制收尾
        onLog?.call('停止返回码 $result，尝试强制清理...');
        // 避免阻塞 UI，直接调用 cleanup（native 已优化为非持锁关闭）
        try {
          _ffi!.cleanup();
          result = 0; // 视为成功
        } catch (e) {
          onLog?.call('强制清理异常: $e');
        }
      }
      _started = false;
      // 健康探测已移除

      switch (result) {
        case 0:
          onLog?.call('sing-box 已停止');
          onStatusChanged?.call(false);
          print("[DEBUG] sing-box 停止成功!");
          return true;
        case -1:
          onLog?.call('sing-box 未运行');
          return false;
        case -2:
          onLog?.call('停止失败');
          print("[DEBUG] sing-box 停止失败");
          return false;
        default:
          onLog?.call('未知错误: $result');
          print("[DEBUG] sing-box 停止失败原因: $result");
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
      // 直接在主线程执行验证，避免Isolate导致DLL重复加载
      final result = _ffi!.testConfig(configJson);

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

  // ================= 延时测试专用方法 =================

  /// 启动临时代理用于延时测试
  Future<bool> startProxy(VPNConfig node, int proxyPort) async {
    if (!_initialized) {
      if (!await initialize()) {
        return false;
      }
    }

    try {
      onLog?.call('启动延时测试代理: ${node.name} 端口: $proxyPort');

      // 创建最简代理配置 - 仅HTTP代理，无TUN
      final config = {
        "log": {"level": "warn", "timestamp": true},
        "inbounds": [
          {
            "type": "http",
            "tag": "http-in",
            "listen": "127.0.0.1",
            "listen_port": proxyPort,
            "users": [],
          },
        ],
        "outbounds": [
          _createOutboundFromNode(node),
          {"type": "direct", "tag": "direct-out"},
        ],
        "route": {"rules": [], "final": node.id},
      };

      // 启动代理
      final configJson = jsonEncode(config);
      _ffi ??= SingBoxFFI.instance;

      final result = _ffi!.start(configJson);
      if (result == 0) {
        onLog?.call('延时测试代理启动成功: 端口 $proxyPort');
        return true;
      } else {
        final detail = _ffi!.getLastError();
        onLog?.call('延时测试代理启动失败($result): $detail');
        return false;
      }
    } catch (e) {
      onLog?.call('启动延时测试代理异常: $e');
      return false;
    }
  }

  /// 停止延时测试代理
  Future<bool> stopProxy() async {
    try {
      _ffi ??= SingBoxFFI.instance;
      if (!_ffi!.isRunning) {
        return true; // 已经停止
      }

      final result = _ffi!.stop();
      if (result == 0 || result == -1) {
        // 0=成功停止, -1=未运行
        onLog?.call('延时测试代理已停止');
        return true;
      } else {
        final detail = _ffi!.getLastError();
        onLog?.call('停止延时测试代理失败($result): $detail');
        return false;
      }
    } catch (e) {
      onLog?.call('停止延时测试代理异常: $e');
      return false;
    }
  }

  /// 根据VPN节点创建出站配置
  Map<String, dynamic> _createOutboundFromNode(VPNConfig node) {
    final outbound = <String, dynamic>{
      "tag": node.id,
      "type": node.type.toLowerCase(),
    };

    // 从settings获取配置值的辅助函数
    String getSetting(String key, [String defaultValue = '']) {
      return node.settings[key]?.toString() ?? defaultValue;
    }

    bool getBoolSetting(String key, [bool defaultValue = false]) {
      final value = node.settings[key];
      if (value is bool) return value;
      if (value is String) {
        return value.toLowerCase() == 'true' || value == '1';
      }
      return defaultValue;
    }

    switch (node.type.toLowerCase()) {
      case 'hysteria':
        outbound.addAll({"server": node.server, "server_port": node.port});

        // 认证：auth_str (明文) 或 auth (base64)
        final pwd = node.settings['password']?.toString() ?? '';
        if (pwd.isNotEmpty) outbound["auth_str"] = pwd;
        final authB64 = node.settings['auth']?.toString() ?? '';
        if (authB64.isNotEmpty) outbound["auth"] = authB64;

        // 带宽
        final upMbps = node.settings['up_mbps'];
        final downMbps = node.settings['down_mbps'];
        if (upMbps != null) outbound["up_mbps"] = upMbps;
        if (downMbps != null) outbound["down_mbps"] = downMbps;
        final upStr = node.settings['up']?.toString();
        final downStr = node.settings['down']?.toString();
        if (upStr != null && upStr.isNotEmpty) outbound["up"] = upStr;
        if (downStr != null && downStr.isNotEmpty) outbound["down"] = downStr;

        if (node.settings['obfs'] != null) {
          outbound["obfs"] = node.settings['obfs'];
        }
        if (node.settings['recv_window_conn'] != null) {
          outbound["recv_window_conn"] = node.settings['recv_window_conn'];
        }
        if (node.settings['recv_window'] != null) {
          outbound["recv_window"] = node.settings['recv_window'];
        }
        if (node.settings['disable_mtu_discovery'] != null) {
          outbound["disable_mtu_discovery"] =
              node.settings['disable_mtu_discovery'];
        }

        final tlsCfg = <String, dynamic>{
          "enabled": true,
          "server_name": node.settings['sni']?.toString() ?? node.server,
          "insecure": (node.settings['skipCertVerify'] == true),
        };
        final alpn = node.settings['alpn'];
        if (alpn is List && alpn.isNotEmpty) {
          tlsCfg["alpn"] = alpn;
        }
        outbound["tls"] = tlsCfg;
        break;
      case 'anytls':
        outbound.addAll({
          "server": node.server,
          "server_port": node.port,
          "password": getSetting('password'),
        });

        // AnyTLS 需要 TLS 配置
        final tlsCfg = <String, dynamic>{
          "enabled": true,
          "server_name": getSetting('sni', node.server),
          "insecure": getBoolSetting('skipCertVerify', false),
        };
        final alpn = node.settings['alpn'];
        if (alpn is List && alpn.isNotEmpty) {
          tlsCfg["alpn"] = alpn;
        }
        outbound["tls"] = tlsCfg;
        break;
      case 'vmess':
        outbound.addAll({
          "server": node.server,
          "server_port": node.port,
          "uuid": node.uuid,
          "alter_id": node.alterId ?? 0,
          "security": node.security.isNotEmpty ? node.security : "auto",
        });

        if (node.network == 'ws') {
          outbound["transport"] = {
            "type": "ws",
            "path": node.path.isNotEmpty ? node.path : "/",
            "headers": {if (node.host.isNotEmpty) "Host": node.host},
          };
        }

        final tlsValue = getSetting('tls');
        if (tlsValue == 'tls' || tlsValue.toLowerCase() == 'true') {
          outbound["tls"] = {
            "enabled": true,
            "server_name": getSetting(
              'sni',
              node.host.isNotEmpty ? node.host : node.server,
            ),
            "insecure": getBoolSetting('skipCertVerify', false),
          };
        }
        break;

      case 'vless':
        outbound.addAll({
          "server": node.server,
          "server_port": node.port,
          "uuid": node.uuid,
        });

        final flow = getSetting('flow');
        if (flow.isNotEmpty) {
          outbound["flow"] = flow;
        }

        if (node.network == 'ws') {
          outbound["transport"] = {
            "type": "ws",
            "path": node.path.isNotEmpty ? node.path : "/",
            "headers": {if (node.host.isNotEmpty) "Host": node.host},
          };
        } else if (node.network == 'grpc') {
          final serviceName = getSetting(
            'grpcServiceName',
            getSetting('service_name'),
          );
          outbound["transport"] = {
            "type": "grpc",
            "service_name": serviceName.isNotEmpty ? serviceName : "",
          };
        }

        final tlsEnabled = getBoolSetting('tlsEnabled');
        final realityEnabled = getBoolSetting('realityEnabled');

        if (tlsEnabled) {
          final tlsConfig = <String, dynamic>{
            "enabled": true,
            "server_name": getSetting('sni', node.server),
            "insecure": getBoolSetting('skipCertVerify', false),
          };

          if (realityEnabled) {
            final publicKey = getSetting('realityPublicKey');
            final shortId = getSetting('realityShortId');
            if (publicKey.isNotEmpty) {
              tlsConfig["reality"] = {
                "enabled": true,
                "public_key": publicKey,
                "short_id": shortId,
              };
            }
          }

          final alpn = node.settings['alpn'];
          if (alpn is List && alpn.isNotEmpty) {
            tlsConfig["alpn"] = alpn;
          }

          outbound["tls"] = tlsConfig;
        }
        break;

      case 'trojan':
        outbound.addAll({
          "server": node.server,
          "server_port": node.port,
          "password": node.password,
        });

        if (node.network == 'ws') {
          outbound["transport"] = {
            "type": "ws",
            "path": node.path.isNotEmpty ? node.path : "/",
            "headers": {if (node.host.isNotEmpty) "Host": node.host},
          };
        } else if (node.network == 'grpc') {
          final serviceName = getSetting(
            'grpcServiceName',
            getSetting('service_name'),
          );
          outbound["transport"] = {"type": "grpc", "service_name": serviceName};
        }

        outbound["tls"] = {
          "enabled": true,
          "server_name": getSetting(
            'sni',
            node.host.isNotEmpty ? node.host : node.server,
          ),
          "insecure": getBoolSetting('skipCertVerify', false),
        };

        final alpn = node.settings['alpn'];
        if (alpn is List && alpn.isNotEmpty) {
          outbound["tls"]["alpn"] = alpn;
        }
        break;

      case 'shadowsocks':
        final method = getSetting('method', "aes-256-gcm");
        outbound.addAll({
          "server": node.server,
          "server_port": node.port,
          "method": method,
          "password": node.password,
        });
        break;

      case 'shadowtls':
        outbound.addAll({
          "server": node.server,
          "server_port": node.port,
          "version": (node.settings['version'] is int)
              ? node.settings['version']
              : int.tryParse(node.settings['version']?.toString() ?? '') ?? 1,
        });
        final pwd = node.settings['password']?.toString() ?? '';
        if (pwd.isNotEmpty) {
          outbound["password"] = pwd;
        }
        final tlsCfg = <String, dynamic>{
          "enabled": true,
          "server_name": node.settings['sni']?.toString() ?? node.server,
          "insecure": (node.settings['skipCertVerify'] == true),
        };
        final alpn = node.settings['alpn'];
        if (alpn is List && alpn.isNotEmpty) {
          tlsCfg["alpn"] = alpn;
        }
        outbound["tls"] = tlsCfg;
        break;

      default:
        // 默认处理
        outbound.addAll({"server": node.server, "server_port": node.port});
    }

    return outbound;
  }
}
