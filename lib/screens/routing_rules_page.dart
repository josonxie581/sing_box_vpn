import 'package:flutter/material.dart';
import 'package:gsou/utils/safe_navigator.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider_v2.dart';
import '../models/proxy_mode.dart';
import '../models/custom_rule.dart';
import '../services/custom_rules_service.dart';
import '../widgets/add_custom_rule_dialog.dart';
import '../theme/app_theme.dart';

/// 分流规则设置页面
class RoutingRulesPage extends StatefulWidget {
  const RoutingRulesPage({super.key});

  @override
  State<RoutingRulesPage> createState() => _RoutingRulesPageState();
}

class _RoutingRulesPageState extends State<RoutingRulesPage> {
  List<CustomRule> _customRules = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCustomRules();
  }

  Future<void> _loadCustomRules() async {
    setState(() => _isLoading = true);
    try {
      final service = CustomRulesService.instance;
      await service.initialize();
      setState(() {
        _customRules = service.rules;
      });
    } catch (e) {
      print('[ERROR] 加载自定义规则失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
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
          '分流设置',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: AppTheme.textSecondary),
            onPressed: () => _showHelpDialog(),
          ),
        ],
      ),
      body: Consumer<VPNProviderV2>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 代理模式选择
                _buildProxyModeSection(provider),

                const SizedBox(height: 24),

                // 规则集状态
                _buildRulesetStatusSection(),

                const SizedBox(height: 24),

                // 规则详情
                _buildRuleDetailsSection(),

                const SizedBox(height: 24),

                // 自定义规则
                _buildCustomRulesSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建代理模式选择部分
  Widget _buildProxyModeSection(VPNProviderV2 provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, color: AppTheme.primaryNeon, size: 20),
              const SizedBox(width: 8),
              const Text(
                '代理模式',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 规则模式
          GestureDetector(
            onTap: () => provider.setProxyMode(ProxyMode.rule),
            child: _buildModeOption(
              ProxyMode.rule,
              provider.proxyMode == ProxyMode.rule,
              Icons.rule,
              '智能分流，根据规则自动选择直连或代理',
            ),
          ),

          const SizedBox(height: 12),

          // 全局模式
          GestureDetector(
            onTap: () => provider.setProxyMode(ProxyMode.global),
            child: _buildModeOption(
              ProxyMode.global,
              provider.proxyMode == ProxyMode.global,
              Icons.public,
              '所有流量通过代理服务器，但保留广告拦截',
            ),
          ),

          const SizedBox(height: 12),

          // 自定义规则模式
          GestureDetector(
            onTap: () => provider.setProxyMode(ProxyMode.custom),
            child: _buildModeOption(
              ProxyMode.custom,
              provider.proxyMode == ProxyMode.custom,
              Icons.tune,
              '仅使用自定义规则进行分流，不使用默认地理规则',
            ),
          ),
        ],
      ),
    );
  }

  /// 构建模式选项
  Widget _buildModeOption(
    ProxyMode mode,
    bool isSelected,
    IconData icon,
    String description,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primaryNeon.withAlpha(30)
            : AppTheme.bgDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? AppTheme.primaryNeon
              : AppTheme.borderColor.withAlpha(100),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected ? AppTheme.primaryNeon : AppTheme.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppTheme.primaryNeon
                        : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Icon(Icons.check_circle, color: AppTheme.primaryNeon, size: 20),
        ],
      ),
    );
  }

  /// 构建规则集状态部分
  Widget _buildRulesetStatusSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_folder, color: AppTheme.primaryNeon, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Gsou 规则集状态',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '本地集成',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppTheme.successGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildRulesetStatusItem('广告拦截', 'geosite-ads.srs', '6.5KB', true),
          const SizedBox(height: 8),
          _buildRulesetStatusItem('中国网站', 'geosite-cn.srs', '35KB', true),
          const SizedBox(height: 8),
          _buildRulesetStatusItem(
            '国外网站',
            'geosite-geolocation-!cn.srs',
            '213KB',
            true,
          ),
          const SizedBox(height: 8),
          _buildRulesetStatusItem('中国IP段', 'geoip-cn.srs', '81KB', true),
        ],
      ),
    );
  }

  /// 构建规则集状态条目
  Widget _buildRulesetStatusItem(
    String name,
    String filename,
    String size,
    bool isLoaded,
  ) {
    return Row(
      children: [
        Icon(
          isLoaded ? Icons.check_circle : Icons.error,
          color: isLoaded ? AppTheme.successGreen : AppTheme.errorRed,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          ),
        ),
        Text(
          size,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  /// 构建规则详情部分
  Widget _buildRuleDetailsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_alt, color: AppTheme.primaryNeon, size: 20),
              const SizedBox(width: 8),
              const Text(
                '规则详情',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildRuleDetailItem(
            '🚫 广告拦截',
            '拦截广告、追踪器和恶意网站',
            'geosite-ads',
            AppTheme.errorRed,
          ),

          const SizedBox(height: 12),

          _buildRuleDetailItem(
            '🇨🇳 中国直连',
            '中国大陆网站和服务直接连接',
            'geosite-cn, geoip-cn',
            AppTheme.successGreen,
          ),

          const SizedBox(height: 12),

          _buildRuleDetailItem(
            '🌍 国外代理',
            '非中国大陆网站通过代理访问',
            'geosite-geolocation-!cn',
            AppTheme.primaryNeon,
          ),

          const SizedBox(height: 12),

          _buildRuleDetailItem(
            '🏠 局域网直连',
            '私有IP地址段直接连接',
            'ip_is_private',
            AppTheme.warningOrange,
          ),
        ],
      ),
    );
  }

  /// 构建规则详情条目
  Widget _buildRuleDetailItem(
    String title,
    String description,
    String ruleset,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '规则集: $ruleset',
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withAlpha(180),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建自定义规则部分
  Widget _buildCustomRulesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, color: AppTheme.primaryNeon, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '自定义规则',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_customRules.isNotEmpty) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNeon.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_customRules.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.primaryNeon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (_customRules.isNotEmpty)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 18),
                  color: AppTheme.bgCard,
                  onSelected: (value) {
                    switch (value) {
                      case 'export':
                        _exportRules();
                        break;
                      case 'import':
                        _importRules();
                        break;
                      case 'clear':
                        _clearAllRules();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.file_download, size: 16, color: AppTheme.textSecondary),
                          SizedBox(width: 8),
                          Text('导出规则', style: TextStyle(color: AppTheme.textPrimary)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Row(
                        children: [
                          Icon(Icons.file_upload, size: 16, color: AppTheme.textSecondary),
                          SizedBox(width: 8),
                          Text('导入规则', style: TextStyle(color: AppTheme.textPrimary)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'clear',
                      child: Row(
                        children: [
                          Icon(Icons.clear_all, size: 16, color: AppTheme.errorRed),
                          SizedBox(width: 8),
                          Text('清空所有', style: TextStyle(color: AppTheme.errorRed)),
                        ],
                      ),
                    ),
                  ],
                ),
              TextButton.icon(
                onPressed: () => _showAddCustomRuleDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNeon,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 规则统计信息
          if (_customRules.isNotEmpty)
            _buildRulesStatsCard(),

          if (_customRules.isNotEmpty)
            const SizedBox(height: 16),

          if (_isLoading)
            _buildLoadingWidget()
          else if (_customRules.isEmpty)
            _buildEmptyStateWidget()
          else
            _buildCustomRulesList(),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: const Column(
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryNeon),
            strokeWidth: 2,
          ),
          SizedBox(height: 12),
          Text(
            '正在加载自定义规则...',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateWidget() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor.withAlpha(50)),
      ),
      child: const Column(
        children: [
          Icon(Icons.rule, color: AppTheme.textSecondary, size: 32),
          SizedBox(height: 8),
          Text(
            '暂无自定义规则',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            '点击上方"添加"按钮创建自定义分流规则',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomRulesList() {
    return Column(
      children: [
        for (int i = 0; i < _customRules.length; i++) ...[
          _buildCustomRuleItem(_customRules[i]),
          if (i < _customRules.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildCustomRuleItem(CustomRule rule) {
    final outboundType = OutboundType.fromValue(rule.outbound);
    final outboundColor = Color(int.parse(outboundType.colorValue.substring(1, 7), radix: 16) + 0xFF000000);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 规则类型图标
              Text(
                rule.type.icon,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 8),

              // 规则名称和状态
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rule.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (!rule.enabled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.textSecondary.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '禁用',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (rule.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        rule.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // 出站标识
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: outboundColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  outboundType.displayName,
                  style: TextStyle(
                    fontSize: 10,
                    color: outboundColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 操作菜单
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 16),
                color: AppTheme.bgCard,
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _editCustomRule(rule);
                      break;
                    case 'toggle':
                      _toggleCustomRule(rule);
                      break;
                    case 'delete':
                      _deleteCustomRule(rule);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 16, color: AppTheme.textSecondary),
                        SizedBox(width: 8),
                        Text('编辑', style: TextStyle(color: AppTheme.textPrimary)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          rule.enabled ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          rule.enabled ? '禁用' : '启用',
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 16, color: AppTheme.errorRed),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: AppTheme.errorRed)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 规则详情
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNeon.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  rule.type.displayName,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.primaryNeon,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rule.value,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 显示帮助对话框
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '分流规则说明',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const SingleChildScrollView(
          child: Text(
            '• 规则模式：根据预设规则智能分流，中国网站直连，国外网站代理\n\n'
            '• 全局模式：所有流量通过代理，但仍会拦截广告\n\n'
            '• 规则优先级：广告拦截 > 自定义规则 > 地理位置规则 > 默认规则\n\n'
            '• 本地集成：规则文件已内置到应用中，无需联网下载',
            style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(context),
            child: const Text(
              '了解',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示添加自定义规则对话框
  Future<void> _showAddCustomRuleDialog() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      builder: (context) => const AddCustomRuleDialog(),
    );

    if (result == true) {
      // 刷新规则列表
      await _loadCustomRules();
    }
  }

  /// 编辑自定义规则
  Future<void> _editCustomRule(CustomRule rule) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      builder: (context) => AddCustomRuleDialog(editingRule: rule),
    );

    if (result == true) {
      // 刷新规则列表
      await _loadCustomRules();
    }
  }

  /// 切换规则启用状态
  Future<void> _toggleCustomRule(CustomRule rule) async {
    try {
      final service = CustomRulesService.instance;
      await service.toggleRule(rule.id, !rule.enabled);
      await _loadCustomRules();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '规则已${!rule.enabled ? '启用' : '禁用'}',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            backgroundColor: AppTheme.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '操作失败: $e',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 删除自定义规则
  Future<void> _deleteCustomRule(CustomRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '确认删除',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要删除规则"${rule.name}"吗？\n\n此操作无法撤销。',
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '删除',
              style: TextStyle(color: AppTheme.errorRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = CustomRulesService.instance;
        await service.deleteRule(rule.id);
        await _loadCustomRules();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '规则已删除',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              backgroundColor: AppTheme.successGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '删除失败: $e',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              backgroundColor: AppTheme.errorRed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  /// 导出规则
  Future<void> _exportRules() async {
    try {
      final service = CustomRulesService.instance;
      final jsonData = service.exportRules();

      // TODO: 实现文件保存功能
      // 这里可以使用 file_picker 或其他文件保存插件
      print('[DEBUG] 导出规则数据: $jsonData');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '导出功能正在开发中',
              style: TextStyle(color: AppTheme.textPrimary),
            ),
            backgroundColor: AppTheme.warningOrange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '导出失败: $e',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 导入规则
  Future<void> _importRules() async {
    // TODO: 实现文件选择和导入功能
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '导入功能正在开发中',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          backgroundColor: AppTheme.warningOrange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 清空所有规则
  Future<void> _clearAllRules() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '确认清空',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要清空所有自定义规则吗？\n\n当前有 ${_customRules.length} 条规则，此操作无法撤销。',
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '清空',
              style: TextStyle(color: AppTheme.errorRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = CustomRulesService.instance;
        await service.clearAllRules();
        await _loadCustomRules();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '所有规则已清空',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              backgroundColor: AppTheme.successGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '清空失败: $e',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              backgroundColor: AppTheme.errorRed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  /// 构建规则统计卡片
  Widget _buildRulesStatsCard() {
    final stats = CustomRulesService.instance.getRulesStats();
    final enabledCount = stats['enabled'] ?? 0;
    final totalCount = stats['total'] ?? 0;
    final disabledCount = stats['disabled'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: AppTheme.primaryNeon, size: 16),
              const SizedBox(width: 8),
              const Text(
                '规则统计',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 统计数字
          Row(
            children: [
              _buildStatItem('总数', totalCount, AppTheme.textPrimary),
              const SizedBox(width: 16),
              _buildStatItem('启用', enabledCount, AppTheme.successGreen),
              const SizedBox(width: 16),
              _buildStatItem('禁用', disabledCount, AppTheme.textSecondary),
            ],
          ),

          const SizedBox(height: 12),

          // 按类型统计
          _buildTypeStatsRow(stats),
        ],
      ),
    );
  }

  /// 构建统计项目
  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  /// 构建类型统计行
  Widget _buildTypeStatsRow(Map<String, int> stats) {
    final typeStats = <String, int>{};

    // 收集类型统计
    for (final type in RuleType.values) {
      final count = stats[type.name] ?? 0;
      if (count > 0) {
        typeStats['${type.icon} ${type.displayName}'] = count;
      }
    }

    if (typeStats.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '类型分布',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: typeStats.entries.map((entry) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryNeon.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryNeon.withAlpha(50),
                  width: 0.5,
                ),
              ),
              child: Text(
                '${entry.key} ${entry.value}',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.primaryNeon,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
