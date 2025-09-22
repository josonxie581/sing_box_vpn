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

/// 出站动作 - 支持动态出站
class OutboundAction {
  final String value;
  final String displayName;
  final String description;
  final bool isDynamic;

  const OutboundAction._(this.value, this.displayName, this.description, {this.isDynamic = false});

  // 系统保留的出站动作
  static const direct = OutboundAction._('direct', '直连', '流量直接连接目标服务器');
  static const proxy = OutboundAction._('proxy', '代理(默认)', '流量通过默认代理服务器转发');
  static const block = OutboundAction._('block', '阻断', '阻止流量访问');

  // 系统预定义的出站动作（不包含动态出站）
  static const List<OutboundAction> predefinedActions = [
    direct,
    proxy,
    block,
  ];

  /// 创建动态出站动作
  static OutboundAction dynamic(String tag, String displayName, {String? description}) {
    return OutboundAction._(
      tag,
      displayName,
      description ?? '流量通过 $displayName 出站',
      isDynamic: true,
    );
  }

  /// 从字符串值创建出站动作
  static OutboundAction fromString(String value, {String? displayName}) {
    // 首先检查预定义的动作
    for (final action in predefinedActions) {
      if (action.value == value) {
        return action;
      }
    }

    // 如果不是预定义的，创建动态出站
    return OutboundAction.dynamic(
      value,
      displayName ?? value.toUpperCase(),
    );
  }

  /// 获取所有可用的出站动作（包括动态的）
  static List<OutboundAction> getAllActions({
    List<String>? dynamicTags,
    Map<String, String>? dynamicDisplayNames,
  }) {
    final actions = List<OutboundAction>.from(predefinedActions);

    if (dynamicTags != null) {
      for (final tag in dynamicTags) {
        // 跳过预定义的标签
        if (predefinedActions.any((a) => a.value == tag)) continue;

        final displayName = dynamicDisplayNames?[tag] ?? tag.toUpperCase();
        actions.add(OutboundAction.dynamic(tag, displayName));
      }
    }

    return actions;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OutboundAction && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
