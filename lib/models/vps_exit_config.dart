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

/// Stable server-owned identity; names, countries and IPs are metadata.
class VpsExitTarget {
  const VpsExitTarget._(this.value);
  final String value;
  // Compatibility aliases for persisted legacy policies, never an inventory.
  static const direct = VpsExitTarget._('direct');
  static const australia = VpsExitTarget._('au');
  static const singapore = VpsExitTarget._('sg');
  static const australiaResidential = VpsExitTarget._('australia');
  static VpsExitTarget parse(dynamic value) {
    if (value is! String ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$').hasMatch(value)) {
      throw const FormatException('服务器出口 ID 格式无效');
    }
    return VpsExitTarget._(value);
  }

  @override
  bool operator ==(Object other) =>
      other is VpsExitTarget && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

class VpsExitPolicy {
  const VpsExitPolicy({
    this.defaultTarget = VpsExitTarget.direct,
    this.claude = VpsExitTarget.australia,
    this.openai = VpsExitTarget.direct,
    this.australiaDomains = const [],
    this.directDomains = const [],
    this.singaporeDomains = const [],
    this.australiaExitDomains = const [],
    this.domainRules = const {},
  });

  final VpsExitTarget defaultTarget;
  final VpsExitTarget claude;
  final VpsExitTarget openai;
  final List<String> australiaDomains;
  final List<String> directDomains;
  final List<String> singaporeDomains;
  final List<String> australiaExitDomains;
  final Map<String, List<String>> domainRules;
  static const legacyFields = {
    'direct': 'direct_domains',
    'au': 'australia_domains',
    'sg': 'singapore_domains',
    'australia': 'australia_exit_domains',
  };
  Map<String, List<String>> get allDomains => {
    'direct': directDomains,
    'au': australiaDomains,
    'sg': singaporeDomains,
    'australia': australiaExitDomains,
    ...domainRules,
  };

  factory VpsExitPolicy.fromJson(Map<String, dynamic> value) {
    List<String> domains(String key) {
      final items = value[key];
      if (items is! List || items.any((v) => v is! String)) {
        throw const FormatException('域名规则格式无效');
      }
      return items.cast<String>();
    }

    final generic = value.containsKey('domain_rules')
        ? _map(value['domain_rules'], field: '域名规则')
        : <String, dynamic>{};
    final parsed = <String, List<String>>{};
    for (final entry in generic.entries) {
      VpsExitTarget.parse(entry.key);
      if (entry.value is! List ||
          (entry.value as List).any((v) => v is! String)) {
        throw const FormatException('域名规则格式无效');
      }
      if (legacyFields.containsKey(entry.key) &&
          value.containsKey(legacyFields[entry.key]) &&
          domains(legacyFields[entry.key]!).isNotEmpty) {
        throw const FormatException('域名规则重复，请刷新后重试');
      }
      parsed[entry.key] = (entry.value as List).cast<String>();
    }
    return VpsExitPolicy(
      domainRules: parsed,
      defaultTarget: VpsExitTarget.parse(value['default']),
      claude: VpsExitTarget.parse(value['claude']),
      openai: VpsExitTarget.parse(value['openai']),
      australiaDomains: value.containsKey('australia_domains')
          ? domains('australia_domains')
          : const [],
      directDomains: value.containsKey('direct_domains')
          ? domains('direct_domains')
          : const [],
      singaporeDomains: value.containsKey('singapore_domains')
          ? domains('singapore_domains')
          : const [],
      australiaExitDomains: value.containsKey('australia_exit_domains')
          ? domains('australia_exit_domains')
          : const [],
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
    final sg = clean(singaporeDomains);
    final australiaExit = clean(australiaExitDomains);
    final generic = <String, List<String>>{};
    for (final entry in domainRules.entries) {
      VpsExitTarget.parse(entry.key);
      generic[entry.key] = clean(entry.value);
    }
    final combined = {
      'au': au,
      'direct': direct,
      'sg': sg,
      'australia': australiaExit,
    };
    for (final entry in generic.entries) {
      if ((combined[entry.key] ?? []).isNotEmpty) {
        throw const FormatException('域名规则重复，请刷新后重试');
      }
      combined[entry.key] = entry.value;
    }
    if (combined.length > 128) throw const FormatException('出口数量过多');
    final groups = combined.values.toList();
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        for (final a in groups[i]) {
          for (final b in groups[j]) {
            if (a == b || a.endsWith('.$b') || b.endsWith('.$a')) {
              throw const FormatException('不同出口包含重叠域名，请移除冲突规则');
            }
          }
        }
      }
    }
    return VpsExitPolicy(
      defaultTarget: defaultTarget,
      claude: claude,
      openai: openai,
      australiaDomains: au,
      directDomains: direct,
      singaporeDomains: sg,
      australiaExitDomains: australiaExit,
      domainRules: Map.unmodifiable(generic),
    );
  }

