import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_config.dart';

/// VPN配置管理服务
class ConfigManager {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

  List<VPNConfig> _configs = [];
  VPNConfig? _currentConfig;

  List<VPNConfig> get configs => _configs;
  VPNConfig? get currentConfig => _currentConfig;

  /// 加载配置
  Future<void> loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configsJson = prefs.getString('vpn_configs');
    if (configsJson != null) {
      final List<dynamic> decoded = json.decode(configsJson);
      _configs = decoded.map((e) => VPNConfig.fromJson(e)).toList();
      _deduplicateConfigIds();
    } else {
      _configs = [];
    }
  }

  /// 保存配置
  Future<void> saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(_configs.map((e) => e.toJson()).toList());
    await prefs.setString('vpn_configs', encoded);
  }

  /// 添加配置
  Future<void> addConfig(VPNConfig config) async {
    _configs.add(config);
    await saveConfigs();
  }

  /// 删除配置
  Future<void> deleteConfig(int index) async {
    if (index >= 0 && index < _configs.length) {
      _configs.removeAt(index);
      await saveConfigs();
    }
  }

  /// 删除所有配置
  Future<void> deleteAllConfigs() async {
    _configs.clear();
    _currentConfig = null;
    await saveConfigs();
  }

  /// 更新配置
  Future<void> updateConfig(int index, VPNConfig config) async {
    if (index >= 0 && index < _configs.length) {
      _configs[index] = config;
      await saveConfigs();
    }
  }

  /// 设置当前配置
  void setCurrentConfig(VPNConfig? config) {
    _currentConfig = config;
  }

  /// 从链接导入配置
  Future<bool> importFromLink(String link) async {
    try {
      final config = VPNConfig.fromSubscriptionLink(link.trim());
      if (config != null) {
        await addConfig(config);
        return true;
      }
    } catch (e) {
      // 忽略错误
    }
    return false;
  }

  /// 从订阅导入配置
  Future<int> importFromSubscription(String content) async {
    final links = _extractAllLinks(content);
    int imported = 0;

    for (final link in links) {
      try {
        final config = VPNConfig.fromSubscriptionLink(link);
        if (config != null) {
          _configs.add(config);
          imported++;
        }
      } catch (e) {
        // 忽略单个链接的错误
      }
    }

    if (imported > 0) {
      await saveConfigs();
    }

    return imported;
  }

  /// 去重配置ID
  void _deduplicateConfigIds() {
    // 暂时跳过去重，因为 id 是 final 的
    // 后续可以在创建配置时就确保 ID 唯一
  }

  /// 提取所有链接
  List<String> _extractAllLinks(String text) {
    final schemes = ['vless://', 'trojan://', 'ss://', 'vmess://',
                    'hysteria://', 'hysteria2://', 'tuic://'];
    final List<String> links = [];

    for (final scheme in schemes) {
      final pattern = RegExp('$scheme[^\\s]+');
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        links.add(match.group(0)!);
      }
    }

    return links;
  }
}