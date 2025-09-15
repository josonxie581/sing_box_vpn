import 'dart:io';
import 'dart:convert';

/// Flutter 预编译脚本：自动处理 sing-box 下载和编译
///
///

void main(List<String> arguments) async {
  print('Start sing-box prebuild...');
  final force =
      arguments.contains('--force') ||
      (Platform.environment['FORCE_REBUILD'] == '1');
  // 支持 --ref <git-ref> 指定 sing-box 目标版本(tag/branch/commit)
  String? targetRef;
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--ref' && i + 1 < arguments.length) {
      targetRef = arguments[i + 1];
      break;
    }
    if (arg.startsWith('--ref=')) {
      targetRef = arg.substring('--ref='.length);
      break;
    }
  }
  targetRef ??= Platform.environment['SING_BOX_REF'];
  if (targetRef != null && targetRef.trim().isEmpty) targetRef = null;

  final projectRoot = Directory.current.path;
  // 按约定：源码位于本项目的上层目录 ../sing-box
  final parentDir = Directory(projectRoot).parent.path;
  final singboxDir = Directory('$parentDir/sing-box');
  final windowsDir = Directory('$projectRoot/windows');
  final dllPath = '$projectRoot/windows/singbox.dll';

  try {
    // 1. 检查是否已存在编译好的 DLL
    if (File(dllPath).existsSync() && !force) {
      print('✅ DLL 已存在，跳过编译（使用 --force 或设置环境变量 FORCE_REBUILD=1 可强制重建）');
      return;
    } else if (File(dllPath).existsSync() && force) {
      try {
        File(dllPath).deleteSync();
        print('🧹 已删除旧 DLL，准备重新编译');
      } catch (e) {
        print('⚠️ 删除旧 DLL 失败: $e');
      }
    }

    // 2. 解析 / 检查 Go 环境
    final goExe = await resolveGoExecutable();
    if (goExe == null) {
      print('❌ 未找到可用的 Go 可执行文件');
      print('👉 请安装 Go 1.23.x (或设置环境变量 GO_EXE=绝对路径) 然后重试');
      exit(1);
    }
    print('✅ 使用 Go: $goExe');
    final versionOk = await checkGoVersion(goExe);
    if (!versionOk) {
      print('⚠️ 检测到 Go 版本不是 1.23.x，sing-box 可能触发 linkname 符号不兼容。继续尝试构建…');
    }

    // 3. 检查 sing-box 源码（位于上层目录）
    if (!singboxDir.existsSync()) {
      print('sing-box not found in parent, cloning to parent...');
      await cloneSingBoxToParent(parentDir);
    } else {
      print('sing-box directory found in parent: ${singboxDir.path}');
    }

    // 3.1 若指定 --ref，则切换版本
    if (targetRef != null) {
      print('➡️ 切换 sing-box 到指定 ref: $targetRef');
      final fetchTags = await Process.run('git', [
        'fetch',
        '--all',
        '--tags',
      ], workingDirectory: singboxDir.path);
      if (fetchTags.exitCode != 0) {
        stderr.writeln('⚠️ fetch tags 失败: ${fetchTags.stderr}');
      }
      final checkout = await Process.run('git', [
        'checkout',
        targetRef,
      ], workingDirectory: singboxDir.path);
      if (checkout.exitCode != 0) {
        stderr.writeln('❌ git checkout $targetRef 失败: ${checkout.stderr}');
        exit(1);
      }
      final revParse = await Process.run('git', [
        'rev-parse',
        '--short',
        'HEAD',
      ], workingDirectory: singboxDir.path);
      if (revParse.exitCode == 0) {
        print('✅ 当前 sing-box 提交: ${revParse.stdout.toString().trim()}');
      }
    } else {
      print('未指定 --ref，使用当前 sing-box 版本');
    }

    // 4. 确保 windows 目录存在
    if (!windowsDir.existsSync()) {
      await windowsDir.create(recursive: true);
    }

    // 5. 编译 sing-box DLL
    print('Building sing-box integrated DLL...');
    // 在编译前，重写 native/go.mod 为最小依赖，并强制 replace 指向上层 sing-box 的绝对路径
    await rewriteMinimalGoMod(projectRoot, singboxDir.path);
    await compileSingBox(projectRoot, goExe);

    // 6. 验证编译结果
    if (File(dllPath).existsSync()) {
      print('Build success. Output: ${File(dllPath).absolute.path}');
    } else {
      print('❌ 编译失败，DLL 文件不存在');
      exit(1);
    }
  } catch (e) {
    print('Prebuild error: $e');
    exit(1);
  }
}

