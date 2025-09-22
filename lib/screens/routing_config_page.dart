import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/navigation.dart';
import '../models/routing_rule_config.dart';
import '../models/dynamic_outbound.dart';
import '../services/routing_config_service.dart';
import 'geosite_manager_page.dart';
import 'add_routing_rule_page.dart';
import '../services/outbound_binding_service.dart';
import '../services/config_manager.dart';
import '../models/vpn_config.dart';

/// 分流规则配置页面
class RoutingConfigPage extends StatefulWidget {
  final int initialTabIndex;
  const RoutingConfigPage({super.key, this.initialTabIndex = 0});

  @override
  State<RoutingConfigPage> createState() => _RoutingConfigPageState();
}

class _RoutingConfigPageState extends State<RoutingConfigPage>
    with SingleTickerProviderStateMixin {
  final RoutingConfigService _configService = RoutingConfigService.instance;
  final OutboundBindingService _binding = OutboundBindingService.instance;
  final ConfigManager _cfgMgr = ConfigManager();

  late TabController _tabController;

  // State
  List<RoutingRuleConfig> _rules = [];
  List<String> _availableRulesets = [];
  bool _isLoading = false;
  String _statusMessage = '';

  // Outbound binding state
  List<VPNConfig> _configs = const [];
  List<DynamicOutbound> _dynamicOutbounds = [];
  String _finalTag = 'proxy';
  bool _isFinalSelectorExpanded = false;

  @override
  void initState() {
    super.initState();
    final idx = widget.initialTabIndex < 0
        ? 0
        : (widget.initialTabIndex > 1 ? 1 : widget.initialTabIndex);
    _tabController = TabController(length: 2, vsync: this, initialIndex: idx);
    _loadData();
    _initBinding();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });
    try {
      await _configService.initialize();
      final available = await _configService.getAvailableRulesets();
      setState(() {
        _rules = _configService.rules;
        _availableRulesets = available;
      });
    } catch (e) {
      setState(() {
        _statusMessage = '加载失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _initBinding() async {
    try {
      if (_cfgMgr.configs.isEmpty) {
        await _cfgMgr.loadConfigs();
      }
      if (!_binding.isInitialized) {
        await _binding.initialize();
      }
      if (!mounted) return;
      setState(() {
        _configs = List<VPNConfig>.from(_cfgMgr.configs);
        _dynamicOutbounds = List<DynamicOutbound>.from(_binding.dynamicOutbounds);
        _finalTag = _binding.finalOutboundTag;
      });
    } catch (e) {
      // 忽略展示错误，UI 保持可用
    }
  }

  Future<void> _saveBinding() async {
    setState(() => _isLoading = true);
    try {
      // 保存所有动态出站
      for (final outbound in _dynamicOutbounds) {
        await _binding.setOutboundBinding(outbound.tag, outbound.configId);
      }
      await _binding.setFinalOutboundTag(_finalTag);
      _showMessage('已保存出站绑定（重新连接后生效）');
    } catch (e) {
      _showMessage('保存失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 重置所有出站绑定设置
  Future<void> _resetBindings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '确认重置',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          '确定要重置所有出站绑定设置吗？这将清除所有动态出站并重置为默认状态。',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重置', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        // 使用服务方法重置为默认配置
        await _binding.resetToDefault();

        // 重新加载绑定状态
        await _initBinding();

        _showMessage('已重置所有出站绑定设置');
      } catch (e) {
        _showMessage('重置失败: $e', isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleRule(String ruleId, bool enabled) async {
    try {
      await _configService.toggleRule(ruleId, enabled);
      await _loadData();
      _showMessage('已${enabled ? '启用' : '禁用'}');
    } catch (e) {
      _showMessage('操作失败: $e', isError: true);
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
          '删除后不可恢复，确定继续吗？',
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
        await _loadData();
        _showMessage('已删除');
      } catch (e) {
        _showMessage('删除失败: $e', isError: true);
      }
    }
  }

  Future<void> _openRulesetManager() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const GeositeManagerPage()));
    await _loadData();
  }

  Future<void> _showAddRuleDialog() async {
    final result = await Navigator.of(context).push<RoutingRuleConfig>(
      MaterialPageRoute(
        builder: (_) => AddRoutingRulePage(
          availableRulesets: _availableRulesets,
          existingRules: _rules,
        ),
      ),
    );

    if (result != null) {
      try {
        await _configService.addRule(result);
        await _loadData();
        _showMessage('已添加规则');
      } catch (e) {
        _showMessage('添加失败: $e', isError: true);
      }
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: isError ? AppTheme.errorRed : AppTheme.successGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 系统内置规则不可删除
  bool _isSystemRule(String ruleId) {
    const systemRules = [
      'ads-block',
      'china-sites-direct',
      'china-ip-direct',
      'overseas-proxy',
    ];
    return systemRules.contains(ruleId);
  }

  Color _getOutboundColor(OutboundAction outbound) {
    if (outbound.value == 'direct') {
      return AppTheme.successGreen;
    } else if (outbound.value == 'proxy') {
      return AppTheme.primaryNeon;
    } else if (outbound.value == 'block') {
      return AppTheme.errorRed;
    } else if (outbound.isDynamic) {
      // 动态出站使用不同的颜色
      return AppTheme.accentNeon;
    } else {
      // 默认颜色
      return AppTheme.primaryNeon;
    }
  }

  Widget _buildRuleCard(RoutingRuleConfig rule) {
    final isAvailable = _availableRulesets.contains(rule.ruleset);

    return Card(
      color: AppTheme.bgCard,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  rule.type == RuleType.geoip
                      ? Icons.location_on_outlined
                      : Icons.language_outlined,
                  color: rule.type == RuleType.geoip
                      ? Colors.orange
                      : AppTheme.primaryNeon,
                  size: 18,
                ),
                const SizedBox(width: 8),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                Switch(
                  value: rule.enabled,
                  onChanged: (value) => _toggleRule(rule.id, value),
                  thumbColor: WidgetStateProperty.resolveWith<Color?>(
                    (states) => states.contains(WidgetState.selected)
                        ? AppTheme.primaryNeon
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? AppTheme.successGreen.withAlpha(30)
                        : AppTheme.errorRed.withAlpha(30),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    rule.ruleset,
                    style: TextStyle(
                      color: isAvailable
                          ? AppTheme.successGreen
                          : AppTheme.errorRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '优先级: ${rule.priority}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                if (!_isSystemRule(rule.id))
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppTheme.errorRed,
                    ),
                    onPressed: () => _deleteRule(rule.id),
                    iconSize: 20,
                  ),
              ],
            ),
            if (rule.description != null) ...[
              const SizedBox(height: 2),
              Text(
                rule.description!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (!isAvailable) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_outlined,
                      color: AppTheme.errorRed,
                      size: 14,
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
                      onPressed: _openRulesetManager,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => safePop(context),
        ),
        title: const Text(
          '分流配置',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryNeon,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primaryNeon,
          tabs: const [
            Tab(text: '规则管理'),
            Tab(text: '出站绑定'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _openRulesetManager,
            icon: const Icon(
              Icons.public,
              size: 18,
              color: AppTheme.primaryNeon,
            ),
            label: const Text(
              '规则集管理',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 规则管理 Tab
          _buildRulesTabBody(),
          // 出站绑定 Tab
          _buildBindingTabBody(),
        ],
      ),
    );
  }

  Widget _buildRulesTabBody() {
    if (_isLoading && _statusMessage.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryNeon),
        ),
      );
    }
    if (_statusMessage.isNotEmpty) {
      return Center(
        child: Text(
          _statusMessage,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        // 顶部操作条（仅在规则页显示）
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _isLoading ? null : _showAddRuleDialog,
                icon: const Icon(
                  Icons.add,
                  size: 18,
                  color: AppTheme.primaryNeon,
                ),
                label: const Text(
                  '添加规则',
                  style: TextStyle(color: AppTheme.primaryNeon),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () async {
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
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
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
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: _rules.map(_buildRuleCard).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildBindingTabBody() {
    return Column(
      children: [
        // 可滚动的主要内容区域
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 默认出站选择器 - 可收缩
              _buildCollapsibleFinalSelector(),
              const SizedBox(height: 16),

              // 自动生成按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _autoGenerateOutbounds,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('自动生成'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.primaryNeon),
                        foregroundColor: AppTheme.primaryNeon,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _addDynamicOutbound,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加出站'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.accentNeon),
                        foregroundColor: AppTheme.accentNeon,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 动态出站列表
              if (_dynamicOutbounds.isNotEmpty) ...[
                const Text(
                  '出站绑定',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                // 动态出站卡片列表
                ..._dynamicOutbounds.asMap().entries.map((entry) {
                  final index = entry.key;
                  final outbound = entry.value;
                  return _buildDynamicOutboundCard(outbound, index);
                }),
              ] else ...[
                // 空状态显示
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.link_off,
                          size: 64,
                          color: AppTheme.textSecondary.withAlpha(128),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无出站绑定',
                          style: TextStyle(
                            color: AppTheme.textSecondary.withAlpha(128),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '点击"自动生成"或"添加出站"开始配置',
                          style: TextStyle(
                            color: AppTheme.textSecondary.withAlpha(192),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),

        // 固定在底部的操作按钮
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            border: Border(
              top: BorderSide(
                color: AppTheme.borderColor.withAlpha(100),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _resetBindings,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    '重置',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveBinding,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryNeon,
                    foregroundColor: AppTheme.bgDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('保存并生效'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  /// 自动生成出站绑定
  Future<void> _autoGenerateOutbounds() async {
    setState(() => _isLoading = true);
    try {
      await _binding.autoGenerateFromConfigs();
      await _initBinding();
      _showMessage('已根据代理节点自动生成出站绑定');
    } catch (e) {
      _showMessage('自动生成失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 添加动态出站
  Future<void> _addDynamicOutbound() async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => _AddOutboundDialog(
        existingTags: _dynamicOutbounds.map((o) => o.tag).toList(),
        configs: _configs,
      ),
    );

    if (result != null) {
      try {
        final tag = result['tag']!;
        final displayName = result['displayName']!;
        final configId = result['configId'];

        await _binding.addDynamicOutbound(
          tag: tag,
          displayName: displayName,
          configId: configId,
        );
        await _initBinding();
        _showMessage('已添加出站: $displayName');
      } catch (e) {
        _showMessage('添加出站失败: $e', isError: true);
      }
    }
  }

  /// 动态出站卡片
  Widget _buildDynamicOutboundCard(DynamicOutbound outbound, int index) {
    return Card(
      color: AppTheme.bgCard,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // 出站名称
                      Text(
                        outbound.displayName,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Tag标签
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNeon.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppTheme.primaryNeon.withAlpha(100),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          outbound.tag,
                          style: const TextStyle(
                            color: AppTheme.primaryNeon,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _editDynamicOutbound(outbound);
                        break;
                      case 'delete':
                        _deleteDynamicOutbound(outbound);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('编辑'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: outbound.configId,
              isExpanded: true,
              dropdownColor: AppTheme.bgCard,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.bgDark,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: AppTheme.borderColor.withAlpha(100),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: AppTheme.borderColor.withAlpha(100),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.primaryNeon),
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    '未绑定',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                ..._configs.map(
                  (c) => DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(
                      c.name.isNotEmpty
                          ? c.name
                          : '${c.type.toUpperCase()} ${c.server}:${c.port}',
                      style: const TextStyle(color: AppTheme.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _dynamicOutbounds[index] = outbound.copyWith(configId: value);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑动态出站
  Future<void> _editDynamicOutbound(DynamicOutbound outbound) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _EditOutboundDialog(
        outbound: outbound,
        existingTags: _dynamicOutbounds.map((o) => o.tag).where((t) => t != outbound.tag).toList(),
      ),
    );

    if (result != null) {
      try {
        await _binding.updateDynamicOutbound(
          outbound.tag,
          displayName: result['displayName'],
        );
        await _initBinding();
        _showMessage('已更新出站: ${result['displayName']}');
      } catch (e) {
        _showMessage('更新出站失败: $e', isError: true);
      }
    }
  }

  /// 删除动态出站
  Future<void> _deleteDynamicOutbound(DynamicOutbound outbound) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '确认删除',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要删除出站 "${outbound.displayName}" 吗？',
          style: const TextStyle(color: AppTheme.textSecondary),
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
        await _binding.removeDynamicOutbound(outbound.tag);
        await _initBinding();
        _showMessage('已删除出站: ${outbound.displayName}');
      } catch (e) {
        _showMessage('删除出站失败: $e', isError: true);
      }
    }
  }

  /// 可收缩的默认出站选择器
  Widget _buildCollapsibleFinalSelector() {
    // 获取所有可用的出站选项
    final availableTags = _binding.getAvailableOutboundTags();
    final options = availableTags.map((tag) {
      if (tag == 'proxy') return _FinalOption(tag, '默认代理 (proxy)');
      if (tag == 'direct') return _FinalOption(tag, '直连 (direct)');
      if (tag == 'block') return _FinalOption(tag, '阻断 (block)');

      // 查找动态出站的显示名称
      final outbound = _dynamicOutbounds.firstWhere(
        (o) => o.tag == tag,
        orElse: () => DynamicOutbound(tag: tag, displayName: tag.toUpperCase()),
      );
      return _FinalOption(tag, '${outbound.displayName} ($tag)');
    }).toList();

    // 找到当前选中选项的显示名称
    final currentOption = options.firstWhere(
      (o) => o.tag == _finalTag,
      orElse: () => _FinalOption(_finalTag, _finalTag),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 可点击的标题栏
          InkWell(
            onTap: () {
              setState(() {
                _isFinalSelectorExpanded = !_isFinalSelectorExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.settings_outlined,
                    color: AppTheme.primaryNeon,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '默认出站',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNeon.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      currentOption.label,
                      style: const TextStyle(
                        color: AppTheme.primaryNeon,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isFinalSelectorExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 可收缩的内容
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: AppTheme.borderColor),
                  const SizedBox(height: 8),
                  const Text(
                    '选择默认出站策略 (route.final)',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...options.map(
                    (o) => RadioListTile<String>(
                      value: o.tag,
                      groupValue: _finalTag,
                      onChanged: (v) => setState(() => _finalTag = v ?? 'proxy'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      fillColor: WidgetStateProperty.resolveWith<Color?>(
                        (states) => states.contains(WidgetState.selected)
                            ? AppTheme.primaryNeon
                            : null,
                      ),
                      title: Text(
                        o.label,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState: _isFinalSelectorExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

}

class _FinalOption {
  final String tag;
  final String label;
  const _FinalOption(this.tag, this.label);
}

/// 添加出站对话框
class _AddOutboundDialog extends StatefulWidget {
  final List<String> existingTags;
  final List<VPNConfig> configs;

  const _AddOutboundDialog({
    required this.existingTags,
    required this.configs,
  });

  @override
  State<_AddOutboundDialog> createState() => _AddOutboundDialogState();
}

class _AddOutboundDialogState extends State<_AddOutboundDialog> {
  final _tagController = TextEditingController();
  final _displayNameController = TextEditingController();
  String? _selectedConfigId;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text(
        '添加动态出站',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppTheme.errorRed, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _displayNameController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '显示名称',
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

            TextField(
              controller: _tagController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '出站标签 (可选)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                hintText: '留空自动生成',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.borderColor),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryNeon),
                ),
              ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String?>(
              value: _selectedConfigId,
              dropdownColor: AppTheme.bgCard,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '绑定配置 (可选)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('稍后绑定'),
                ),
                ...widget.configs.map((config) {
                  return DropdownMenuItem<String?>(
                    value: config.id,
                    child: Text(
                      config.name.isNotEmpty
                          ? config.name
                          : '${config.type.toUpperCase()} ${config.server}:${config.port}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedConfigId = value;
                });
              },
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
            final displayName = _displayNameController.text.trim();
            if (displayName.isEmpty) {
              setState(() {
                _errorMessage = '请输入显示名称';
              });
              return;
            }

            var tag = _tagController.text.trim();
            if (tag.isEmpty) {
              // 自动生成标签
              tag = DynamicOutbound.generateTag(widget.existingTags.length);
            }

            // 验证标签
            if (!DynamicOutbound.isValidTag(tag)) {
              setState(() {
                _errorMessage = '标签格式无效，只能包含小写字母、数字、横线和下划线';
              });
              return;
            }

            if (widget.existingTags.contains(tag)) {
              setState(() {
                _errorMessage = '标签已存在';
              });
              return;
            }

            Navigator.of(context).pop({
              'tag': tag,
              'displayName': displayName,
              'configId': _selectedConfigId,
            });
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

/// 编辑出站对话框
class _EditOutboundDialog extends StatefulWidget {
  final DynamicOutbound outbound;
  final List<String> existingTags;

  const _EditOutboundDialog({
    required this.outbound,
    required this.existingTags,
  });

  @override
  State<_EditOutboundDialog> createState() => _EditOutboundDialogState();
}

class _EditOutboundDialogState extends State<_EditOutboundDialog> {
  late final TextEditingController _displayNameController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.outbound.displayName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text(
        '编辑出站',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppTheme.errorRed, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _displayNameController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '显示名称',
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

            // 显示不可编辑的标签
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Text(
                    '出站标签: ',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  Text(
                    widget.outbound.tag,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '(不可修改)',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
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
            final displayName = _displayNameController.text.trim();
            if (displayName.isEmpty) {
              setState(() {
                _errorMessage = '请输入显示名称';
              });
              return;
            }

            Navigator.of(context).pop({
              'displayName': displayName,
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryNeon,
            foregroundColor: Colors.white,
          ),
          child: const Text('保存'),
        ),
      ],
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
  final _priorityController = TextEditingController(text: '650');

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
        .where(
          (ruleset) => _selectedType == RuleType.geoip
              ? ruleset.startsWith('geoip-')
              : ruleset.startsWith('geosite-'),
        )
        .toList();

    if (availableForType.isNotEmpty &&
        (_selectedRuleset == null ||
            !availableForType.contains(_selectedRuleset))) {
      _selectedRuleset = availableForType.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableForType = widget.availableRulesets
        .where(
          (ruleset) => _selectedType == RuleType.geoip
              ? ruleset.startsWith('geoip-')
              : ruleset.startsWith('geosite-'),
        )
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
                return DropdownMenuItem(value: ruleset, child: Text(ruleset));
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
              items: OutboundAction.predefinedActions.map((action) {
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
            if (_nameController.text.trim().isEmpty ||
                _selectedRuleset == null) {
              return;
            }

            final priority = int.tryParse(_priorityController.text) ?? 650;
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

// 与现有弹窗风格一致的底部抽屉式添加规则表单
class _AddRuleSheet extends StatefulWidget {
  final List<String> availableRulesets;
  final List<RoutingRuleConfig> existingRules;

  const _AddRuleSheet({
    required this.availableRulesets,
    required this.existingRules,
  });

  @override
  State<_AddRuleSheet> createState() => _AddRuleSheetState();
}

class _AddRuleSheetState extends State<_AddRuleSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priorityController = TextEditingController(text: '650');

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
        .where(
          (ruleset) => _selectedType == RuleType.geoip
              ? ruleset.startsWith('geoip-')
              : ruleset.startsWith('geosite-'),
        )
        .toList();

    if (availableForType.isNotEmpty &&
        (_selectedRuleset == null ||
            !availableForType.contains(_selectedRuleset))) {
      _selectedRuleset = availableForType.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableForType = widget.availableRulesets
        .where(
          (ruleset) => _selectedType == RuleType.geoip
              ? ruleset.startsWith('geoip-')
              : ruleset.startsWith('geosite-'),
        )
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '添加分流规则',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

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
            const SizedBox(height: 12),

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
            const SizedBox(height: 12),

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
                return DropdownMenuItem(value: ruleset, child: Text(ruleset));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedRuleset = value;
                });
              },
            ),
            const SizedBox(height: 12),

            // 出站动作
            DropdownButtonFormField<OutboundAction>(
              value: _selectedOutbound,
              dropdownColor: AppTheme.bgCard,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '出站动作',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
              items: OutboundAction.predefinedActions.map((action) {
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
            const SizedBox(height: 12),

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
            const SizedBox(height: 12),

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

            const SizedBox(height: 16),

            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    if (_nameController.text.trim().isEmpty ||
                        _selectedRuleset == null) {
                      return;
                    }

                    final priority =
                        int.tryParse(_priorityController.text) ?? 650;
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
            ),
          ],
        ),
      ),
    );
  }
}
