import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path/path.dart' as p;

/// Shared by the VPN core and RTT worker. Linux releases only load the bundled
/// library: the installed executable can carry network capabilities.
String resolveNativeLibraryPath({
  String? operatingSystem,
  String? executablePath,
  String? workingDirectory,
  bool Function(String)? exists,
  bool allowDevelopmentPaths = kDebugMode,
}) {
  final system = operatingSystem ?? Platform.operatingSystem;
  if (system == 'android') return 'libsingbox.so';
  if (system != 'windows' && system != 'linux') {
    throw UnsupportedError('暂不支持该平台: $system');
  }
  final paths = p.Context(
    style: system == 'windows' ? p.Style.windows : p.Style.posix,
  );
  final exeDir = paths.dirname(executablePath ?? Platform.resolvedExecutable);
  final fileExists = exists ?? (file) => File(file).existsSync();
  final bundled = system == 'linux'
      ? paths.join(exeDir, 'lib', 'libsingbox.so')
      : paths.join(exeDir, 'singbox.dll');
  if (fileExists(bundled)) return bundled;
  if (system == 'linux' && allowDevelopmentPaths) {
    final development = paths.join(
      workingDirectory ?? Directory.current.path,
      'build',
      'linux-core',
      'libsingbox.so',
    );
    if (fileExists(development)) return development;
  }
  if (system == 'windows') {
    final development = paths.join(
      workingDirectory ?? Directory.current.path,
      'windows',
      'singbox.dll',
    );
    if (fileExists(development)) return development;
  }
  throw StateError('未找到 sing-box 核心: $bundled。请重新构建或安装完整程序目录。');
}
