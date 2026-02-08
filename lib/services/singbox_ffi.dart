import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path/path.dart' as path;
// import 'package:win32/win32.dart' as win32; // Not required; use Directory.current instead

// C 原型: typedef void (*LogCallback)(const char* msg);
// 注意：typedef 需置于顶层，避免 Dart analyzer 报错
typedef NativeLogC = Void Function(Pointer<Utf8>);
typedef DartLogC = void Function(Pointer<Utf8>);

// 将原生日志回调桥接为 Dart 打印（线程安全：仅进行简单字符串转换与打印）
void _nativeLog(Pointer<Utf8> msg) {
  try {
    final s = msg.toDartString();
    // ignore: avoid_print
    print(s);
  } catch (_) {}
}

/// sing-box FFI 绑定
class SingBoxFFI {
  static SingBoxFFI? _instance;
  late DynamicLibrary _lib;

  // 函数指针
  late final Function _initSingBox;
  late final Function _startSingBox;
  late final Function? _startSingBoxWithTunFd;
  late final Function _stopSingBox;
  late final Function _isRunning;
  late final Function _testConfig;
  late final Function _cleanup;
  late final Function _getVersion;
  Pointer<Utf8> Function()? _getLastError;
  void Function(Pointer<Utf8>)? _freeCString;
  Pointer<Utf8> Function()? _drainLogs;
  // 严格探测
  int Function(Pointer<Utf8>, int, Pointer<Utf8>, int, Pointer<Utf8>, int)?
  _probeTLS;
  int Function(Pointer<Utf8>, int, Pointer<Utf8>, int, Pointer<Utf8>, int)?
  _probeQUIC;

  // 新增：动态路由规则管理
  int Function(Pointer<Utf8>)? _addRouteRule;
  int Function(Pointer<Utf8>)? _removeRouteRule;
  int Function()? _reloadConfig;
  int Function(Pointer<Utf8>)? _replaceConfig;
  int Function()? _clearRouteRules;

  // 回调函数
  // 日志回调暂不使用，后续可以通过端口消息通道实现

  SingBoxFFI._() {
    _loadLibrary();
    _bindFunctions();
  }

  /// 获取单例实例
  static SingBoxFFI get instance {
    _instance ??= SingBoxFFI._();
    return _instance!;
  }

