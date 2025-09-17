import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/navigation.dart';
import '../models/routing_rule_config.dart';
import '../services/routing_config_service.dart';
import '../services/geosite_manager.dart';
import 'geosite_manager_page.dart';

/// 分流规则配置页面
class RoutingConfigPage extends StatefulWidget {
  const RoutingConfigPage({super.key});

  @override
  State<RoutingConfigPage> createState() => _RoutingConfigPageState();
}

class _RoutingConfigPageState extends State<RoutingConfigPage> {
  final RoutingConfigService _configService = RoutingConfigService.instance;
  final GeositeManager _geositeManager = GeositeManager();

  List<RoutingRuleConfig> _rules = [];
  List<String> _availableRulesets = [];
  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在加载配置...';
    });

    try {
      await _configService.initialize();
      final availableRulesets = await _configService.getAvailableRulesets();

      setState(() {
        _rules = _configService.rules;
        _availableRulesets = availableRulesets;
      });
    } catch (e) {
      _showMessage('加载配置失败: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorRed : AppTheme.successGreen,
      ),
    );
  }

  Future<void> _toggleRule(String ruleId, bool enabled) async {
    try {
      await _configService.toggleRule(ruleId, enabled);
      setState(() {
        _rules = _configService.rules;
      });
      _showMessage(enabled ? '规则已启用' : '规则已禁用');
    } catch (e) {
      _showMessage('操作失败: $e', isError: true);
    }
  }

  Future<void> _showAddRuleDialog() async {
    final result = await showDialog<RoutingRuleConfig>(
      context: context,
      builder: (context) => _AddRuleDialog(
        availableRulesets: _availableRulesets,
        existingRules: _rules,
      ),
    );

    if (result != null) {
      try {
        await _configService.addRule(result);
        setState(() {
          _rules = _configService.rules;
        });
        _showMessage('规则添加成功');
      } catch (e) {
        _showMessage('添加规则失败: $e', isError: true);
      }
    }
  }

  Future<void> _deleteRule(String ruleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '确认删除',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          '确定要删除这条规则吗？',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _configService.removeRule(ruleId);
        setState(() {
          _rules = _configService.rules;
        });
        _showMessage('规则删除成功');
      } catch (e) {
        _showMessage('删除规则失败: $e', isError: true);
      }
    }
  }

  Widget _buildRuleCard(RoutingRuleConfig rule) {
    final isAvailable = _availableRulesets.contains(rule.ruleset);

    return Card(
      color: AppTheme.bgCard,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 规则类型图标
                Icon(
                  rule.type == RuleType.geoip
                      ? Icons.location_on_outlined
                      : Icons.language_outlined,
                  color: rule.type == RuleType.geoip
                      ? Colors.orange
                      : AppTheme.primaryNeon,
                  size: 20,
                ),
                const SizedBox(width: 8),
                // 规则名称
                Expanded(
                  child: Text(
                    rule.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // 出站动作标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getOutboundColor(rule.outbound).withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    rule.outbound.displayName,
                    style: TextStyle(
                      color: _getOutboundColor(rule.outbound),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 启用开关
                Switch(
                  value: rule.enabled,
                  onChanged: (value) => _toggleRule(rule.id, value),
                  activeColor: AppTheme.primaryNeon,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // 规则集名称
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? AppTheme.successGreen.withAlpha(30)
                        : AppTheme.errorRed.withAlpha(30),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    rule.ruleset,
                    style: TextStyle(
                      color: isAvailable ? AppTheme.successGreen : AppTheme.errorRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 优先级
                Text(
                  '优先级: ${rule.priority}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                // 删除按钮
                if (!_isSystemRule(rule.id))
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed),
                    onPressed: () => _deleteRule(rule.id),
                    iconSize: 20,
                  ),
              ],
            ),
            if (rule.description != null) ...[
              const SizedBox(height: 4),
              Text(
                rule.description!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (!isAvailable) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_outlined,
                      color: AppTheme.errorRed,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '规则集未下载，请先下载对应的规则集',
                        style: TextStyle(
                          color: AppTheme.errorRed,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const GeositeManagerPage(),
                          ),
                        ).then((_) => _loadData());
                      },
                      child: const Text(
                        '下载',
                        style: TextStyle(color: AppTheme.errorRed),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isSystemRule(String ruleId) {
    const systemRules = [
      'ads-block',
      'china-sites-direct',
      'china-ip-direct'
    ];
    return systemRules.contains(ruleId);
  }

  Color _getOutboundColor(OutboundAction outbound) {
    switch (outbound) {
      case OutboundAction.direct:
        return AppTheme.successGreen;
      case OutboundAction.proxy:
        return AppTheme.primaryNeon;
      case OutboundAction.block:
        return AppTheme.errorRed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Column(
        children: [
          // 顶部标题栏
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.borderColor.withAlpha(50),
                ),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => safePop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.bgDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.borderColor.withAlpha(100),
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: AppTheme.primaryNeon,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '分流规则配置',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                // 添加规则按钮
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _showAddRuleDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('添加规则'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryNeon,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // 状态信息
          if (_statusMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppTheme.primaryNeon.withAlpha(20),
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: AppTheme.primaryNeon,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // 统计信息
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.borderColor.withAlpha(100),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.route_outlined,
                  color: AppTheme.primaryNeon,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '共 ${_rules.length} 条规则，${_rules.where((r) => r.enabled).length} 条已启用',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppTheme.bgCard,
                        title: const Text(
                          '重置配置',
                          style: TextStyle(color: AppTheme.textPrimary),
                        ),
                        content: const Text(
                          '确定要重置为默认配置吗？所有自定义规则将被删除。',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text(
                              '重置',
                              style: TextStyle(color: AppTheme.errorRed),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      try {
                        await _configService.resetToDefault();
                        await _loadData();
                        _showMessage('配置已重置为默认值');
                      } catch (e) {
                        _showMessage('重置配置失败: $e', isError: true);
                      }
                    }
                  },
                  child: const Text(
                    '重置为默认',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),

          // 规则列表
          Expanded(
            child: _isLoading && _statusMessage.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryNeon,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: _rules.map(_buildRuleCard).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// 添加规则对话框
class _AddRuleDialog extends StatefulWidget {
  final List<String> availableRulesets;
  final List<RoutingRuleConfig> existingRules;

  const _AddRuleDialog({
    required this.availableRulesets,
    required this.existingRules,
  });

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priorityController = TextEditingController(text: '500');

  String? _selectedRuleset;
  RuleType _selectedType = RuleType.geosite;
  OutboundAction _selectedOutbound = OutboundAction.proxy;

  @override
  void initState() {
    super.initState();
    _updateAvailableRulesets();
  }

  void _updateAvailableRulesets() {
    final availableForType = widget.availableRulesets
        .where((ruleset) => _selectedType == RuleType.geoip
            ? ruleset.startsWith('geoip-')
            : ruleset.startsWith('geosite-'))
        .toList();

    if (availableForType.isNotEmpty &&
        (_selectedRuleset == null || !availableForType.contains(_selectedRuleset))) {
      _selectedRuleset = availableForType.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableForType = widget.availableRulesets
        .where((ruleset) => _selectedType == RuleType.geoip
            ? ruleset.startsWith('geoip-')
            : ruleset.startsWith('geosite-'))
        .toList();

    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text(
        '添加分流规则',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 规则名称
            TextField(
              controller: _nameController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '规则名称',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.borderColor),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryNeon),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 规则类型
            DropdownButtonFormField<RuleType>(
              value: _selectedType,
              dropdownColor: AppTheme.bgCard,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '规则类型',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
              items: RuleType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedType = value;
                    _updateAvailableRulesets();
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // 规则集
            DropdownButtonFormField<String>(
              value: _selectedRuleset,
              dropdownColor: AppTheme.bgCard,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '规则集',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
              items: availableForType.map((ruleset) {
                return DropdownMenuItem(
                  value: ruleset,
                  child: Text(ruleset),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedRuleset = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // 出站动作
            DropdownButtonFormField<OutboundAction>(
              value: _selectedOutbound,
              dropdownColor: AppTheme.bgCard,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '出站动作',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
              items: OutboundAction.values.map((action) {
                return DropdownMenuItem(
                  value: action,
                  child: Text(action.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedOutbound = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // 优先级
            TextField(
              controller: _priorityController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '优先级 (数字越大优先级越高)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.borderColor),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryNeon),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 描述
            TextField(
              controller: _descriptionController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '描述 (可选)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.borderColor),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryNeon),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.trim().isEmpty || _selectedRuleset == null) {
              return;
            }

            final priority = int.tryParse(_priorityController.text) ?? 500;
            final rule = RoutingRuleConfig(
              id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
              name: _nameController.text.trim(),
              type: _selectedType,
              ruleset: _selectedRuleset!,
              outbound: _selectedOutbound,
              priority: priority,
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
            );

            Navigator.of(context).pop(rule);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryNeon,
            foregroundColor: Colors.white,
          ),
          child: const Text('添加'),
        ),
      ],
    );
  }
}