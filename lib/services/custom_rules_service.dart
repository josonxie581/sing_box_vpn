import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/custom_rule.dart';

/// 自定义规则管理服务
/// 负责自定义规则的增删改查和持久化存储
class CustomRulesService {
  static CustomRulesService? _instance;
  static CustomRulesService get instance => _instance ??= CustomRulesService._();
  CustomRulesService._();

  List<CustomRule> _rules = [];
  bool _isLoaded = false;

  /// 获取所有自定义规则
  List<CustomRule> get rules => List.unmodifiable(_rules);

  /// 获取启用的自定义规则
  List<CustomRule> get enabledRules =>
      _rules.where((rule) => rule.enabled).toList();

  /// 初始化服务，加载存储的规则
  Future<void> initialize() async {
    if (_isLoaded) return;

    try {
      await _loadRules();
      _isLoaded = true;
      print('[DEBUG] 自定义规则服务初始化完成，加载了 ${_rules.length} 条规则');
    } catch (e) {
      print('[ERROR] 自定义规则服务初始化失败: $e');
      _rules = [];
      _isLoaded = true;
    }
  }

  /// 添加自定义规则
  Future<bool> addRule(CustomRule rule) async {
    try {
      // 检查规则ID是否重复
      if (_rules.any((r) => r.id == rule.id)) {
        print('[ERROR] 规则ID重复: ${rule.id}');
        return false;
      }

      // 检查规则名称是否重复
      if (_rules.any((r) => r.name == rule.name)) {
        print('[ERROR] 规则名称重复: ${rule.name}');
        return false;
      }

      _rules.add(rule);
      await _saveRules();

      print('[DEBUG] 成功添加自定义规则: ${rule.name}');
      return true;
    } catch (e) {
      print('[ERROR] 添加自定义规则失败: $e');
      return false;
    }
  }

  /// 更新自定义规则
  Future<bool> updateRule(String id, CustomRule updatedRule) async {
    try {
      final index = _rules.indexWhere((r) => r.id == id);
      if (index == -1) {
        print('[ERROR] 未找到要更新的规则: $id');
        return false;
      }

      // 检查新名称是否与其他规则重复
      if (updatedRule.name != _rules[index].name &&
          _rules.any((r) => r.id != id && r.name == updatedRule.name)) {
        print('[ERROR] 规则名称重复: ${updatedRule.name}');
        return false;
      }

      _rules[index] = updatedRule.copyWith(
        id: id, // 确保ID不变
        updatedAt: DateTime.now(),
      );

      await _saveRules();

      print('[DEBUG] 成功更新自定义规则: ${updatedRule.name}');
      return true;
    } catch (e) {
      print('[ERROR] 更新自定义规则失败: $e');
      return false;
    }
  }

  /// 删除自定义规则
  Future<bool> deleteRule(String id) async {
    try {
      final index = _rules.indexWhere((r) => r.id == id);
      if (index == -1) {
        print('[ERROR] 未找到要删除的规则: $id');
        return false;
      }

      final ruleName = _rules[index].name;
      _rules.removeAt(index);
      await _saveRules();

      print('[DEBUG] 成功删除自定义规则: $ruleName');
      return true;
    } catch (e) {
      print('[ERROR] 删除自定义规则失败: $e');
      return false;
    }
  }

  /// 切换规则启用状态
  Future<bool> toggleRule(String id, bool enabled) async {
    try {
      final index = _rules.indexWhere((r) => r.id == id);
      if (index == -1) {
        print('[ERROR] 未找到要切换状态的规则: $id');
        return false;
      }

      _rules[index] = _rules[index].copyWith(
        enabled: enabled,
        updatedAt: DateTime.now(),
      );

      await _saveRules();

      print('[DEBUG] 成功切换规则状态: ${_rules[index].name} -> ${enabled ? '启用' : '禁用'}');
      return true;
    } catch (e) {
      print('[ERROR] 切换规则状态失败: $e');
      return false;
    }
  }