  /// 提前初始化（在应用启动时调用）
  static Future<void> preloadLibrary() async {
    try {
      print('[SingBoxFFI] 开始预加载 sing-box 动态库...');
      final stopwatch = Stopwatch()..start();

      // 触发单例创建，这会自动调用 _loadLibrary
      final _ = instance;

      stopwatch.stop();
      print(
        '[SingBoxFFI] sing-box 动态库预加载完成，耗时: ${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      print('[SingBoxFFI] sing-box 动态库预加载失败: $e');
      // 不抛出异常，允许应用继续运行
      // 实际使用时会再次尝试加载
    }
  }

  /// 加载动态库
  void _loadLibrary() {
    final libraryPath = _getLibraryPath();
    _ffiDiag('FFI: _loadLibrary begin -> target=$libraryPath');

    final isWindows = Platform.isWindows;
    final isAndroid = Platform.isAndroid;
    if (!isWindows && !isAndroid) {
      throw UnsupportedError('暂不支持该平台');
    }

    // Windows: 将工作目录切换到可执行文件目录，提升依赖 DLL 的可发现性
    try {
      if (isWindows) {
        final exeDir = path.dirname(Platform.resolvedExecutable);
        Directory.current = exeDir;
        _ffiDiag('FFI: set CWD to $exeDir');
      }
    } catch (e) {
      _ffiDiag('FFI: set CWD failed: $e');
    }

    final sw = Stopwatch()..start();
    bool finished = false;
    // 若加载超过 1200ms 仍未返回，则每秒追加一次“仍在加载”提示，帮助定位是否卡在 AV/Defender 扫描
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (finished) {
        t.cancel();
        return;
      }
      if (sw.elapsedMilliseconds > 1000 * (t.tick)) {
        _ffiDiag(
          'FFI: DynamicLibrary.open still pending... ${sw.elapsedMilliseconds}ms',
        );
      }
      // 限制最多 8 条
      if (t.tick >= 8) t.cancel();
    });
    try {
      _ffiDiag('FFI: calling DynamicLibrary.open');
      _lib = DynamicLibrary.open(libraryPath);
      finished = true;
      _ffiDiag(
        'FFI: DynamicLibrary.open ok ${sw.elapsedMilliseconds}ms size=${_safeFileSize(libraryPath)} sha256_hint=${_sizeHashHint(libraryPath)}',
      );
    } catch (e) {
      finished = true;
      _ffiDiag(
        'FFI: DynamicLibrary.open FAILED after ${sw.elapsedMilliseconds}ms -> $e',
      );
      rethrow;
    }
  }

  // _preloadWintunIfPresent 已移除

  /// 获取库文件路径
  String _getLibraryPath() {
    if (Platform.isWindows) {
      // 优先从应用目录（Flutter Windows 构建输出目录）加载集成版
      final exeDir = path.dirname(Platform.resolvedExecutable);
      final exeIntegrated = path.join(exeDir, 'singbox.dll');
      if (File(exeIntegrated).existsSync()) {
        return exeIntegrated;
      }

      // 开发模式下从项目目录加载
      final devDllPath = path.join(
        Directory.current.path,
        'windows',
        'singbox.dll',
      );
      if (File(devDllPath).existsSync()) {
        return devDllPath;
      }

      // 不再支持外部 DLL/EXE 回退；明确报错提示缺少集成 DLL
      throw StateError(
        '未找到 singbox.dll。\n'
        '请确保已执行预编译生成 windows/singbox.dll，'
        '或在发布包中将该 DLL 与可执行文件放在同一目录。',
      );
    }

    if (Platform.isAndroid) {
      // Android: .so 会被系统从标准库搜索路径加载，直接传库名即可。
      // 需要在项目中放置：android/app/src/main/jniLibs/<abi>/libsingbox.so
      return 'libsingbox.so';
    }

    throw UnsupportedError('暂不支持该平台');
  }

  /// 绑定函数
  void _bindFunctions() {
    _ffiDiag('FFI: _bindFunctions start');
    // InitSingBox() -> int
    _initSingBox = _lib
        .lookup<NativeFunction<Int32 Function()>>('InitSingBox')
        .asFunction<int Function()>();

    // StartSingBox(char* configJSON) -> int
    _startSingBox = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Utf8>)>>('StartSingBox')
        .asFunction<int Function(Pointer<Utf8>)>();

    // Optional: StartSingBoxWithTunFd(char* configJSON, int fd) -> int
    try {
      _startSingBoxWithTunFd = _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Int32)>>(
            'StartSingBoxWithTunFd',
          )
          .asFunction<int Function(Pointer<Utf8>, int)>();
    } catch (_) {
      _startSingBoxWithTunFd = null;
    }

    // StopSingBox() -> int
    _stopSingBox = _lib
        .lookup<NativeFunction<Int32 Function()>>('StopSingBox')
        .asFunction<int Function()>();

    // IsRunning() -> int
    _isRunning = _lib
        .lookup<NativeFunction<Int32 Function()>>('IsRunning')
        .asFunction<int Function()>();

    // TestConfig(char* configJSON) -> int
    _testConfig = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Utf8>)>>('TestConfig')
        .asFunction<int Function(Pointer<Utf8>)>();

    // Cleanup()
    _cleanup = _lib
        .lookup<NativeFunction<Void Function()>>('Cleanup')
        .asFunction<void Function()>();

    // GetVersion() -> char*
    _getVersion = _lib
        .lookup<NativeFunction<Pointer<Utf8> Function()>>('GetVersion')
        .asFunction<Pointer<Utf8> Function()>();

    // RegisterLogCallback：仅在 Debug 注册，避免 Release 下线程回调导致崩溃
    if (kDebugMode) {
      try {
        // C: typedef void (*LogCallback)(const char* msg);
        final reg = _lib
            .lookupFunction<
              Void Function(Pointer<NativeFunction<NativeLogC>>),
              void Function(Pointer<NativeFunction<NativeLogC>>)
            >('RegisterLogCallback');
        // 绑定本地回调，把 C 文本打印到 Dart 日志
        final cbPtr = Pointer.fromFunction<NativeLogC>(_nativeLog);
        reg(cbPtr);
      } catch (_) {
        // 老版本或不支持可忽略
      }
    }

    // Optional: GetLastError/FreeCString (may not exist in older DLLs)
    try {
      // Prefer new name to avoid WinAPI symbol conflict
      _getLastError = _lib
          .lookup<NativeFunction<Pointer<Utf8> Function()>>('SbGetLastError')
          .asFunction<Pointer<Utf8> Function()>();
    } catch (_) {
      try {
        _getLastError = _lib
            .lookup<NativeFunction<Pointer<Utf8> Function()>>('GetLastError')
            .asFunction<Pointer<Utf8> Function()>();
      } catch (_) {
        _getLastError = null;
      }
    }
    try {
      _freeCString = _lib
          .lookup<NativeFunction<Void Function(Pointer<Utf8>)>>('FreeCString')
          .asFunction<void Function(Pointer<Utf8>)>();
    } catch (_) {
      _freeCString = null;
    }

    try {
      _drainLogs = _lib
          .lookup<NativeFunction<Pointer<Utf8> Function()>>('SbDrainLogs')
          .asFunction<Pointer<Utf8> Function()>();
    } catch (_) {
      _drainLogs = null;
    }

    // 尝试绑定新的路由规则管理函数（可能不存在于旧版DLL）
    try {
      _addRouteRule = _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>)>>('AddRouteRule')
          .asFunction<int Function(Pointer<Utf8>)>();
    } catch (_) {
      _addRouteRule = null;
    }

    try {
      _removeRouteRule = _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>)>>(
            'RemoveRouteRule',
          )
          .asFunction<int Function(Pointer<Utf8>)>();
    } catch (_) {
      _removeRouteRule = null;
    }

    try {
      _reloadConfig = _lib
          .lookup<NativeFunction<Int32 Function()>>('ReloadConfig')
          .asFunction<int Function()>();
    } catch (_) {
      _reloadConfig = null;
    }
    try {
      _replaceConfig = _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>)>>(
            'ReplaceConfig',
          )
          .asFunction<int Function(Pointer<Utf8>)>();
    } catch (_) {
      _replaceConfig = null;
    }
    try {
      _clearRouteRules = _lib
          .lookup<NativeFunction<Int32 Function()>>('ClearRouteRules')
          .asFunction<int Function()>();
    } catch (_) {
      _clearRouteRules = null;
    }

    _ffiDiag('FFI: _bindFunctions done');
  }

  String getLastError() {
    try {
      if (_getLastError == null) return '';
      final p = _getLastError!.call();
      if (p == nullptr) return '';
      final s = p.toDartString();
      try {
        _freeCString?.call(p);
      } catch (_) {}
      return s;
    } catch (_) {
      return '';
    }
  }

  /// 初始化 sing-box
  int init() {
    return _initSingBox();
  }

  /// 启动 sing-box
  int start(String configJson) {
    final configPtr = configJson.toNativeUtf8();
    try {
      return _startSingBox(configPtr);
    } finally {
      malloc.free(configPtr);
    }
  }

  /// 使用指定的 TUN FD 启动（Android 专用）
  int startWithTunFd(String configJson, int fd) {
    if (_startSingBoxWithTunFd == null) {
      // 回落到普通启动
      return start(configJson);
    }
    final configPtr = configJson.toNativeUtf8();
    try {
      final f = _startSingBoxWithTunFd as int Function(Pointer<Utf8>, int);
      return f(configPtr, fd);
    } finally {
      malloc.free(configPtr);
    }
  }

  /// 停止 sing-box
  int stop() {
    return _stopSingBox();
  }

  /// 检查是否运行中
  bool get isRunning => _isRunning() == 1;

  /// 测试配置
  int testConfig(String configJson) {
    final configPtr = configJson.toNativeUtf8();
    try {
      return _testConfig(configPtr);
    } finally {
      malloc.free(configPtr);
    }
  }

  /// 清理资源
  void cleanup() {
    _cleanup();
  }

  /// 获取版本信息
  String getVersion() {
    final p = _getVersion();
    final s = p.toDartString();
    try {
      _freeCString?.call(p);
    } catch (_) {}
    return s;
  }

  /// 拉取并清空原生日志缓冲（为空返回空字符串）
  String drainLogs() {
    try {
      if (_drainLogs == null) return '';
      final p = _drainLogs!.call();
      if (p == nullptr) return '';
      final s = p.toDartString();
      try {
        _freeCString?.call(p);
      } catch (_) {}
      return s;
    } catch (_) {
      return '';
    }
  }

  /// TLS 严格探测（最小握手）
  bool probeTLS({
    required String host,
    required int port,
    String sni = '',
    bool insecure = false,
    List<String>? alpn,
    int timeoutMs = 1500,
  }) {
    try {
      _probeTLS ??= _lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<Utf8>,
                Int32,
                Pointer<Utf8>,
                Int32,
                Pointer<Utf8>,
                Int32,
              )
            >
          >('ProbeTLS')
          .asFunction<
            int Function(
              Pointer<Utf8>,
              int,
              Pointer<Utf8>,
              int,
              Pointer<Utf8>,
              int,
            )
          >();
    } catch (_) {
      _probeTLS = null;
    }
    if (_probeTLS == null) return false;
    final h = host.toNativeUtf8();
    final s = sni.toNativeUtf8();
    final a = (alpn == null || alpn.isEmpty ? '' : alpn.join(','))
        .toNativeUtf8();
    try {
      final r = _probeTLS!(h, port, s, insecure ? 1 : 0, a, timeoutMs);
      return r == 0;
    } finally {
      malloc.free(h);
      malloc.free(s);
      malloc.free(a);
    }
  }

  /// QUIC 严格探测（最小握手，适用于 TUIC/Hysteria 等）
  bool probeQUIC({
    required String host,
    required int port,
    String sni = '',
    bool insecure = false,
    List<String>? alpn,
    int timeoutMs = 1500,
  }) {
    try {
      _probeQUIC ??= _lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<Utf8>,
                Int32,
                Pointer<Utf8>,
                Int32,
                Pointer<Utf8>,
                Int32,
              )
            >
          >('ProbeQUIC')
          .asFunction<
            int Function(
              Pointer<Utf8>,
              int,
              Pointer<Utf8>,
              int,
              Pointer<Utf8>,
              int,
            )
          >();
    } catch (_) {
      _probeQUIC = null;
    }
    if (_probeQUIC == null) return false;
    final h = host.toNativeUtf8();
    final s = sni.toNativeUtf8();
    final a = (alpn == null || alpn.isEmpty ? '' : alpn.join(','))
        .toNativeUtf8();
    try {
      final r = _probeQUIC!(h, port, s, insecure ? 1 : 0, a, timeoutMs);
      return r == 0;
    } finally {
      malloc.free(h);
      malloc.free(s);
      malloc.free(a);
    }
  }

  /// 设置日志回调（当前为空实现，原生回调未启用）
  void setLogCallback(void Function(String) callback) {
    // no-op: 若后续启用原生回调，请基于 Dart_Port/SendPort 实现线程安全回调
  }

  /// 添加临时路由规则（用于延时测试绕过VPN）
  bool addRouteRule(String ruleJson) {
    if (_addRouteRule == null) {
      print('FFI: AddRouteRule函数不可用，可能需要更新DLL');
      return false;
    }

    final rulePtr = ruleJson.toNativeUtf8();
    try {
      final result = _addRouteRule!(rulePtr);
      return result == 0;
    } finally {
      malloc.free(rulePtr);
    }
  }

  /// 移除临时路由规则
  bool removeRouteRule(String ruleJson) {
    if (_removeRouteRule == null) {
      print('FFI: RemoveRouteRule函数不可用，可能需要更新DLL');
      return false;
    }

    final rulePtr = ruleJson.toNativeUtf8();
    try {
      final result = _removeRouteRule!(rulePtr);
      return result == 0;
    } finally {
      malloc.free(rulePtr);
    }
  }

  /// 重新加载配置
  bool reloadConfig() {
    if (_reloadConfig == null) {
      print('FFI: ReloadConfig函数不可用，可能需要更新DLL');
      return false;
    }

    final result = _reloadConfig!();
    return result == 0;
  }

  /// 在线热替换配置（运行中切换节点不触发断开）
  bool replaceConfig(String configJson) {
    if (_replaceConfig == null) {
      print('FFI: ReplaceConfig函数不可用，可能需要更新DLL');
      return false;
    }
    final ptr = configJson.toNativeUtf8();
    try {
      final r = _replaceConfig!(ptr);
      return r == 0;
    } finally {
      malloc.free(ptr);
    }
  }

  /// 清空所有临时路由规则
  bool clearRouteRules() {
    if (_clearRouteRules == null) {
      print('FFI: ClearRouteRules函数不可用，可能需要更新DLL');
      return false;
    }
    final result = _clearRouteRules!();
    return result == 0;
  }

  /// 检查是否支持动态路由规则
  bool get supportsRouteRules {
    return _addRouteRule != null && _removeRouteRule != null;
  }
}

