import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/routing_rule_config.dart';
import 'geosite_manager.dart';

/// 路由配置服务
/// 管理 geosite 和 geoIP 规则的配置
class RoutingConfigService {
  static final RoutingConfigService _instance =
      RoutingConfigService._internal();
  factory RoutingConfigService() => _instance;
  RoutingConfigService._internal();

  static RoutingConfigService get instance => _instance;

  List<RoutingRuleConfig> _rules = [];
  bool _initialized = false;

  List<RoutingRuleConfig> get rules => List.unmodifiable(_rules);
  bool get isInitialized => _initialized;

  /// 获取配置文件路径
  Future<String> get _configFilePath async {
    final appDir = await getApplicationSupportDirectory();
    return path.join(appDir.path, 'routing_config.json');
  }

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _loadConfig();
      _initialized = true;
      print('[RoutingConfigService] 初始化完成，加载 ${_rules.length} 条规则配置');
    } catch (e) {
      print('[RoutingConfigService] 初始化失败: $e');
      await _createDefaultConfig();
      _initialized = true;
    }
  }

  /// 加载配置
  Future<void> _loadConfig() async {
    final configPath = await _configFilePath;
    final file = File(configPath);

    if (!await file.exists()) {
      await _createDefaultConfig();
      return;
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final rulesJson = json['rules'] as List<dynamic>? ?? [];

    _rules = rulesJson
        .map((ruleJson) => RoutingRuleConfig.fromJson(ruleJson))
        .toList();
  }

  /// 创建默认配置
  Future<void> _createDefaultConfig() async {
    _rules = [
      // 基础规则（私有地址直连已硬编码到 RulesetManager 中）
      RoutingRuleConfig(
        id: 'ads-block',
        name: '广告拦截',
        type: RuleType.geosite,
        ruleset: 'geosite-ads',
        outbound: OutboundAction.block,
        priority: 900,
        description: '拦截广告和追踪网站',
      ),
      RoutingRuleConfig(
        id: 'china-sites-direct',
        name: '中国网站直连',
        type: RuleType.geosite,
        ruleset: 'geosite-cn',
        outbound: OutboundAction.direct,
        priority: 800,
        description: '中国大陆网站直接连接',
      ),
      RoutingRuleConfig(
        id: 'china-ip-direct',
        name: '中国IP直连',
        type: RuleType.geoip,
        ruleset: 'geoip-cn',
        outbound: OutboundAction.direct,
        priority: 700,
        description: '中国大陆IP地址直接连接',
      ),
      // 常用服务代理
      RoutingRuleConfig(
        id: 'overseas-proxy',
        name: '境外代理',
        type: RuleType.geosite,
        ruleset: 'geosite-geolocation-!cn',
        outbound: OutboundAction.proxy,
        priority: 600,
        // enabled: false,
        description: '所有境外服务通过代理访问',
      ),
      // RoutingRuleConfig(
      //   id: 'youtube-proxy',
      //   name: 'YouTube 代理',
      //   type: RuleType.geosite,
      //   ruleset: 'geosite-youtube',
      //   outbound: OutboundAction.proxy,
      //   priority: 590,
      //   enabled: false,
      //   description: 'YouTube 通过代理访问',
      // ),
      // RoutingRuleConfig(
      //   id: 'twitter-proxy',
      //   name: 'Twitter 代理',
      //   type: RuleType.geosite,
      //   ruleset: 'geosite-twitter',
      //   outbound: OutboundAction.proxy,
      //   priority: 580,
      //   enabled: false,
      //   description: 'Twitter 通过代理访问',
      // ),
      // RoutingRuleConfig(
      //   id: 'telegram-proxy',
      //   name: 'Telegram 代理',
      //   type: RuleType.geosite,
      //   ruleset: 'geosite-telegram',
      //   outbound: OutboundAction.proxy,
      //   priority: 570,
      //   enabled: false,
      //   description: 'Telegram 通过代理访问',
      // ),
    ];

    await _saveConfig();
  }

  /// 保存配置
  Future<void> _saveConfig() async {
    final configPath = await _configFilePath;
    final file = File(configPath);

    final config = {
      'version': '1.0',
      'rules': _rules.map((rule) => rule.toJson()).toList(),
    };

    await file.writeAsString(jsonEncode(config));
  }

  /// 添加规则
  Future<void> addRule(RoutingRuleConfig rule) async {
    _rules.add(rule);
    _sortRulesByPriority();
    await _saveConfig();
  }

  /// 更新规则
  Future<void> updateRule(RoutingRuleConfig rule) async {
    final index = _rules.indexWhere((r) => r.id == rule.id);
    if (index >= 0) {
      _rules[index] = rule;
      _sortRulesByPriority();
      await _saveConfig();
    }
  }

  /// 删除规则
  Future<void> removeRule(String ruleId) async {
    _rules.removeWhere((rule) => rule.id == ruleId);
    await _saveConfig();
  }

  /// 切换规则启用状态
  Future<void> toggleRule(String ruleId, bool enabled) async {
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index >= 0) {
      _rules[index] = _rules[index].copyWith(enabled: enabled);
      await _saveConfig();
    }
  }

  /// 按优先级排序规则
  void _sortRulesByPriority() {
    _rules.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// 获取启用的规则
  List<RoutingRuleConfig> getEnabledRules() {
    return _rules.where((rule) => rule.enabled).toList();
  }

  /// 生成 sing-box 路由规则
  List<Map<String, dynamic>> generateSingBoxRules() {
    final enabledRules = getEnabledRules();
    return enabledRules.map((rule) => rule.toSingBoxRule()).toList();
  }

  /// 获取已配置的规则集
  List<String> getConfiguredRulesets() {
    // 仅返回启用的规则对应的规则集，避免在连接时加载未启用的规则集
    return _rules
        .where((rule) => rule.enabled)
        .map((rule) => rule.ruleset)
        .toSet()
        .toList();
  }

  /// 获取可用的规则集（已下载的）
  Future<List<String>> getAvailableRulesets() async {
    final geositeManager = GeositeManager();
    return await geositeManager.getDownloadedRulesets();
  }

  /// 检查规则集是否已下载
  Future<bool> isRulesetAvailable(String ruleset) async {
    final available = await getAvailableRulesets();
    return available.contains(ruleset);
  }

  /// 获取建议的规则配置
  List<Map<String, dynamic>> getSuggestedConfigs() {
    return [
      {
        'name': '流媒体服务',
        'rules': [
          {'ruleset': 'geosite-netflix', 'outbound': 'proxy', 'priority': 650},
          {'ruleset': 'geosite-youtube', 'outbound': 'proxy', 'priority': 640},
          {'ruleset': 'geosite-spotify', 'outbound': 'proxy', 'priority': 630},
          {'ruleset': 'geosite-disney', 'outbound': 'proxy', 'priority': 620},
        ],
      },
      {
        'name': '社交媒体',
        'rules': [
          {'ruleset': 'geosite-twitter', 'outbound': 'proxy', 'priority': 580},
          {'ruleset': 'geosite-facebook', 'outbound': 'proxy', 'priority': 570},
          {
            'ruleset': 'geosite-instagram',
            'outbound': 'proxy',
            'priority': 560,
          },
          {'ruleset': 'geosite-telegram', 'outbound': 'proxy', 'priority': 550},
        ],
      },
      {
        'name': '技术服务',
        'rules': [
          {'ruleset': 'geosite-github', 'outbound': 'proxy', 'priority': 680},
          {'ruleset': 'geosite-google', 'outbound': 'proxy', 'priority': 670},
          {'ruleset': 'geosite-openai', 'outbound': 'proxy', 'priority': 660},
        ],
      },
    ];
  }

  /// 重置为默认配置
  Future<void> resetToDefault() async {
    await _createDefaultConfig();
  }

  /// 调试：打印当前所有规则
  void debugPrintRules() {
    print('[RoutingConfigService] 当前规则列表:');
    for (final rule in _rules) {
      print(
        '  - ${rule.name}: ${rule.ruleset} (${rule.enabled ? '启用' : '禁用'})',
      );
    }
  }
}