  /// 根据ID获取规则
  CustomRule? getRule(String id) {
    try {
      return _rules.firstWhere((r) => r.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 验证规则名称是否可用
  bool isRuleNameAvailable(String name, {String? excludeId}) {
    return !_rules.any((r) =>
        r.name == name && (excludeId == null || r.id != excludeId));
  }

  /// 生成唯一的规则ID
  String generateRuleId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return 'custom_rule_${timestamp}_$random';
  }

  /// 导出所有规则为JSON
  String exportRules() {
    final data = {
      'version': '1.0',
      'exportTime': DateTime.now().toIso8601String(),
      'rules': _rules.map((r) => r.toJson()).toList(),
    };
    return json.encode(data);
  }

  /// 从JSON导入规则
  Future<bool> importRules(String jsonData, {bool replaceAll = false}) async {
    try {
      final data = json.decode(jsonData) as Map<String, dynamic>;
      final rulesData = data['rules'] as List<dynamic>;

      final importedRules = rulesData
          .map((r) => CustomRule.fromJson(r as Map<String, dynamic>))
          .toList();

      if (replaceAll) {
        _rules = importedRules;
      } else {
        // 合并规则，跳过重复的ID和名称
        for (final rule in importedRules) {
          if (!_rules.any((r) => r.id == rule.id || r.name == rule.name)) {
            _rules.add(rule);
          }
        }
      }

      await _saveRules();

      print('[DEBUG] 成功导入 ${importedRules.length} 条自定义规则');
      return true;
    } catch (e) {
      print('[ERROR] 导入自定义规则失败: $e');
      return false;
    }
  }

  /// 清空所有规则
  Future<bool> clearAllRules() async {
    try {
      _rules.clear();
      await _saveRules();

      print('[DEBUG] 成功清空所有自定义规则');
      return true;
    } catch (e) {
      print('[ERROR] 清空自定义规则失败: $e');
      return false;
    }
  }

  /// 获取规则统计信息
  Map<String, int> getRulesStats() {
    final stats = <String, int>{
      'total': _rules.length,
      'enabled': _rules.where((r) => r.enabled).length,
      'disabled': _rules.where((r) => !r.enabled).length,
    };

    // 按类型统计
    for (final type in RuleType.values) {
      stats[type.name] = _rules.where((r) => r.type == type).length;
    }

    // 按出站统计
    final outbounds = _rules.map((r) => r.outbound).toSet();
    for (final outbound in outbounds) {
      stats['outbound_$outbound'] = _rules.where((r) => r.outbound == outbound).length;
    }

    return stats;
  }

  /// 生成供 sing-box 使用的规则配置
  List<Map<String, dynamic>> generateSingBoxRules() {
    return enabledRules.map((rule) => rule.toSingBoxRule()).toList();
  }

  /// 获取配置文件路径
  Future<String> _getConfigFilePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final configDir = Directory(path.join(appDir.path, 'sing-box-vpn'));

    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }

    return path.join(configDir.path, 'custom_rules.json');
  }

  /// 从文件加载规则
  Future<void> _loadRules() async {
    final filePath = await _getConfigFilePath();
    final file = File(filePath);

    if (!await file.exists()) {
      print('[DEBUG] 自定义规则文件不存在，创建默认配置');
      _rules = [];
      await _saveRules();
      return;
    }

    try {
      final content = await file.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;
      final rulesData = data['rules'] as List<dynamic>;

      _rules = rulesData
          .map((r) => CustomRule.fromJson(r as Map<String, dynamic>))
          .toList();

      print('[DEBUG] 成功加载 ${_rules.length} 条自定义规则');
    } catch (e) {
      print('[ERROR] 加载自定义规则文件失败: $e');
      _rules = [];
    }
  }

  /// 保存规则到文件
  Future<void> _saveRules() async {
    try {
      final filePath = await _getConfigFilePath();
      final file = File(filePath);

      final data = {
        'version': '1.0',
        'lastModified': DateTime.now().toIso8601String(),
        'rules': _rules.map((r) => r.toJson()).toList(),
      };

      await file.writeAsString(
        json.encode(data),
        mode: FileMode.write,
        encoding: utf8,
      );

      print('[DEBUG] 成功保存 ${_rules.length} 条自定义规则到文件');
    } catch (e) {
      print('[ERROR] 保存自定义规则文件失败: $e');
      rethrow;
    }
  }
}