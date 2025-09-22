/// 自定义路由规则模型
/// 基于 sing-box 官方规则配置规范实现
class CustomRule {
  final String id;
  final String name;
  final String description;
  final RuleType type;
  final String value;
  final String outbound;
  final bool enabled;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CustomRule({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.value,
    required this.outbound,
    this.enabled = true,
    required this.createdAt,
    this.updatedAt,
  });

  /// 生成 sing-box 配置格式的规则
  Map<String, dynamic> toSingBoxRule() {
    final rule = <String, dynamic>{};

    switch (type) {
      case RuleType.domain:
        rule['domain'] = [value];
        break;
      case RuleType.domainSuffix:
        rule['domain_suffix'] = [value];
        break;
      case RuleType.domainKeyword:
        rule['domain_keyword'] = [value];
        break;
      case RuleType.domainRegex:
        rule['domain_regex'] = [value];
        break;
      case RuleType.ipCidr:
        rule['ip_cidr'] = [value];
        break;
      case RuleType.sourceIpCidr:
        rule['source_ip_cidr'] = [value];
        break;
      case RuleType.port:
        final ports = value
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .where((e) => e != null)
            .cast<int>()
            .toList();
        if (ports.isNotEmpty) {
          rule['port'] = ports;
        }
        break;
      case RuleType.sourcePort:
        final ports = value
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .where((e) => e != null)
            .cast<int>()
            .toList();
        if (ports.isNotEmpty) {
          rule['source_port'] = ports;
        }
        break;
      case RuleType.network:
        rule['network'] = [value];
        break;
      case RuleType.protocol:
        rule['protocol'] = [value];
        break;
      case RuleType.processName:
        rule['process_name'] = [value];
        break;
    }

    rule['outbound'] = outbound;
    return rule;
  }

  /// 从 JSON 创建规则
  factory CustomRule.fromJson(Map<String, dynamic> json) {
    return CustomRule(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      type: RuleType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RuleType.domain,
      ),
      value: json['value'],
      outbound: json['outbound'],
      enabled: json['enabled'] ?? true,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'value': value,
      'outbound': outbound,
      'enabled': enabled,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// 复制规则并修改部分属性
  CustomRule copyWith({
    String? id,
    String? name,
    String? description,
    RuleType? type,
    String? value,
    String? outbound,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomRule(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      value: value ?? this.value,
      outbound: outbound ?? this.outbound,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomRule && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 规则类型枚举
/// 基于 sing-box 官方支持的规则字段
enum RuleType {
  domain('精确域名', '完全匹配域名', 'example.com'),
  domainSuffix('域名后缀', '匹配域名后缀', '.example.com'),
  domainKeyword('域名关键词', '包含指定关键词的域名', 'example'),
  domainRegex('域名正则', '使用正则表达式匹配域名', r'.*\.example\.com$'),
  ipCidr('IP地址段', '匹配IP地址范围', '192.168.1.0/24'),
  sourceIpCidr('源IP地址段', '匹配源IP地址范围', '10.0.0.0/8'),
  port('目标端口', '匹配目标端口（支持多个，用逗号分隔）', '80,443,8080'),
  sourcePort('源端口', '匹配源端口（支持多个，用逗号分隔）', '1024,2048'),
  network('网络协议', '匹配网络协议类型', 'tcp'),
  protocol('传输协议', '匹配传输协议', 'http'),
  processName('进程名称', '匹配进程名称（仅支持部分平台）', 'chrome.exe');

  const RuleType(this.displayName, this.description, this.example);

  final String displayName;
  final String description;
  final String example;

  /// 获取规则类型的图标
  String get icon {
    switch (this) {
      case RuleType.domain:
      case RuleType.domainSuffix:
      case RuleType.domainKeyword:
      case RuleType.domainRegex:
        return '🌐';
      case RuleType.ipCidr:
      case RuleType.sourceIpCidr:
        return '📍';
      case RuleType.port:
      case RuleType.sourcePort:
        return '🚪';
      case RuleType.network:
      case RuleType.protocol:
        return '🔗';
      case RuleType.processName:
        return '⚙️';
    }
  }

  /// 验证规则值是否符合格式
  bool isValidValue(String value) {
    if (value.trim().isEmpty) return false;

    switch (this) {
      case RuleType.domain:
        return _isValidDomain(value);
      case RuleType.domainSuffix:
        return _isValidDomainSuffix(value);
      case RuleType.domainKeyword:
        return value.trim().isNotEmpty;
      case RuleType.domainRegex:
        return _isValidRegex(value);
      case RuleType.ipCidr:
      case RuleType.sourceIpCidr:
        return _isValidCidr(value);
      case RuleType.port:
      case RuleType.sourcePort:
        return _isValidPorts(value);
      case RuleType.network:
        return ['tcp', 'udp', 'icmp'].contains(value.toLowerCase());
      case RuleType.protocol:
        return ['http', 'https', 'tls', 'quic'].contains(value.toLowerCase());
      case RuleType.processName:
        return value.trim().isNotEmpty;
    }
  }

  static bool _isValidDomain(String domain) {
    final domainRegex = RegExp(
      r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$',
    );
    return domainRegex.hasMatch(domain);
  }

  static bool _isValidDomainSuffix(String suffix) {
    return suffix.startsWith('.') && _isValidDomain(suffix.substring(1));
  }

  static bool _isValidRegex(String pattern) {
    try {
      RegExp(pattern);
      return true;
    } catch (e) {
      return false;
    }
  }

  static bool _isValidCidr(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return false;

    final ip = parts[0];
    final prefixLength = int.tryParse(parts[1]);

    if (prefixLength == null) return false;

    // IPv4 validation
    final ipv4Regex = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final ipv4Match = ipv4Regex.firstMatch(ip);
    if (ipv4Match != null) {
      final octets = ipv4Match.groups([1, 2, 3, 4]);
      if (octets.every((octet) => octet != null && int.parse(octet) <= 255)) {
        return prefixLength >= 0 && prefixLength <= 32;
      }
    }

    // IPv6 validation (simplified)
    if (ip.contains(':')) {
      return prefixLength >= 0 && prefixLength <= 128;
    }

    return false;
  }

  static bool _isValidPorts(String ports) {
    final portList = ports.split(',');
    for (final port in portList) {
      final portNum = int.tryParse(port.trim());
      if (portNum == null || portNum < 1 || portNum > 65535) {
        return false;
      }
    }
    return true;
  }
}

/// 出站类型枚举
enum OutboundType {
  direct('direct', '直连', '流量直接连接目标服务器'),
  proxy('proxy', '代理', '流量通过默认代理'),
  block('block', '阻断', '阻止访问目标地址'),
  reject('reject', '拒绝', '拒绝连接请求');

  const OutboundType(this.value, this.displayName, this.description);

  final String value;
  final String displayName;
  final String description;

  /// 获取出站类型的颜色
  String get colorValue {
    switch (this) {
      case OutboundType.direct:
        return '#4CAF50'; // 绿色
      case OutboundType.proxy:
        return '#2196F3'; // 蓝色
      case OutboundType.block:
        return '#F44336'; // 红色
      case OutboundType.reject:
        return '#FF9800'; // 橙色
    }
  }

  static OutboundType fromValue(String value) {
    return OutboundType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => OutboundType.direct,
    );
  }
}
