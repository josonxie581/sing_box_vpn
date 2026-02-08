// -*- coding: utf-8 -*-
import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Windows 权限管理工具类
/// 用于检查和处理管理员权限
class PrivilegeManager {
  static const int _tokenElevation = 20;
  static const int _tokenQuery = 0x0008;

  // Windows API 函数声明
  late final ffi.DynamicLibrary _kernel32;
  late final ffi.DynamicLibrary _advapi32;

  // GetCurrentProcess
  late final int Function() _getCurrentProcess;

  // OpenProcessToken
  late final int Function(
    int hProcess,
    int desiredAccess,
    ffi.Pointer<ffi.IntPtr> tokenHandle,
  )
  _openProcessToken;

  // GetTokenInformation
  late final int Function(
    int tokenHandle,
    int tokenInformationClass,
    ffi.Pointer<ffi.Void> tokenInformation,
    int tokenInformationLength,
    ffi.Pointer<ffi.Uint32> returnLength,
  )
  _getTokenInformation;

  // CloseHandle
  late final int Function(int hObject) _closeHandle;

  // ShellExecute (for UAC elevation) 修正: 使用 Pointer<Utf16>
  late final int Function(
    int hwnd,
    ffi.Pointer<Utf16> lpOperation,
    ffi.Pointer<Utf16> lpFile,
    ffi.Pointer<Utf16> lpParameters,
    ffi.Pointer<Utf16> lpDirectory,
    int nShowCmd,
  )
  _shellExecute;

  static PrivilegeManager? _instance;

  PrivilegeManager._() {
    // 非 Windows 平台不加载任何系统 DLL，避免崩溃
    if (!Platform.isWindows) {
      return;
    }
    try {
      _kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      _advapi32 = ffi.DynamicLibrary.open('advapi32.dll');

      _getCurrentProcess = _kernel32
          .lookup<ffi.NativeFunction<ffi.IntPtr Function()>>(
            'GetCurrentProcess',
          )
          .asFunction();

      _openProcessToken = _advapi32
          .lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.IntPtr,
                ffi.Uint32,
                ffi.Pointer<ffi.IntPtr>,
              )
            >
          >('OpenProcessToken')
          .asFunction();

      _getTokenInformation = _advapi32
          .lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.IntPtr,
                ffi.Int32,
                ffi.Pointer<ffi.Void>,
                ffi.Uint32,
                ffi.Pointer<ffi.Uint32>,
              )
            >
          >('GetTokenInformation')
          .asFunction();

