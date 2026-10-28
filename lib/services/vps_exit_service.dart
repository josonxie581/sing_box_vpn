import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vps_exit_config.dart';

abstract interface class VpsExitTransport {
  Future<Map<String, dynamic>> call(
    VpsExitProfile profile,
    String action, [
    Map<String, dynamic> data = const {},
  ]);
  Future<Map<String, dynamic>> deploy(VpsExitProfile profile);
}

class VpsSshResult {
  const VpsSshResult(this.exitCode, this.output, this.error);
  final int exitCode;
  final String output;
  final String error;
}

abstract interface class VpsSshRunner {
  Future<VpsSshResult> run(
    String executable,
    List<String> arguments,
    String input, {
    Duration timeout = const Duration(seconds: 35),
  });
}

class OpenSshVpsRunner implements VpsSshRunner {
  @override
  Future<VpsSshResult> run(
    String executable,
    List<String> arguments,
    String input, {
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
    );
    Future<String> bounded(Stream<List<int>> stream) async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (bytes.length + chunk.length > 131072) {
          process.kill();
          throw const FormatException('SSH 响应过长');
        }
        bytes.add(chunk);
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    }

    final result = Future.wait<Object>([
      bounded(process.stdout),
      bounded(process.stderr),
      process.exitCode,
    ]);
    try {
      final values = await (() async {
        process.stdin.add(utf8.encode(input));
        await process.stdin.close();
        return await result;
      })().timeout(timeout);
      return VpsSshResult(
        values[2] as int,
        values[0] as String,
        values[1] as String,
      );
    } on Object {
      process.kill();
      // Drain output and reap the short-lived SSH process, never the VPN client.
      try {
        await result.timeout(const Duration(seconds: 3));
      } on Object {
        /* Already reported to the caller. */
      }
      rethrow;
    }
  }
}

class VpsExitService implements VpsExitTransport {
  VpsExitService({
    VpsSshRunner? runner,
    AssetBundle? assets,
    Future<bool> Function(String)? fileExists,
    bool? windows,
  }) : _runner = runner ?? OpenSshVpsRunner(),
       _assets = assets ?? rootBundle,
       _fileExists = fileExists ?? ((path) => File(path).exists()),
       _windows = windows ?? Platform.isWindows;

  final VpsSshRunner _runner;
  final AssetBundle _assets;
  final Future<bool> Function(String) _fileExists;
  final bool _windows;
  static const _preference = 'vps_exit_management_profile_v1';
  static const bundleFiles = [
    'vpn_policy.py',
    'vpn_runtime.py',
    'vpn_routes_service.py',
    'shaowei-vpn-routes.service',
  ];

  static Future<VpsExitProfile?> loadProfile() async {
    final value = (await SharedPreferences.getInstance()).getString(
      _preference,
    );
    if (value == null) return null;
    return VpsExitProfile.fromJson(
      Map<String, dynamic>.from(jsonDecode(value) as Map),
    );
  }

