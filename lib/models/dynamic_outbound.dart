/// 动态出站绑定配置模型
class DynamicOutbound {
  final String tag;          // 出站标签，如 proxy-a, custom-hk
  final String? configId;    // 绑定的配置ID
  final String displayName;  // 显示名称，支持自定义
  final int sortOrder;       // 排序顺序
  final bool enabled;        // 是否启用

  const DynamicOutbound({
    required this.tag,
    this.configId,
    required this.displayName,
    this.sortOrder = 0,
    this.enabled = true,
  });

  DynamicOutbound copyWith({
    String? tag,
    String? configId,
    String? displayName,
    int? sortOrder,
    bool? enabled,
  }) {
    return DynamicOutbound(
      tag: tag ?? this.tag,
      configId: configId ?? this.configId,
      displayName: displayName ?? this.displayName,
      sortOrder: sortOrder ?? this.sortOrder,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tag': tag,
      'configId': configId,
      'displayName': displayName,
      'sortOrder': sortOrder,
      'enabled': enabled,
    };
  }

  factory DynamicOutbound.fromJson(Map<String, dynamic> json) {
    return DynamicOutbound(
      tag: json['tag'] as String,
      configId: json['configId'] as String?,
      displayName: json['displayName'] as String,
      sortOrder: json['sortOrder'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// 检查是否为系统保留的出站标签
  static bool isReservedTag(String tag) {
    const reserved = {'proxy', 'direct', 'block', 'dns-out'};
    return reserved.contains(tag);
  }

  /// 生成默认的动态出站标签
  static String generateTag(int index, {String? prefix}) {
    if (prefix != null && prefix.isNotEmpty) {
      return '${prefix.toLowerCase()}-${index + 1}';
    }
    // 使用字母序列: proxy-a, proxy-b, proxy-c...
    if (index < 26) {
      return 'proxy-${String.fromCharCode(97 + index)}';
    }
    // 超过26个使用数字: proxy-27, proxy-28...
    return 'proxy-${index + 1}';
  }

  /// 验证标签格式
  static bool isValidTag(String tag) {
    // 不能为空，不能包含空格和特殊字符，不能是保留标签
    if (tag.isEmpty || isReservedTag(tag)) return false;
    final regex = RegExp(r'^[a-z0-9\-_]+$');
    return regex.hasMatch(tag);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DynamicOutbound && other.tag == tag;
  }

  @override
  int get hashCode => tag.hashCode;

  @override
  String toString() {
    return 'DynamicOutbound(tag: $tag, configId: $configId, displayName: $displayName, enabled: $enabled)';
  }
}

/// 动态出站管理配置
class DynamicOutboundConfig {
  final List<DynamicOutbound> outbounds;
  final String finalOutboundTag;
  final bool autoGenerateFromConfigs;
  final int maxOutbounds;

  const DynamicOutboundConfig({
    required this.outbounds,
    this.finalOutboundTag = 'proxy',
    this.autoGenerateFromConfigs = false,
    this.maxOutbounds = 26,
  });

  DynamicOutboundConfig copyWith({
    List<DynamicOutbound>? outbounds,
    String? finalOutboundTag,
    bool? autoGenerateFromConfigs,
    int? maxOutbounds,
  }) {
    return DynamicOutboundConfig(
      outbounds: outbounds ?? this.outbounds,
      finalOutboundTag: finalOutboundTag ?? this.finalOutboundTag,
      autoGenerateFromConfigs: autoGenerateFromConfigs ?? this.autoGenerateFromConfigs,
      maxOutbounds: maxOutbounds ?? this.maxOutbounds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'outbounds': outbounds.map((e) => e.toJson()).toList(),
      'finalOutboundTag': finalOutboundTag,
      'autoGenerateFromConfigs': autoGenerateFromConfigs,
      'maxOutbounds': maxOutbounds,
    };
  }

  factory DynamicOutboundConfig.fromJson(Map<String, dynamic> json) {
    return DynamicOutboundConfig(
      outbounds: (json['outbounds'] as List<dynamic>?)
          ?.map((e) => DynamicOutbound.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      finalOutboundTag: json['finalOutboundTag'] as String? ?? 'proxy',
      autoGenerateFromConfigs: json['autoGenerateFromConfigs'] as bool? ?? false,
      maxOutbounds: json['maxOutbounds'] as int? ?? 26,
    );
  }

  /// 获取所有可用的出站标签
  List<String> get availableOutboundTags {
    final tags = ['proxy', 'direct', 'block'];
    tags.addAll(outbounds.where((o) => o.enabled).map((o) => o.tag));
    return tags;
  }

  /// 获取绑定的出站配置
  List<DynamicOutbound> get boundOutbounds {
    return outbounds.where((o) => o.configId != null && o.enabled).toList();
  }

  /// 根据标签查找出站
  DynamicOutbound? findByTag(String tag) {
    try {
      return outbounds.firstWhere((o) => o.tag == tag);
    } catch (e) {
      return null;
    }
  }
}