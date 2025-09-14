import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
// import 'package:win32/win32.dart' as win32; // Not required; use Directory.current instead

// C 原型: typedef void (*LogCallback)(const char* msg);
typedef NativeLogC = Void Function(Pointer<Utf8>);

/// sing-box FFI 绑定
class SingBoxFFI {
  static SingBoxFFI? _instance;
  late DynamicLibrary _lib;

  // 函数指针
  late final Function _initSingBox;
  late final Function _startSingBox;
  late final Function _stopSingBox;
  late final Function _isRunning;
  late final Function _testConfig;
  late final Function _cleanup;
  late final Function _getVersion;
  Pointer<Utf8> Function()? _getLastError;
  void Function(Pointer<Utf8>)? _freeCString;

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

  /// 加载动态库
  void _loadLibrary() {
    final libraryPath = _getLibraryPath();
    _ffiDiag('FFI: _loadLibrary begin -> target=$libraryPath');

    if (!Platform.isWindows) {
      throw UnsupportedError('暂不支持该平台');
    }

    // 将工作目录切换到可执行文件目录，提升依赖 DLL 的可发现性
    try {
      final exeDir = path.dirname(Platform.resolvedExecutable);
      Directory.current = exeDir;
      _ffiDiag('FFI: set CWD to $exeDir');
    } catch (e) {
      _ffiDiag('FFI: set CWD failed: $e');
    }

    // 移除本地 Wintun 预加载：守护进程模式统一处理 TUN，应用侧不再尝试显式加载 wintun.dll

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

    // RegisterLogCallback 暂不使用

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

  /// 设置日志回调（当前为空实现，原生回调未启用）
  void setLogCallback(void Function(String) callback) {
    // no-op: 若后续启用原生回调，请基于 Dart_Port/SendPort 实现线程安全回调
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
