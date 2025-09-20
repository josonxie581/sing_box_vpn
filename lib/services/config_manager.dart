import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_config.dart';
import '../models/subscription_info.dart';
import 'remote_subscription_service.dart';

/// VPN配置管理服务
class ConfigManager {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

  List<VPNConfig> _configs = [];
  VPNConfig? _currentConfig;
  final RemoteSubscriptionService _subscriptionService = RemoteSubscriptionService();

  // 订阅管理
  final Map<String, SubscriptionInfo> _subscriptionInfos = {};
  final Map<String, DateTime> _subscriptionLastUpdated = {};

  List<VPNConfig> get configs => _configs;
  VPNConfig? get currentConfig => _currentConfig;
  Map<String, SubscriptionInfo> get subscriptionInfos => _subscriptionInfos;
  Map<String, DateTime> get subscriptionLastUpdated => _subscriptionLastUpdated;

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

    // 加载订阅数据
    await _loadSubscriptionData();
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

  /// 从远程URL导入订阅
  Future<SubscriptionImportResult> importFromRemoteSubscription(
    String url, {
    String? userAgent,
    int timeout = 30000,
  }) async {
    try {
      print('[配置管理] 开始从远程订阅导入: $url');

      // 下载并解析订阅
      final result = await _subscriptionService.fetchSubscription(
        url,
        userAgent: userAgent,
        timeout: timeout,
      );

      // 保存订阅信息
      if (result.subscriptionInfo != null) {
        _subscriptionInfos[url] = result.subscriptionInfo!;
        print('[配置管理] 保存订阅信息: ${result.subscriptionInfo!}');
      } else {
        print('[配置管理] 订阅未提供流量信息');
      }
      _subscriptionLastUpdated[url] = DateTime.now();

      // 添加配置到列表
      int imported = 0;
      for (final config in result.configs) {
        config.subscriptionUrl = url;
        config.lastUpdated = DateTime.now();
        _configs.add(config);
        imported++;
      }

      if (imported > 0) {
        await saveConfigs();
        await _saveSubscriptionData();
      }

      print('[配置管理] 远程订阅导入完成，导入配置数: $imported');

      return SubscriptionImportResult(
        success: true,
        importedCount: imported,
        subscriptionInfo: result.subscriptionInfo,
        message: '成功导入 $imported 个配置',
      );

    } catch (e) {
      print('[配置管理] 远程订阅导入失败: $e');
      return SubscriptionImportResult(
        success: false,
        importedCount: 0,
        message: '导入失败: $e',
      );
    }
  }

  /// 更新订阅
  Future<SubscriptionUpdateResult> updateSubscription(
    String url, {
    String? userAgent,
    int timeout = 30000,
  }) async {
    try {
      print('[配置管理] 开始更新订阅: $url');

      // 获取该订阅的现有配置
      final oldConfigs = _configs.where((config) => config.subscriptionUrl == url).toList();

      // 下载新的订阅内容
      final result = await _subscriptionService.updateSubscription(
        url,
        oldConfigs,
        userAgent: userAgent,
        timeout: timeout,
      );

      // 更新订阅信息
      if (result.subscriptionResult.subscriptionInfo != null) {
        _subscriptionInfos[url] = result.subscriptionResult.subscriptionInfo!;
      }
      _subscriptionLastUpdated[url] = DateTime.now();

      // 移除旧配置
      for (final removedConfig in result.removedConfigs) {
        _configs.removeWhere((config) => config.id == removedConfig.id);
      }

      // 更新现有配置
      for (final updatedConfig in result.updatedConfigs) {
        final index = _configs.indexWhere(
          (config) => config.name == updatedConfig.name && config.server == updatedConfig.server,
        );
        if (index != -1) {
          _configs[index] = updatedConfig.copyWithSubscription(
            subscriptionUrl: url,
            lastUpdated: DateTime.now(),
          );
        }
      }

      // 添加新配置
      for (final newConfig in result.addedConfigs) {
        newConfig.subscriptionUrl = url;
        newConfig.lastUpdated = DateTime.now();
        _configs.add(newConfig);
      }

      if (result.hasChanges) {
        await saveConfigs();
        await _saveSubscriptionData();
      }

      print('[配置管理] 订阅更新完成，新增: ${result.addedConfigs.length}, 更新: ${result.updatedConfigs.length}, 删除: ${result.removedConfigs.length}');

      return SubscriptionUpdateResult(
        success: true,
        addedCount: result.addedConfigs.length,
        updatedCount: result.updatedConfigs.length,
        removedCount: result.removedConfigs.length,
        subscriptionInfo: result.subscriptionResult.subscriptionInfo,
        message: '更新完成：新增${result.addedConfigs.length}，更新${result.updatedConfigs.length}，删除${result.removedConfigs.length}',
      );

    } catch (e) {
      print('[配置管理] 更新订阅失败: $e');
      return SubscriptionUpdateResult(
        success: false,
        addedCount: 0,
        updatedCount: 0,
        removedCount: 0,
        message: '更新失败: $e',
      );
    }
  }