// ================== 低层诊断辅助 ==================

void _ffiDiag(String msg) {
  final line = '[FFI] $msg';
  // 控制台
  // ignore: avoid_print
  print(line);
  // 追加到 early_start.log (最佳努力，无阻塞要求)
  try {
    if (!Platform.isWindows) return; // 当前只处理 Windows
    final home = Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return;
    final dir = Directory(path.join(home, 'Documents', 'sing-box'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(path.join(dir.path, 'early_start.log'));
    file.writeAsStringSync(
      '[${DateTime.now().toIso8601String()}] $line\n',
      mode: FileMode.append,
      flush: false,
    );
  } catch (_) {}
}

int _safeFileSize(String p) {
  try {
    final f = File(p);
    if (!f.existsSync()) return -1;
    return f.lengthSync();
  } catch (_) {
    return -2;
  }
}

String _sizeHashHint(String p) {
  try {
    final size = _safeFileSize(p);
    if (size <= 0) return 'n/a';
    // 粗略 hash hint：文件长度和前 16/后 16 字节做个 XOR，避免引入完整哈希算法的耗时
    final f = File(p);
    final raf = f.openSync(mode: FileMode.read);
    final head = raf.readSync(min(16, size));
    if (size > 32) {
      raf.setPositionSync(size - 16);
    }
    final tail = raf.readSync(min(16, size));
    raf.closeSync();
    int acc = size & 0xffffffff;
    for (final b in head) acc = (acc ^ b) & 0xffffffff;
    for (final b in tail) acc = (acc.rotateLeft(5) ^ b) & 0xffffffff;
    return 'sz${size}_x${acc.toRadixString(16)}';
  } catch (_) {
    return 'n/a';
  }
}

extension _IntRotate on int {
  int rotateLeft(int n) =>
      ((this << n) & 0xffffffff) | (toUnsigned(32) >> (32 - n));
}
