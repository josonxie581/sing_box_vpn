import 'package:flutter/material.dart';
import 'package:gsou/utils/safe_navigator.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/proxy_mode.dart';
import '../theme/app_theme.dart';

/// 分流规则设置页面
class RoutingRulesPage extends StatefulWidget {
  const RoutingRulesPage({super.key});

  @override
  State<RoutingRulesPage> createState() => _RoutingRulesPageState();
}

class _RoutingRulesPageState extends State<RoutingRulesPage> {
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
      body: Consumer<VPNProvider>(
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
  Widget _buildProxyModeSection(VPNProvider provider) {
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
              Icon(Icons.rule_folder, color: AppTheme.primaryNeon, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Gsou 规则集状态',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '本地集成',
                  style: TextStyle(
                    fontSize: 10,
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
              Icon(Icons.edit_note, color: AppTheme.primaryNeon, size: 20),
              const SizedBox(width: 8),
              const Text(
                '自定义规则',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
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

          // 暂无自定义规则提示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderColor.withAlpha(50)),
            ),
            child: Column(
              children: [
                Icon(Icons.rule, color: AppTheme.textSecondary, size: 32),
                const SizedBox(height: 8),
                const Text(
                  '暂无自定义规则',
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 4),
                const Text(
                  '点击上方"添加"按钮创建自定义分流规则',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
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
  void _showAddCustomRuleDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '添加自定义规则',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          '自定义规则功能正在开发中，敬请期待！',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(context),
            child: const Text(
              '确定',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
        ],
      ),
    );
  }
}
