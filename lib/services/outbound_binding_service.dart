import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vpn_config.dart';
import '../models/dynamic_outbound.dart';
import 'config_manager.dart';

/// 管理动态多出站绑定与默认出站（场景）设置
/// - 支持基于代理节点数量动态创建出站
/// - 支持自定义出站名称
/// - 向后兼容原有的 proxy-a、proxy-b 功能
class OutboundBindingService {
  static final OutboundBindingService _instance =
      OutboundBindingService._internal();
  factory OutboundBindingService() => _instance;
  OutboundBindingService._internal();

  static OutboundBindingService get instance => _instance;

  // 新的存储键
  static const _kDynamicOutboundsKey = 'dynamic_outbounds_config';
  static const _kFinalTagKey = 'route_final_outbound_tag';

  // 向后兼容的旧存储键
  static const _kOutboundAKey = 'outbound_binding_a_config_id';
  static const _kOutboundBKey = 'outbound_binding_b_config_id';

  DynamicOutboundConfig _config = const DynamicOutboundConfig(outbounds: []);
  String _finalOutboundTag = 'proxy'; // 默认仍为 proxy，保持兼容

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // 向后兼容的访问器
  String? get outboundAConfigId => _config.findByTag('proxy-a')?.configId;
  String? get outboundBConfigId => _config.findByTag('proxy-b')?.configId;
  String get finalOutboundTag => _finalOutboundTag;

  // 新的动态出站访问器
  DynamicOutboundConfig get dynamicConfig => _config;
  List<DynamicOutbound> get dynamicOutbounds => _config.outbounds;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    // 尝试加载新的动态出站配置
    final configJson = prefs.getString(_kDynamicOutboundsKey);
    if (configJson != null) {
      try {
        final decoded = json.decode(configJson) as Map<String, dynamic>;
        _config = DynamicOutboundConfig.fromJson(decoded);
      } catch (e) {
        print('[OutboundBinding] 加载动态出站配置失败: $e');
        _config = const DynamicOutboundConfig(outbounds: []);
      }
    } else {
      // 迁移旧配置
      await _migrateFromLegacyConfig(prefs);
    }