  /// 删除订阅（包括其所有配置）
  Future<bool> deleteSubscription(String url) async {
    try {
      // 删除该订阅的所有配置
      final removedCount = _configs.where((config) => config.subscriptionUrl == url).length;
      _configs.removeWhere((config) => config.subscriptionUrl == url);

      // 删除订阅信息
      _subscriptionInfos.remove(url);
      _subscriptionLastUpdated.remove(url);

      if (removedCount > 0) {
        await saveConfigs();
        await _saveSubscriptionData();
      }

      print('[配置管理] 删除订阅完成: $url，删除配置数: $removedCount');
      return true;

    } catch (e) {
      print('[配置管理] 删除订阅失败: $e');
      return false;
    }
  }

  /// 获取所有订阅URL
  List<String> getAllSubscriptionUrls() {
    final urls = <String>{};
    for (final config in _configs) {
      if (config.subscriptionUrl != null) {
        urls.add(config.subscriptionUrl!);
      }
    }
    return urls.toList();
  }

  /// 获取订阅的配置数量
  int getSubscriptionConfigCount(String url) {
    return _configs.where((config) => config.subscriptionUrl == url).length;
  }

  /// 保存订阅数据
  Future<void> _saveSubscriptionData() async {
    final prefs = await SharedPreferences.getInstance();

    // 保存订阅信息
    final subscriptionInfoJson = _subscriptionInfos.map(
      (url, info) => MapEntry(url, info.toJson()),
    );
    await prefs.setString('subscription_infos', json.encode(subscriptionInfoJson));

    // 保存更新时间
    final lastUpdatedJson = _subscriptionLastUpdated.map(
      (url, time) => MapEntry(url, time.millisecondsSinceEpoch),
    );
    await prefs.setString('subscription_last_updated', json.encode(lastUpdatedJson));
  }

  /// 加载订阅数据
  Future<void> _loadSubscriptionData() async {
    final prefs = await SharedPreferences.getInstance();

    // 加载订阅信息
    final subscriptionInfosJson = prefs.getString('subscription_infos');
    if (subscriptionInfosJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(subscriptionInfosJson);
        _subscriptionInfos.clear();
        decoded.forEach((url, infoJson) {
          _subscriptionInfos[url] = SubscriptionInfo.fromJson(infoJson);
        });
      } catch (e) {
        print('[配置管理] 加载订阅信息失败: $e');
      }
    }

    // 加载更新时间
    final lastUpdatedJson = prefs.getString('subscription_last_updated');
    if (lastUpdatedJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(lastUpdatedJson);
        _subscriptionLastUpdated.clear();
        decoded.forEach((url, timestamp) {
          _subscriptionLastUpdated[url] = DateTime.fromMillisecondsSinceEpoch(timestamp);
        });
      } catch (e) {
        print('[配置管理] 加载订阅更新时间失败: $e');
      }
    }
  }
}

/// 订阅导入结果
class SubscriptionImportResult {
  final bool success;
  final int importedCount;
  final SubscriptionInfo? subscriptionInfo;
  final String message;

  SubscriptionImportResult({
    required this.success,
    required this.importedCount,
    this.subscriptionInfo,
    required this.message,
  });
}

/// 订阅更新结果
class SubscriptionUpdateResult {
  final bool success;
  final int addedCount;
  final int updatedCount;
  final int removedCount;
  final SubscriptionInfo? subscriptionInfo;
  final String message;

  SubscriptionUpdateResult({
    required this.success,
    required this.addedCount,
    required this.updatedCount,
    required this.removedCount,
    this.subscriptionInfo,
    required this.message,
  });

  bool get hasChanges => addedCount > 0 || updatedCount > 0 || removedCount > 0;
}