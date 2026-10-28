import 'dart:io';

/// Connection metadata only. OpenSSH owns key material and host verification.
class VpsExitProfile {
  const VpsExitProfile({
    required this.host,
    this.port = 22,
    this.user = 'root',
    required this.identityFile,
    required this.knownHostsFile,
  });

  final String host;
  final int port;
  final String user;
  final String identityFile;
  final String knownHostsFile;

  void validate() {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.-]{0,252}$').hasMatch(host) ||
        host.contains('..') ||
        !RegExp(r'^[a-z_][a-z0-9_-]{0,31}$').hasMatch(user) ||
        port < 1 ||
        port > 65535) {
      throw const FormatException('SSH 主机、端口或用户名无效');
    }
    for (final path in [identityFile, knownHostsFile]) {
      if (path.isEmpty ||
          path.length > 4096 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
          !RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\)').hasMatch(path)) {
        throw const FormatException('请选择私钥和 known_hosts 文件的完整路径');
      }
    }
  }

  factory VpsExitProfile.fromJson(Map<String, dynamic> value) {
    const keys = {
      'version',
      'host',
      'port',
      'user',
      'identityFile',
      'knownHostsFile',
    };
    if (value['version'] != 1 ||
        value.keys.toSet().difference(keys).isNotEmpty ||
        value['host'] is! String ||
        value['user'] is! String ||
        value['port'] is! int ||
        value['identityFile'] is! String ||
        value['knownHostsFile'] is! String) {
      throw const FormatException('SSH 管理连接格式无效');
    }
    final profile = VpsExitProfile(
      host: value['host'],
      port: value['port'],
      user: value['user'],
      identityFile: value['identityFile'],
      knownHostsFile: value['knownHostsFile'],
    );
    profile.validate();
    return profile;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'host': host,
    'port': port,
    'user': user,
    'identityFile': identityFile,
    'knownHostsFile': knownHostsFile,
  };
}

enum VpsExitTarget {
  direct('direct'),
  australia('au');

  const VpsExitTarget(this.value);
  final String value;
  static VpsExitTarget parse(dynamic value) => values.firstWhere(
    (target) => target.value == value,
    orElse: () => throw const FormatException('出口类型无效'),
  );
}

class VpsExitPolicy {
  const VpsExitPolicy({
    this.defaultTarget = VpsExitTarget.direct,
    this.claude = VpsExitTarget.australia,
    this.openai = VpsExitTarget.direct,
    this.australiaDomains = const [],
    this.directDomains = const [],
  });

  final VpsExitTarget defaultTarget;
  final VpsExitTarget claude;
  final VpsExitTarget openai;
  final List<String> australiaDomains;
  final List<String> directDomains;

  factory VpsExitPolicy.fromJson(Map<String, dynamic> value) {
    List<String> domains(String key) {
      final items = value[key];
      if (items is! List || items.any((v) => v is! String)) {
        throw const FormatException('域名规则格式无效');
      }
      return items.cast<String>();
    }

    return VpsExitPolicy(
      defaultTarget: VpsExitTarget.parse(value['default']),
      claude: VpsExitTarget.parse(value['claude']),
      openai: VpsExitTarget.parse(value['openai']),
      australiaDomains: domains('australia_domains'),
      directDomains: domains('direct_domains'),
    ).normalized();
  }

  VpsExitPolicy normalized() {
    List<String> clean(List<String> values) {
      if (values.length > 80) throw const FormatException('每个出口最多填写 80 个域名');
      final result = <String>{};
      for (var value in values) {
        value = value.trim().toLowerCase();
        if (value.startsWith('*.')) value = value.substring(2);
        if (value.endsWith('.')) value = value.substring(0, value.length - 1);
        if (value.length > 253 ||
            !value.contains('.') ||
            InternetAddress.tryParse(value) != null ||
            value
                .split('.')
                .any(
                  (label) => !RegExp(
                    r'^[a-z0-9\u0080-\uffff](?:[a-z0-9\u0080-\uffff-]{0,61}[a-z0-9\u0080-\uffff])?$',
                  ).hasMatch(label),
                )) {
          throw const FormatException('请填写域名，不要包含网址、路径或端口');
        }
        result.add(value);
      }
      return List.unmodifiable(result.toList()..sort());
    }

    final au = clean(australiaDomains), direct = clean(directDomains);
    for (final a in au) {
      for (final b in direct) {
        if (a == b || a.endsWith('.$b') || b.endsWith('.$a')) {
          throw const FormatException('两个出口包含重叠域名，请移除冲突规则');
        }
      }
    }
    return VpsExitPolicy(
      defaultTarget: defaultTarget,
      claude: claude,
      openai: openai,
      australiaDomains: au,
      directDomains: direct,
    );
  }

  Map<String, dynamic> toJson() => {
    'default': defaultTarget.value,
    'claude': claude.value,
    'openai': openai.value,
    'australia_domains': australiaDomains,
    'direct_domains': directDomains,
  };
}

class VpsExitJob {
  VpsExitJob.fromJson(Map<String, dynamic> value)
    : id = _text(value['id'], 32),
      state = _text(value['state'], 20),
      message = value['message'] == null ? '' : _text(value['message'], 1000) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        !{
          'queued',
          'running',
          'succeeded',
          'unchanged',
          'failed',
        }.contains(state)) {
      throw const FormatException('服务器任务格式无效');
    }
  }
  final String id;
  final String state;
  final String message;
  bool get pending => state == 'queued' || state == 'running';
}

class VpsExitStatus {
  VpsExitStatus.fromJson(Map<String, dynamic> value)
    : revision = _text(value['revision'], 64),
      policy = VpsExitPolicy.fromJson(_map(value['policy'])),
      externalRules = value['external_rules'] == true,
      canRollback = value['can_rollback'] == true,
      job = value['job'] == null
          ? null
          : VpsExitJob.fromJson(_map(value['job'])),
      exits = _map(value['exits']),
      history = value['history'] is List
          ? List.unmodifiable((value['history'] as List).take(8).map(_map))
          : const [] {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(revision) ||
        value['external_rules'] is! bool ||
        value['can_rollback'] is! bool) {
      throw const FormatException('服务器规则状态格式无效');
    }
    for (final target in VpsExitTarget.values) {
      final info = _map(exits[target.value]);
      _text(info['label'], 100);
      if (InternetAddress.tryParse(_text(info['ip'], 60)) == null) {
        throw const FormatException('服务器出口地址格式无效');
      }
    }
  }
  final String revision;
  final VpsExitPolicy policy;
  final bool externalRules;
  final bool canRollback;
  final VpsExitJob? job;
  final Map<String, dynamic> exits;
  final List<Map<String, dynamic>> history;
  String label(VpsExitTarget target) =>
      (exits[target.value] as Map)['label'] as String;
  String address(VpsExitTarget target) =>
      (exits[target.value] as Map)['ip'] as String;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is! Map) throw const FormatException('服务器响应格式无效');
  return Map<String, dynamic>.from(value);
}

String _text(dynamic value, int max) {
  if (value is! String || value.isEmpty || value.length > max) {
    throw const FormatException('服务器响应格式无效');
  }
  return value;
}