      _closeHandle = _kernel32
          .lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.IntPtr)>>(
            'CloseHandle',
          )
          .asFunction();

      // 从 shell32.dll 加载 ShellExecute
      final shell32 = ffi.DynamicLibrary.open('shell32.dll');
      _shellExecute = shell32
          .lookup<
            ffi.NativeFunction<
              ffi.IntPtr Function(
                ffi.IntPtr,
                ffi.Pointer<Utf16>,
                ffi.Pointer<Utf16>,
                ffi.Pointer<Utf16>,
                ffi.Pointer<Utf16>,
                ffi.Int32,
              )
            >
          >('ShellExecuteW')
          .asFunction();
    } catch (e) {
      if (kDebugMode) {
        print('PrivilegeManager 初始化失败: $e');
      }
      rethrow;
    }
  }

  static PrivilegeManager get instance {
    _instance ??= PrivilegeManager._();
    return _instance!;
  }

  /// 检查当前进程是否以管理员权限运行
  bool isElevated() {
    if (!Platform.isWindows) return false;

    try {
      final int process = _getCurrentProcess();
      final ffi.Pointer<ffi.IntPtr> tokenHandle = calloc<ffi.IntPtr>();

      try {
        // 打开进程令牌
        final int result = _openProcessToken(process, _tokenQuery, tokenHandle);
        if (result == 0) {
          if (kDebugMode) print('OpenProcessToken 失败');
          return false;
        }

        // 获取提升信息
        final ffi.Pointer<ffi.Uint32> elevation = calloc<ffi.Uint32>();
        final ffi.Pointer<ffi.Uint32> returnLength = calloc<ffi.Uint32>();

        try {
          final int getInfoResult = _getTokenInformation(
            tokenHandle.value,
            _tokenElevation,
            elevation.cast<ffi.Void>(),
            4, // sizeof(DWORD)
            returnLength,
          );

          if (getInfoResult == 0) {
            if (kDebugMode) print('GetTokenInformation 失败');
            return false;
          }

          final bool isElevated = elevation.value != 0;
          if (kDebugMode) print('权限检查结果: ${isElevated ? "已提权" : "未提权"}');
          return isElevated;
        } finally {
          calloc.free(elevation);
          calloc.free(returnLength);
        }
      } finally {
        if (tokenHandle.value != 0) {
          _closeHandle(tokenHandle.value);
        }
        calloc.free(tokenHandle);
      }
    } catch (e) {
      if (kDebugMode) print('权限检查异常: $e');
      return false;
    }
  }

  /// 请求管理员权限重启应用
  /// [reason] 提权原因，用于显示给用户
  /// 返回 true 表示重启成功，false 表示用户取消或失败
  Future<bool> requestElevation({String reason = '启用 TUN 模式需要管理员权限'}) async {
    if (!Platform.isWindows) return false;

    try {
      // 首先尝试直接通过 ShellExecuteW 以管理员身份重新启动自身
      // 这样可避免依赖外部脚本，并减少 PowerShell 被阻止的概率
      final bool shellExecStarted = await _restartWithShellExecute();
      if (shellExecStarted) {
        // 给新进程时间启动后退出当前进程
        await Future.delayed(const Duration(milliseconds: 300));
        exit(0);
      }

      // 获取当前执行文件路径
      final String exePath = Platform.resolvedExecutable;
      final String exeDir = File(exePath).parent.path;

      // 检查是否有静默提权脚本
      final String elevateScript = '$exeDir\\tools\\silent_elevate.bat';
      final String fallbackScript =
          '${Directory.current.path}\\tools\\silent_elevate.bat';

      String? scriptPath;
      if (File(elevateScript).existsSync()) {
        scriptPath = elevateScript;
      } else if (File(fallbackScript).existsSync()) {
        scriptPath = fallbackScript;
      }

      if (scriptPath != null) {
        // 使用静默提权脚本
        if (kDebugMode) print('使用静默提权脚本: $scriptPath');
        await _restartWithElevation(scriptPath, exePath);
      } else {
        // 直接使用 PowerShell 提权
        if (kDebugMode) print('使用 PowerShell 提权');
        await _restartWithPowerShell(exePath);
      }

      // 如果到这里说明重启成功，应用即将退出
      return true;
    } catch (e) {
      if (kDebugMode) print('请求提权失败: $e');
      return false;
    }
  }

  /// 使用 ShellExecuteW 以 runas 模式重新启动当前进程
  /// 返回是否成功发起（不代表新进程业务已完全就绪）
  Future<bool> _restartWithShellExecute() async {
    if (!Platform.isWindows) return false;
    try {
      final String exePath = Platform.resolvedExecutable;
      // operation = 'runas'
      final opPtr = 'runas'.toNativeUtf16();
      final filePtr = exePath.toNativeUtf16();
      // 可根据需要传递参数，这里保持与当前参数一致（忽略 dart vm 参数差异）
      final paramsPtr = ''.toNativeUtf16();
      final dirPtr = ''.toNativeUtf16();
      try {
        final int hInstance = _shellExecute(
          0,
          opPtr,
          filePtr,
          paramsPtr,
          dirPtr,
          1, // SW_SHOWNORMAL
        );

        // ShellExecute 返回值 > 32 表示成功
        if (hInstance <= 32) {
          if (kDebugMode) print('ShellExecuteW 提权启动失败 hInstance=$hInstance');
          return false;
        }
        if (kDebugMode) print('ShellExecuteW 已发起提权重启');
        return true;
      } finally {
        calloc.free(opPtr);
        calloc.free(filePtr);
        calloc.free(paramsPtr);
        calloc.free(dirPtr);
      }
    } catch (e) {
      if (kDebugMode) print('ShellExecuteW 调用异常: $e');
      return false;
    }
  }

  /// 使用静默提权脚本重启
  Future<void> _restartWithElevation(String scriptPath, String exePath) async {
    final ProcessResult result = await Process.run(scriptPath, [
      exePath,
    ], runInShell: true);

    if (kDebugMode) {
      print('提权脚本执行结果: ${result.exitCode}');
      if (result.stderr.toString().isNotEmpty) {
        print('stderr: ${result.stderr}');
      }
    }

    // 给提权的新进程一点时间启动
    await Future.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  /// 使用 PowerShell 提权重启
  Future<void> _restartWithPowerShell(String exePath) async {
    final String powershellCmd =
        '''
Start-Process -FilePath "$exePath" -Verb RunAs -WindowStyle Normal
''';

    final ProcessResult result = await Process.run('powershell.exe', [
      '-WindowStyle',
      'Hidden',
      '-Command',
      powershellCmd,
    ]);

    if (kDebugMode) {
      print('PowerShell 提权结果: ${result.exitCode}');
      if (result.stderr.toString().isNotEmpty) {
        print('stderr: ${result.stderr}');
      }
    }

    // 给提权的新进程一点时间启动
    await Future.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  /// 检查 TUN 模式的可用性
  /// 返回状态信息
  TunAvailability checkTunAvailability() {
    // Android 使用 VpnService，应用内可用
    if (Platform.isAndroid) {
      return TunAvailability.available;
    }
    if (!Platform.isWindows) {
      return TunAvailability.notSupported;
    }

    // 检查是否有管理员权限
    if (!isElevated()) {
      return TunAvailability.needElevation;
    }

    // 检查 wintun.dll 是否存在
    final String exeDir = File(Platform.resolvedExecutable).parent.path;
    final String wintunPath = '$exeDir\\wintun.dll';

    if (!File(wintunPath).existsSync()) {
      // 在开发环境中检查项目目录
      final String devWintunPath =
          '${Directory.current.path}\\windows\\wintun.dll';
      if (!File(devWintunPath).existsSync()) {
        return TunAvailability.missingWintun;
      }
    }

    return TunAvailability.available;
  }
}

/// TUN 模式可用性状态
enum TunAvailability {
  /// 可用
  available,

  /// 需要管理员权限
  needElevation,

  /// 缺少 wintun.dll
  missingWintun,

  /// 平台不支持
  notSupported,
}

/// 扩展方法
extension TunAvailabilityExtension on TunAvailability {
  String get description {
    switch (this) {
      case TunAvailability.available:
        return 'TUN 模式可用';
      case TunAvailability.needElevation:
        return '需要管理员权限';
      case TunAvailability.missingWintun:
        return '缺少 wintun.dll';
      case TunAvailability.notSupported:
        return '平台不支持';
    }
  }

  bool get isAvailable => this == TunAvailability.available;
  bool get needsElevation => this == TunAvailability.needElevation;
}
