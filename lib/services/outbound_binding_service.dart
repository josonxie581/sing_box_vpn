import 'package:shared_preferences/shared_preferences.dart';

import '../models/vpn_config.dart';
import 'config_manager.dart';

/// 管理多出站绑定与默认出站（场景）设置
/// - 支持两个额外出站标签：proxy-a、proxy-b
/// - 允许设置默认出站（route.final）：proxy / proxy-a / proxy-b
class OutboundBindingService {
  static final OutboundBindingService _instance =
      OutboundBindingService._internal();
  factory OutboundBindingService() => _instance;
  OutboundBindingService._internal();

  static OutboundBindingService get instance => _instance;

  static const _kOutboundAKey = 'outbound_binding_a_config_id';
  static const _kOutboundBKey = 'outbound_binding_b_config_id';
  static const _kFinalTagKey = 'route_final_outbound_tag';

  String? _boundAConfigId;
  String? _boundBConfigId;
  String _finalOutboundTag = 'proxy'; // 默认仍为 proxy，保持兼容

  bool _initialized = false;
  bool get isInitialized => _initialized;

  String? get outboundAConfigId => _boundAConfigId;
  String? get outboundBConfigId => _boundBConfigId;
  String get finalOutboundTag => _finalOutboundTag;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _boundAConfigId = prefs.getString(_kOutboundAKey);
    _boundBConfigId = prefs.getString(_kOutboundBKey);
    _finalOutboundTag = prefs.getString(_kFinalTagKey) ?? 'proxy';
    _initialized = true;
  }

  Future<void> setOutboundBindingA(String? configId) async {
    final prefs = await SharedPreferences.getInstance();
    _boundAConfigId = configId;
    if (configId == null || configId.isEmpty) {
      await prefs.remove(_kOutboundAKey);
    } else {
      await prefs.setString(_kOutboundAKey, configId);
    }
  }

  Future<void> setOutboundBindingB(String? configId) async {
    final prefs = await SharedPreferences.getInstance();
    _boundBConfigId = configId;
    if (configId == null || configId.isEmpty) {
      await prefs.remove(_kOutboundBKey);
    } else {
      await prefs.setString(_kOutboundBKey, configId);
    }
  }

  Future<void> setFinalOutboundTag(String tag) async {
    if (tag != 'proxy' && tag != 'proxy-a' && tag != 'proxy-b') {
      // 仅允许上述三种，避免不受控的标签导致路由失效
      tag = 'proxy';
    }
    final prefs = await SharedPreferences.getInstance();
    _finalOutboundTag = tag;
    await prefs.setString(_kFinalTagKey, tag);
  }

  /// 生成额外出站（若已绑定）：proxy-a / proxy-b
  /// - 若未绑定返回空列表
  /// - 若绑定的配置找不到，则忽略该出站
  List<Map<String, dynamic>> buildAdditionalOutbounds() {
    final result = <Map<String, dynamic>>[];
    final cfgMgr = ConfigManager();
    final List<VPNConfig> all = cfgMgr.configs;

    Map<String, dynamic>? _build(String tag, String? configId) {
      if (configId == null) return null;
      final cfg = all.firstWhere(
        (c) => c.id == configId,
        orElse: () => VPNConfig.placeholder(),
      );
      if (cfg.type == 'placeholder') return null;
      try {
        return cfg.toSingBoxOutbound(tag: tag);
      } catch (_) {
        return null;
      }
    }

    final oa = _build('proxy-a', _boundAConfigId);
    if (oa != null) result.add(oa);
    final ob = _build('proxy-b', _boundBConfigId);
    if (ob != null) result.add(ob);

    return result;
  }
}