    _finalOutboundTag = prefs.getString(_kFinalTagKey) ?? 'proxy';
    _initialized = true;
  }

  /// 从旧配置迁移到新的动态出站配置
  Future<void> _migrateFromLegacyConfig(SharedPreferences prefs) async {
    final aConfigId = prefs.getString(_kOutboundAKey);
    final bConfigId = prefs.getString(_kOutboundBKey);

    final outbounds = <DynamicOutbound>[];

    if (aConfigId != null || bConfigId != null) {
      // 创建默认的 proxy-a 和 proxy-b
      outbounds.add(DynamicOutbound(
        tag: 'proxy-a',
        configId: aConfigId,
        displayName: '代理A',
        sortOrder: 0,
      ));
      outbounds.add(DynamicOutbound(
        tag: 'proxy-b',
        configId: bConfigId,
        displayName: '代理B',
        sortOrder: 1,
      ));

      _config = DynamicOutboundConfig(outbounds: outbounds);

      // 保存迁移后的配置
      await _saveDynamicConfig();

      // 清理旧的键
      await prefs.remove(_kOutboundAKey);
      await prefs.remove(_kOutboundBKey);

      print('[OutboundBinding] 已从旧配置迁移到动态出站配置');
    }
  }

  /// 保存动态出站配置
  Future<void> _saveDynamicConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = json.encode(_config.toJson());
    await prefs.setString(_kDynamicOutboundsKey, configJson);
  }

  // 向后兼容的方法
  Future<void> setOutboundBindingA(String? configId) async {
    await setOutboundBinding('proxy-a', configId);
  }

  Future<void> setOutboundBindingB(String? configId) async {
    await setOutboundBinding('proxy-b', configId);
  }

  /// 设置指定标签的出站绑定
  Future<void> setOutboundBinding(String tag, String? configId) async {
    final outbounds = List<DynamicOutbound>.from(_config.outbounds);
    final index = outbounds.indexWhere((o) => o.tag == tag);

    if (index >= 0) {
      // 更新现有出站
      outbounds[index] = outbounds[index].copyWith(configId: configId);
    } else if (configId != null) {
      // 创建新出站
      outbounds.add(DynamicOutbound(
        tag: tag,
        configId: configId,
        displayName: _generateDisplayName(tag),
        sortOrder: outbounds.length,
      ));
    }

    _config = _config.copyWith(outbounds: outbounds);
    await _saveDynamicConfig();
  }

  /// 生成显示名称
  String _generateDisplayName(String tag) {
    if (tag == 'proxy-a') return '代理A';
    if (tag == 'proxy-b') return '代理B';
    // 提取标签中的标识符
    final parts = tag.split('-');
    if (parts.length >= 2) {
      return '代理${parts.last.toUpperCase()}';
    }
    return tag.toUpperCase();
  }

  Future<void> setFinalOutboundTag(String tag) async {
    // 验证标签是否在可用出站中
    final availableTags = _config.availableOutboundTags;
    if (!availableTags.contains(tag)) {
      print('[OutboundBinding] 最终出站标签 "$tag" 不在可用列表中，回退到 "proxy"');
      tag = 'proxy';
    }
    final prefs = await SharedPreferences.getInstance();
    _finalOutboundTag = tag;
    await prefs.setString(_kFinalTagKey, tag);
  }

  /// 生成所有动态出站的 sing-box 配置
  List<Map<String, dynamic>> buildAdditionalOutbounds() {
    final result = <Map<String, dynamic>>[];
    final cfgMgr = ConfigManager();
    final List<VPNConfig> allConfigs = cfgMgr.configs;

    for (final outbound in _config.outbounds) {
      if (!outbound.enabled || outbound.configId == null) {
        continue;
      }

      final cfg = allConfigs.firstWhere(
        (c) => c.id == outbound.configId,
        orElse: () => VPNConfig.placeholder(),
      );

      if (cfg.type == 'placeholder') {
        print('[OutboundBinding] 配置ID ${outbound.configId} 对应的VPN配置不存在，跳过出站 ${outbound.tag}');
        continue;
      }

      try {
        final singBoxOutbound = cfg.toSingBoxOutbound(tag: outbound.tag);
        result.add(singBoxOutbound);
      } catch (e) {
        print('[OutboundBinding] 生成出站 ${outbound.tag} 配置失败: $e');
      }
    }

    return result;
  }

  /// 添加新的动态出站
  Future<void> addDynamicOutbound({
    required String tag,
    required String displayName,
    String? configId,
  }) async {
    if (DynamicOutbound.isReservedTag(tag) || !DynamicOutbound.isValidTag(tag)) {
      throw ArgumentError('无效的出站标签: $tag');
    }

    final outbounds = List<DynamicOutbound>.from(_config.outbounds);

    // 检查标签是否已存在
    if (outbounds.any((o) => o.tag == tag)) {
      throw ArgumentError('出站标签已存在: $tag');
    }

    outbounds.add(DynamicOutbound(
      tag: tag,
      configId: configId,
      displayName: displayName,
      sortOrder: outbounds.length,
    ));

    _config = _config.copyWith(outbounds: outbounds);
    await _saveDynamicConfig();
  }

  /// 更新动态出站
  Future<void> updateDynamicOutbound(
    String tag, {
    String? displayName,
    String? configId,
    bool? enabled,
  }) async {
    final outbounds = List<DynamicOutbound>.from(_config.outbounds);
    final index = outbounds.indexWhere((o) => o.tag == tag);

    if (index < 0) {
      throw ArgumentError('出站标签不存在: $tag');
    }

    outbounds[index] = outbounds[index].copyWith(
      displayName: displayName,
      configId: configId,
      enabled: enabled,
    );

    _config = _config.copyWith(outbounds: outbounds);
    await _saveDynamicConfig();
  }

  /// 删除动态出站
  Future<void> removeDynamicOutbound(String tag) async {
    if (DynamicOutbound.isReservedTag(tag)) {
      throw ArgumentError('不能删除保留的出站标签: $tag');
    }

    final outbounds = List<DynamicOutbound>.from(_config.outbounds);
    outbounds.removeWhere((o) => o.tag == tag);

    _config = _config.copyWith(outbounds: outbounds);
    await _saveDynamicConfig();

    // 如果删除的是当前的最终出站，回退到默认代理
    if (_finalOutboundTag == tag) {
      await setFinalOutboundTag('proxy');
    }
  }

  /// 根据可用配置自动生成动态出站
  Future<void> autoGenerateFromConfigs({
    int maxCount = 26,
    String prefix = 'proxy',
  }) async {
    final cfgMgr = ConfigManager();
    final configs = cfgMgr.configs;

    if (configs.isEmpty) return;

    final outbounds = <DynamicOutbound>[];

    // 保留现有的自定义出站
    outbounds.addAll(_config.outbounds);

    // 为没有绑定出站的配置创建新出站
    int index = 0;
    for (final config in configs.take(maxCount)) {
      // 检查是否已有出站绑定到这个配置
      final alreadyBound = outbounds.any((o) => o.configId == config.id);
      if (alreadyBound) continue;

      // 生成唯一标签
      String tag;
      do {
        tag = DynamicOutbound.generateTag(index, prefix: prefix);
        index++;
      } while (outbounds.any((o) => o.tag == tag) || DynamicOutbound.isReservedTag(tag));

      // 使用配置名称或生成显示名称
      final displayName = config.name.isNotEmpty
          ? config.name
          : '${config.server}:${config.port}';

      outbounds.add(DynamicOutbound(
        tag: tag,
        configId: config.id,
        displayName: displayName,
        sortOrder: outbounds.length,
      ));

      if (outbounds.length >= maxCount) break;
    }

    _config = _config.copyWith(
      outbounds: outbounds,
      autoGenerateFromConfigs: true,
    );
    await _saveDynamicConfig();
  }

  /// 获取所有可用的出站标签（包括系统保留的）
  List<String> getAvailableOutboundTags() {
    return _config.availableOutboundTags;
  }

  /// 根据标签获取出站配置
  DynamicOutbound? getOutboundByTag(String tag) {
    return _config.findByTag(tag);
  }

  /// 清除所有动态出站配置
  Future<void> clearAllDynamicOutbounds() async {
    _config = const DynamicOutboundConfig(outbounds: []);
    await _saveDynamicConfig();
  }

  /// 重置为默认配置
  Future<void> resetToDefault() async {
    await clearAllDynamicOutbounds();
    await setFinalOutboundTag('proxy');
  }
}
