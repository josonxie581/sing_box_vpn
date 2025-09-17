/// 路由规则配置模型
class RoutingRuleConfig {
  final String id;
  final String name;
  final RuleType type;
  final String ruleset;
  final OutboundAction outbound;
  final int priority;
  final bool enabled;
  final String? description;

  const RoutingRuleConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.ruleset,
    required this.outbound,
    required this.priority,
    this.enabled = true,
    this.description,
  });

  RoutingRuleConfig copyWith({
    String? id,
    String? name,
    RuleType? type,
    String? ruleset,
    OutboundAction? outbound,
    int? priority,
    bool? enabled,
    String? description,
  }) {
    return RoutingRuleConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      ruleset: ruleset ?? this.ruleset,
      outbound: outbound ?? this.outbound,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.value,
      'ruleset': ruleset,
      'outbound': outbound.value,
      'priority': priority,
      'enabled': enabled,
      'description': description,
    };
  }

  factory RoutingRuleConfig.fromJson(Map<String, dynamic> json) {
    return RoutingRuleConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      type: RuleType.fromString(json['type'] as String),
      ruleset: json['ruleset'] as String,
      outbound: OutboundAction.fromString(json['outbound'] as String),
      priority: json['priority'] as int,
      enabled: json['enabled'] as bool? ?? true,
      description: json['description'] as String?,
    );
  }

  /// 生成 sing-box 路由规则
  Map<String, dynamic> toSingBoxRule() {
    return {
      'rule_set': [ruleset],
      'outbound': outbound.value,
    };
  }
}

/// 规则类型
enum RuleType {
  geosite('geosite', 'Geosite 域名规则'),
  geoip('geoip', 'GeoIP 地址规则');

  const RuleType(this.value, this.displayName);

  final String value;
  final String displayName;

  static RuleType fromString(String value) {
    return RuleType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => RuleType.geosite,
    );
  }
}

/// 出站动作
enum OutboundAction {
  direct('direct', '直连', '流量直接连接目标服务器'),
  proxy('proxy', '代理', '流量通过代理服务器转发'),
  block('block', '阻断', '阻止流量访问');

  const OutboundAction(this.value, this.displayName, this.description);

  final String value;
  final String displayName;
  final String description;

  static OutboundAction fromString(String value) {
    return OutboundAction.values.firstWhere(
      (action) => action.value == value,
      orElse: () => OutboundAction.direct,
    );
  }
}