/// 检测 Go 版本是否形如 go1.23.*
Future<bool> checkGoVersion(String goExe) async {
  try {
    final result = await Process.run(goExe, ['version']);
    if (result.exitCode == 0) {
      final out = (result.stdout as String).trim();
      print('Go version: $out');
      return out.contains('go1.23');
    }
  } catch (_) {}
  return false;
}

/// 根据 GO_EXE / GOROOT / 常见安装路径 / PATH 定位 go 可执行文件
Future<String?> resolveGoExecutable() async {
  final env = Platform.environment;
  final candidates = <String>[];
  // 最高优先：显式指定
  if (env['GO_EXE'] != null && env['GO_EXE']!.isNotEmpty) {
    candidates.add(env['GO_EXE']!.trim());
  }
  // 其次：GOROOT
  if (env['GOROOT'] != null && env['GOROOT']!.isNotEmpty) {
    final p = Platform.isWindows
        ? '${env['GOROOT']}\\bin\\go.exe'
        : '${env['GOROOT']}/bin/go';
    candidates.add(p);
  }
  // 常见安装路径（Windows）
  if (Platform.isWindows) {
    candidates.addAll([
      r'C:\go1.23.1\bin\go.exe',
      r'C:\Go\bin\go.exe',
      r'C:\Program Files\Go\bin\go.exe',
      r'D:\Go\bin\go.exe',
      r'D:\Program Files\Go\bin\go.exe',
    ]);
  }
  // PATH 中的 go（最后）
  candidates.add('go');

  for (final c in candidates) {
    try {
      final result = await Process.run(c, ['version']);
      if (result.exitCode == 0) {
        return c;
      }
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// 下载 sing-box 源码
Future<void> cloneSingBoxToParent(String parentDir) async {
  final process = await Process.start('git', [
    'clone',
    'https://github.com/SagerNet/sing-box.git',
    'sing-box',
  ], workingDirectory: parentDir);
  process.stdout.transform(utf8.decoder).listen((data) {
    stdout.write(data);
  });
  process.stderr.transform(utf8.decoder).listen((data) {
    stderr.write(data);
  });
  final code = await process.exitCode;
  if (code != 0) {
    throw Exception('Git clone failed with code: $code');
  }
}

/// 更新 sing-box 源码（可选）
// removed updateSingBox; submodule update is preferred

/// 编译 sing-box DLL
Future<void> compileSingBox(String projectRoot, String goExe) async {
  final nativeDir = '$projectRoot/native';

  // 1. 确保 native 目录和文件存在
  await ensureNativeFiles(projectRoot);

  // 2. 设置环境变量并编译
  final env = Map<String, String>.from(Platform.environment);
  env['CGO_ENABLED'] = '1';
  env['GOOS'] = 'windows';
  env['GOARCH'] = 'amd64';
  // 提高 Go 模块的可达性
  env.putIfAbsent('GOPROXY', () => 'https://goproxy.cn,direct');
  env.putIfAbsent('GOSUMDB', () => 'sum.golang.google.cn');

  // Windows 下自动探测合适的 gcc，并设置 CC 与 PATH，便于 cgo 使用
  if (Platform.isWindows) {
    String? cc;
    // 1) 环境变量优先
    final envMingwBin = Platform.environment['MINGW64_BIN'];
    if (envMingwBin != null && envMingwBin.isNotEmpty) {
      final p = File(
        envMingwBin.endsWith('gcc.exe')
            ? envMingwBin
            : ('$envMingwBin\\gcc.exe'),
      );
      if (p.existsSync()) {
        cc = p.path;
      }
    }

    // 可选：如果提供了 MSYS2_DIR，尝试拼接 mingw64 路径
    if (cc == null) {
      final msys2Dir = Platform.environment['MSYS2_DIR'];
      if (msys2Dir != null && msys2Dir.isNotEmpty) {
        final p = File(msys2Dir.replaceAll('"', '') + r'\mingw64\bin\gcc.exe');
        if (p.existsSync()) {
          cc = p.path;
        }
      }
    }

    // 2) 常见安装路径（含 C: 与 D:）
    final candidates = <String>[
      // MSYS2 mingw64
      r'C:\\msys64\\mingw64\\bin\\gcc.exe',
      r'D:\\msys64\\mingw64\\bin\\gcc.exe',
      r'C:\\Program Files\\msys64\\mingw64\\bin\\gcc.exe',
      r'D:\\Program Files\\msys64\\mingw64\\bin\\gcc.exe',
      // MSYS2 ucrt64（也可用于 Go）
      r'C:\\msys64\\ucrt64\\bin\\gcc.exe',
      r'D:\\msys64\\ucrt64\\bin\\gcc.exe',
      r'C:\\Program Files\\msys64\\ucrt64\\bin\\gcc.exe',
      r'D:\\Program Files\\msys64\\ucrt64\\bin\\gcc.exe',
      // TDM-GCC
      r'C:\\TDM-GCC-64\\bin\\gcc.exe',
      r'C:\\TDM-GCC\\bin\\gcc.exe',
      // w64devkit（最后再考虑）
      r'C:\\tools\\w64devkit\\bin\\gcc.exe',
    ];
    for (final path in candidates) {
      if (cc != null) break;
      if (File(path).existsSync()) {
        cc = path;
      }
    }
    if (cc == null) {
      // 兜底：PATH 中查找
      try {
        final whereGcc = await Process.run('where', ['gcc']);
        if (whereGcc.exitCode == 0) {
          final lines = (whereGcc.stdout as String)
              .toString()
              .split(RegExp(r"[\r\n]+"))
              .where((e) => e.trim().isNotEmpty)
              .toList();
          if (lines.isNotEmpty) {
            cc = lines.first.trim();
          }
        }
      } catch (_) {}
    }
    if (cc != null) {
      env['CC'] = cc;
      final binDir = File(cc).parent.path;
      final currentPath = env['PATH'] ?? '';
      // 将目标工具链 bin 置于最前，避免被 w64devkit 抢占
      env['PATH'] = currentPath.toLowerCase().contains(binDir.toLowerCase())
          ? currentPath
          : "$binDir;${currentPath}";
      stdout.writeln('🛠️ 使用 C 编译器: ${env['CC']}');
      if (cc.toLowerCase().contains('w64devkit')) {
        stdout.writeln(
          '⚠️ 检测到 w64devkit。若遇到 "cgo: cannot parse gcc output _cgo_.o as ..."，请改用 MSYS2 mingw64 或 TDM-GCC 的 gcc.exe',
        );
      }
    }
  }

  // 3. 清理 go.sum 以确保根据本地 sing-box 重新解析依赖
  final goSumFile = File('$nativeDir/go.sum');
  if (goSumFile.existsSync()) {
    try {
      goSumFile.deleteSync();
    } catch (_) {}
  }

  // 4. 下载依赖
  print('📦 下载 Go 模块依赖...');
  var result = await Process.run(
    goExe,
    ['mod', 'tidy'],
    workingDirectory: nativeDir,
    environment: env,
  );

  if (result.exitCode != 0) {
    print('Go mod tidy 输出: ${result.stdout}');
    print('Go mod tidy 错误: ${result.stderr}');
    throw Exception('下载依赖失败');
  }

  result = await Process.run(
    goExe,
    ['mod', 'download'],
    workingDirectory: nativeDir,
    environment: env,
  );

  if (result.exitCode != 0) {
    print('Go mod download 输出: ${result.stdout}');
    print('Go mod download 错误: ${result.stderr}');
    throw Exception('下载依赖失败');
  }

  // 5. 编译 DLL
  print('🔨 正在编译 DLL...');
  stdout.writeln(
    '环境变量预览: CGO_ENABLED=${env['CGO_ENABLED']} GOOS=${env['GOOS']} GOARCH=${env['GOARCH']} CC=${env['CC'] ?? '未设置'}',
  );
  // 统一构建标签（需包含 gVisor 与 Wintun 支持以满足双向回退）
  const buildTags =
      'with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_v2ray_api,with_gvisor,with_tailscale';
  stdout.writeln('使用构建标签: ' + buildTags);
  result = await Process.run(
    goExe,
    [
      'build',
      '-tags',
      buildTags,
      '-trimpath',
      '-ldflags',
      '-s -w -buildid= -checklinkname=0',
      '-buildmode=c-shared',
      '-o',
      '../windows/singbox.dll',
      'singbox.go',
    ],
    workingDirectory: nativeDir,
    environment: env,
  );

  if (result.exitCode != 0) {
    print('编译输出: ${result.stdout}');
    print('编译错误: ${result.stderr}');
    final errStr = result.stderr.toString();
    if (errStr.contains('gVisor is not included')) {
      stdout.writeln('ℹ️ 检测到 gVisor 缺失提示，请确认构建标签包含 with_gvisor');
    }
    if (errStr.contains('clash api is not included')) {
      stdout.writeln(
        'ℹ️ 检测到 clash api 缺失提示：请确认已 checkout 含 experimental/clashapi 的上游版本并包含 --tags with_clash_api',
      );
    }
    throw Exception('编译 DLL 失败');
  }

  print('✅ DLL 编译完成');
}

/// 确保 native 目录和必要文件存在
Future<void> ensureNativeFiles(String projectRoot) async {
  final nativeDir = Directory('$projectRoot/native');

  if (!nativeDir.existsSync()) {
    await nativeDir.create(recursive: true);
  }

  // 确保 go.mod 存在（replace 将在编译前根据上层路径补丁进去）
  final goModFile = File('$projectRoot/native/go.mod');
  if (!goModFile.existsSync()) {
    await goModFile.writeAsString('''module singbox_native

go 1.23.1

require (
    github.com/sagernet/sing-box v0.0.0
)
''');
  }

  // 确保 Go 源文件存在（这里可以动态生成或复制）
  final goSourceFile = File('$projectRoot/native/singbox.go');
  if (!goSourceFile.existsSync()) {
    throw Exception('Go 源文件不存在: ${goSourceFile.path}');
  }
}

/// 将 replace 指向上层 sing-box 的绝对路径，避免依赖项目根联结
Future<void> patchGoModReplaceToPath(
  String projectRoot,
  String parentSingBoxPath,
) async {
  final goModFile = File('$projectRoot/native/go.mod');
  if (!goModFile.existsSync()) return;
  final content = await goModFile.readAsString();
  final absPath = Directory(
    parentSingBoxPath,
  ).absolute.path.replaceAll('\\', '/');
  final replaceLine =
      'replace github.com/sagernet/sing-box => ' + absPath + '\n';
  String updated;
  final regex = RegExp(
    r'^replace\s+github.com/sagernet/sing-box\s*=>.*$',
    multiLine: true,
  );
  if (regex.hasMatch(content)) {
    updated = content.replaceAll(
      regex,
      'replace github.com/sagernet/sing-box => ' + absPath,
    );
  } else {
    updated =
        content.trimRight() + '\n\n// 使用上层目录的 sing-box 源码\n' + replaceLine;
  }
  await goModFile.writeAsString(updated);
}

/// 用一个最小的 go.mod 覆盖 native/go.mod，并指向上层 sing-box
Future<void> rewriteMinimalGoMod(
  String projectRoot,
  String parentSingBoxPath,
) async {
  final dir = Directory('$projectRoot/native');
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  final absPath = Directory(
    parentSingBoxPath,
  ).absolute.path.replaceAll('\\', '/');

  // 检查是否使用local-sing-tun
  final localSingTunPath = Directory('$parentSingBoxPath/local-sing-tun');
  final useLocalSingTun = localSingTunPath.existsSync();

  final goMod = File('$projectRoot/native/go.mod');
  var content =
      '''module singbox_native

go 1.23.1

require (
    github.com/sagernet/sing-box v0.0.0
)

// 使用上层目录的 sing-box 源码
replace github.com/sagernet/sing-box => ${absPath}
''';

  // 如果local-sing-tun存在，则添加对应的replace指令
  if (useLocalSingTun) {
    final localSingTunAbsPath = localSingTunPath.absolute.path.replaceAll(
      '\\',
      '/',
    );
    content +=
        '''
// 使用本地的 sing-tun 源码
replace github.com/sagernet/sing-tun => ${localSingTunAbsPath}
''';
    print('✅ 检测到 local-sing-tun，将使用本地版本: $localSingTunAbsPath');
  }

  await goMod.writeAsString(content);
}