  static Future<void> saveProfile(VpsExitProfile profile) async {
    profile.validate();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_preference, jsonEncode(profile.toJson()))) {
      throw const FormatException('无法保存 SSH 连接设置');
    }
  }

  static const _bridge = r'''
import json,socket,sys
try:
 raw=sys.stdin.buffer.read(32769)
 if len(raw)>32768:raise ValueError()
 with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as client:
  client.settimeout(25);client.connect('/run/shaowei-vpn/control.sock')
  client.sendall(raw.rstrip(b'\n')+b'\n')
  with client.makefile('rb') as response:data=response.readline(131073)
 if len(data)>131072 or not data.endswith(b'\n'):raise ValueError()
 sys.stdout.buffer.write(data)
except Exception:
 print(json.dumps({'ok':False,'error':'未连接到 VPS 出口控制服务，请先部署或检查 SSH 管理权限'}))
''';

  static String commandFor(String trustedScript) =>
      "/usr/bin/python3 -c '${trustedScript.replaceAll("'", "'\\''")}'";

  static List<String> sshArguments(VpsExitProfile profile, String command) {
    profile.validate();
    return [
      '-T',
      '-F',
      'NUL',
      '-o',
      'BatchMode=yes',
      '-o',
      'IdentitiesOnly=yes',
      '-o',
      'StrictHostKeyChecking=yes',
      '-o',
      'UpdateHostKeys=no',
      '-o',
      'UserKnownHostsFile=${profile.knownHostsFile}',
      '-o',
      'GlobalKnownHostsFile=NUL',
      '-o',
      'ConnectTimeout=8',
      '-o',
      'ServerAliveInterval=10',
      '-o',
      'ServerAliveCountMax=2',
      '-i',
      profile.identityFile,
      '-p',
      '${profile.port}',
      '${profile.user}@${profile.host}',
      command,
    ];
  }

  Future<Map<String, dynamic>> _execute(
    VpsExitProfile profile,
    String script,
    Map<String, dynamic> payload, {
    bool installing = false,
  }) async {
    if (!_windows) throw const FormatException('VPS SSH 出口管控目前支持 Windows');
    profile.validate();
    if (!await _fileExists(profile.identityFile) ||
        !await _fileExists(profile.knownHostsFile)) {
      throw const FormatException('私钥或 known_hosts 文件不存在，请重新选择');
    }
    final input = '${jsonEncode(payload)}\n';
    if (utf8.encode(input).length > (installing ? 262144 : 32768)) {
      throw const FormatException('配置内容过长');
    }
    VpsSshResult result;
    try {
      result = await _runner.run(
        'ssh.exe',
        sshArguments(profile, commandFor(script)),
        input,
        timeout: Duration(seconds: installing ? 120 : 40),
      );
    } on TimeoutException {
      throw const FormatException('SSH 请求超时；如已提交应用，请刷新状态核对，不要重复提交');
    } on ProcessException {
      throw const FormatException('无法启动 Windows OpenSSH，请检查系统 SSH 客户端');
    }
    Map<String, dynamic>? response;
    try {
      response = Map<String, dynamic>.from(jsonDecode(result.output) as Map);
    } on Object {
      /* Transport failures intentionally omit raw stderr. */
    }
    if (response?['ok'] == false && response?['error'] is String) {
      final error = response!['error'] as String;
      throw FormatException(error.length <= 1000 ? error : '服务器操作失败');
    }
    if (result.exitCode != 0 ||
        response?['ok'] != true ||
        response?['result'] is! Map) {
      if (result.error.contains('Host key verification failed') ||
          result.error.contains('REMOTE HOST IDENTIFICATION')) {
        throw const FormatException('SSH 主机校验失败，请核对可信主机指纹与 known_hosts 文件');
      }
      throw const FormatException('SSH 管理连接失败，请检查账号、密钥权限和服务器服务状态');
    }
    return Map<String, dynamic>.from(response!['result'] as Map);
  }

  @override
  Future<Map<String, dynamic>> call(
    VpsExitProfile profile,
    String action, [
    Map<String, dynamic> data = const {},
  ]) {
    if (!{'status', 'validate', 'apply', 'rollback'}.contains(action) ||
        data.keys.any(
          (key) => !{'policy', 'expected_revision'}.contains(key),
        )) {
      throw const FormatException('不支持的出口管理操作');
    }
    return _execute(profile, _bridge, {
      'action': action,
      'actor': 'Gsou-${profile.user}',
      ...data,
    });
  }

  @override
  Future<Map<String, dynamic>> deploy(VpsExitProfile profile) async {
    if (profile.user != 'root') {
      throw const FormatException('部署控制服务需要 root 管理账号');
    }
    final files = <String, String>{};
    for (final name in bundleFiles) {
      files[name] = base64Encode(
        utf8.encode(await _assets.loadString('assets/vps_exit/$name')),
      );
    }
    final manifest = jsonDecode(
      await _assets.loadString('assets/vps_exit/manifest.json'),
    );
    final installer = await _assets.loadString('assets/vps_exit/install.py');
    return _execute(profile, installer, {
      'files': files,
      'sha256': manifest,
    }, installing: true);
  }
}