  Map<String, dynamic> toJson({
    bool includeSingapore = false,
    bool includeAustraliaExit = false,
    bool dynamicSchema = false,
  }) => dynamicSchema
      ? {
          'default': defaultTarget.value,
          'claude': claude.value,
          'openai': openai.value,
          'domain_rules': allDomains,
        }
      : {
          'default': defaultTarget.value,
          'claude': claude.value,
          'openai': openai.value,
          'australia_domains': allDomains['au'] ?? const <String>[],
          'direct_domains': allDomains['direct'] ?? const <String>[],
          // Older two-exit controllers reject fields they do not recognize.
          if (includeSingapore ||
              defaultTarget == VpsExitTarget.singapore ||
              claude == VpsExitTarget.singapore ||
              openai == VpsExitTarget.singapore ||
              (allDomains['sg'] ?? []).isNotEmpty)
            'singapore_domains': allDomains['sg'] ?? const <String>[],
          if (includeAustraliaExit ||
              defaultTarget == VpsExitTarget.australiaResidential ||
              claude == VpsExitTarget.australiaResidential ||
              openai == VpsExitTarget.australiaResidential ||
              (allDomains['australia'] ?? []).isNotEmpty)
            'australia_exit_domains':
                allDomains['australia'] ?? const <String>[],
        };
}

class VpsExitJob {
  VpsExitJob.fromJson(Map<String, dynamic> value)
    : id = _text(value['id'], 32, field: '任务编号'),
      state = _text(value['state'], 20, field: '任务状态'),
      message = value['message'] == null
          ? ''
          : _text(value['message'], 1000, allowEmpty: true, field: '任务说明') {
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
    : policySchema = value['policy_schema'] == 2 ? 2 : 1,
      revision = _text(value['revision'], 64, field: '规则版本'),
      policy = VpsExitPolicy.fromJson(_map(value['policy'], field: '出口规则')),
      externalRules = value['external_rules'] == true,
      canRollback = value['can_rollback'] == true,
      job = value['job'] == null
          ? null
          : VpsExitJob.fromJson(_map(value['job'], field: '任务')),
      exits = _map(value['exits'], field: '可用出口'),
      history = value['history'] is List
          ? List.unmodifiable(
              (value['history'] as List)
                  .take(8)
                  .map((item) => _map(item, field: '应用记录')),
            )
          : const [] {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(revision) ||
        value['external_rules'] is! bool ||
        value['can_rollback'] is! bool) {
      throw const FormatException('服务器规则状态格式无效');
    }
    if (exits.isEmpty || exits.length > 128) {
      throw const FormatException('服务器可用出口列表无效');
    }
    for (final key in exits.keys) {
      final target = VpsExitTarget.parse(key);
      final info = _map(exits[target.value], field: '出口 ${target.value}');
      _text(info['label'], 100, field: '出口 ${target.value} 名称');
      if (InternetAddress.tryParse(
            _text(info['ip'], 60, field: '出口 ${target.value} 地址'),
          ) ==
          null) {
        throw const FormatException('服务器出口地址格式无效');
      }
    }
    _checkTargets(policy);
  }
  final int policySchema;
  final String revision;
  final VpsExitPolicy policy;
  final bool externalRules;
  final bool canRollback;
  final VpsExitJob? job;
  final Map<String, dynamic> exits;
  final List<Map<String, dynamic>> history;
  List<VpsExitTarget> get availableTargets =>
      List.unmodifiable(exits.keys.map(VpsExitTarget.parse));

  void _checkTargets(VpsExitPolicy value) {
    final selected = {
      value.defaultTarget,
      value.claude,
      value.openai,
      for (final entry in value.allDomains.entries)
        if (entry.value.isNotEmpty) VpsExitTarget.parse(entry.key),
    };
    if (selected.any((target) => !exits.containsKey(target.value))) {
      throw FormatException(
        '规则引用的出口不可用：${selected.firstWhere((t) => !exits.containsKey(t.value)).value}，请刷新服务器状态后重试',
      );
    }
  }

  Map<String, dynamic> encodePolicy(VpsExitPolicy value) {
    _checkTargets(value);
    if (policySchema < 2 &&
        value.allDomains.entries.any(
          (e) =>
              e.value.isNotEmpty &&
              !VpsExitPolicy.legacyFields.containsKey(e.key),
        )) {
      throw const FormatException('服务器尚不支持动态域名规则，请升级控制服务');
    }
    return value.toJson(
      dynamicSchema: policySchema >= 2,
      includeSingapore: exits.containsKey('sg'),
      includeAustraliaExit: exits.containsKey('australia'),
    );
  }

  String label(VpsExitTarget target) =>
      (exits[target.value] as Map)['label'] as String;
  String address(VpsExitTarget target) =>
      (exits[target.value] as Map)['ip'] as String;
}

Map<String, dynamic> _map(dynamic value, {required String field}) {
  if (value is! Map) throw FormatException('服务器响应格式无效：$field');
  return Map<String, dynamic>.from(value);
}

String _text(
  dynamic value,
  int max, {
  bool allowEmpty = false,
  required String field,
}) {
  if (value is! String ||
      (!allowEmpty && value.isEmpty) ||
      value.length > max) {
    throw FormatException('服务器响应格式无效：$field');
  }
  return value;
}
