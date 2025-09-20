// -*- coding: utf-8 -*-
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart' as pffi;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path/path.dart' as path;

/// 简单可靠的单实例管理器
/// Windows: 使用命名互斥量（CreateMutexW）确保单实例（DEBUG 允许 2 个实例）
/// 其它平台: 使用临时目录中的锁文件（DEBUG 允许第 2 个锁文件）
class SimpleSingleInstance {
  static SimpleSingleInstance? _instance;
  static SimpleSingleInstance get instance {
    _instance ??= SimpleSingleInstance._();
    return _instance!;
  }

  SimpleSingleInstance._();

  // 非 Windows 锁文件
  static const String _lockFileName = 'gsou.lock';
  static const String _lockFileNameDebug = 'gsou.debug.lock';

  // Windows 互斥量名称（Local 优先，必要时再尝试 Global）
  static const String _mtxLocalPrimary = r'Local\GsouVPN_SingleInstance_Mutex';
  static const String _mtxLocalDebug = r'Local\GsouVPN_SingleInstance_Debug2';
  static const String _mtxGlobalPrimary =
      r'Global\GsouVPN_SingleInstance_Mutex';
  static const String _mtxGlobalDebug = r'Global\GsouVPN_SingleInstance_Debug2';

  // Windows 句柄集合（可能有多个，便于释放）
  final List<int> _mutexHandles = [];
  File? _lockFile; // 非 Windows 平台使用

  // kernel32 绑定
  ffi.DynamicLibrary? _kernel32;
  late final int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<pffi.Utf16>)
  _CreateMutexW;
  late final int Function() _GetLastError;
  late final int Function(int) _CloseHandle;

  void _ensureKernel32() {
    if (_kernel32 != null) return;
    _kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    _CreateMutexW = _kernel32!
        .lookup<
          ffi.NativeFunction<
            ffi.IntPtr Function(
              ffi.Pointer<ffi.Void>,
              ffi.Int32,
              ffi.Pointer<pffi.Utf16>,
            )
          >
        >('CreateMutexW')
        .asFunction();
    _GetLastError = _kernel32!
        .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>('GetLastError')
        .asFunction();
    _CloseHandle = _kernel32!
        .lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.IntPtr)>>(
          'CloseHandle',
        )
        .asFunction();
  }

  /// 检查并创建单实例
  /// 返回 true 表示当前实例允许运行；返回 false 表示已有实例运行应退出
  Future<bool> checkAndAcquire() async {
    try {
      if (Platform.isWindows) {
        return _checkWindowsSingleInstance();
      } else {
        return await _checkUnixSingleInstance();
      }
    } catch (e) {
      print('单实例检查失败: $e');
      // 出错时允许运行，避免阻止正常启动
      return true;
    }
  }

  // Windows: 尝试占用互斥量名；返回状态并在成功时保存句柄
  _AcquireState _acquireMutexByName(String name) {
    _ensureKernel32();
    final namePtr = name.toNativeUtf16();
    try {
      final handle = _CreateMutexW(ffi.nullptr, 0, namePtr);
      if (handle == 0) {
        final err = _GetLastError();
        print('CreateMutexW($name) 失败，错误码: $err');
        return _AcquireState.error;
      }
      final last = _GetLastError();
      const ERROR_ALREADY_EXISTS = 183;
      if (last == ERROR_ALREADY_EXISTS) {
        // 已存在则不保留句柄
        _CloseHandle(handle);
        return _AcquireState.exists;
      }
      _mutexHandles.add(handle);
      return _AcquireState.acquired;
    } finally {
      pffi.calloc.free(namePtr);
    }
  }

  /// Windows 单实例逻辑
  bool _checkWindowsSingleInstance() {
    // Local Primary
    final lp = _acquireMutexByName(_mtxLocalPrimary);
    if (lp == _AcquireState.acquired) return true;
    if (lp == _AcquireState.exists) {
      if (kDebugMode) {
        final ld = _acquireMutexByName(_mtxLocalDebug);
        if (ld == _AcquireState.acquired) return true; // 第 2 个实例（DEBUG）
        return false; // 已超过 2 个，或调试互斥量创建失败
      }
      return false; // 非调试模式，严格单实例
    }

    // Local 报错时，尝试 Global
    final gp = _acquireMutexByName(_mtxGlobalPrimary);
    if (gp == _AcquireState.acquired) return true;
    if (gp == _AcquireState.exists) {
      if (kDebugMode) {
        final gd = _acquireMutexByName(_mtxGlobalDebug);
        if (gd == _AcquireState.acquired) return true;
        return false;
      }
      return false;
    }

    // 两边都失败（error），允许启动但告警
    print('警告: 无法创建命名互斥量，单实例可能失效');
    return true;
  }

  /// Unix 单实例逻辑（锁文件）
  Future<bool> _checkUnixSingleInstance() async {
    try {
      final tmp = Directory.systemTemp;
      final primaryPath = path.join(tmp.path, _lockFileName);
      final primary = File(primaryPath);
      if (!await primary.exists()) {
        await primary.create(exclusive: true);
        await primary.writeAsString(pid.toString());
        _lockFile = primary;
        print('创建锁文件成功: $primaryPath');
        return true;
      }

      if (kDebugMode) {
        final debugPath = path.join(tmp.path, _lockFileNameDebug);
        final debugFile = File(debugPath);
        if (!await debugFile.exists()) {
          await debugFile.create(exclusive: true);
          await debugFile.writeAsString(pid.toString());
          _lockFile = debugFile;
          print('创建调试锁文件成功: $debugPath');
          return true;
        }
        print('调试锁文件已存在: $debugPath');
        return false;
      }

      print('检测到锁文件存在: $primaryPath');
      return false;
    } catch (e) {
      print('创建锁文件失败: $e');
      return false;
    }
  }

  /// 释放资源
  Future<void> release() async {
    try {
      // 释放 Windows 互斥量
      if (Platform.isWindows) {
        for (final h in _mutexHandles) {
          try {
            _CloseHandle(h);
          } catch (_) {}
        }
        _mutexHandles.clear();
      }

      // 删除锁文件
      if (_lockFile != null && await _lockFile!.exists()) {
        try {
          await _lockFile!.delete();
        } catch (_) {}
        _lockFile = null;
      }

      print('单实例资源已释放');
    } catch (e) {
      print('释放单实例资源失败: $e');
    }
  }

  /// 静态方法：检查是否为唯一实例
  static Future<bool> isUniqueInstance() async {
    return await instance.checkAndAcquire();
  }

  /// 静态方法：释放资源
  static Future<void> releaseInstance() async {
    await instance.release();
  }
}

enum _AcquireState { acquired, exists, error }
