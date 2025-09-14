import 'package:flutter/material.dart';
import 'package:gsou/utils/safe_navigator.dart';
import '../theme/app_theme.dart';
import 'dns_server_detail_page.dart';

/// DNS服务器配置页面
class DnsServersPage extends StatefulWidget {
  const DnsServersPage({super.key});

  @override
  State<DnsServersPage> createState() => _DnsServersPageState();
}

class _DnsServersPageState extends State<DnsServersPage> {
  // DNS服务器配置项
  final List<DnsServerItem> _serverItems = [
    DnsServerItem(
      title: 'DNS服务器',
      subtitle: 'local',
      icon: Icons.info_outline,
      type: DnsServerType.info,
    ),
    DnsServerItem(
      title: '代理服务器',
      subtitle: 'local',
      icon: Icons.info_outline,
      type: DnsServerType.info,
    ),
    DnsServerItem(
      title: '直连流量',
      subtitle: 'local',
      icon: Icons.info_outline,
      type: DnsServerType.info,
    ),
    DnsServerItem(
      title: '代理流量',
      subtitle: 'https://1.1.1.1/dns-query...',
      icon: Icons.info_outline,
      type: DnsServerType.config,
    ),
    DnsServerItem(
      title: '自动设置服务器',
      subtitle: '',
      icon: null,
      type: DnsServerType.setting,
    ),
    DnsServerItem(
      title: '重置服务器',
      subtitle: '',
      icon: null,
      type: DnsServerType.setting,
    ),
  ];

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
          '服务器',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _serverItems.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _serverItems[index];
          return _buildServerItem(item, index);
        },
      ),
    );
  }

  /// 构建服务器配置项
  Widget _buildServerItem(DnsServerItem item, int index) {
    return GestureDetector(
      onTap: () => _handleServerItemTap(item, index),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
        ),
        child: Row(
          children: [
            // 图标
            if (item.icon != null) ...[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNeon.withAlpha(50),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, size: 14, color: AppTheme.primaryNeon),
              ),
              const SizedBox(width: 12),
            ],

            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // 右侧箭头
            if (item.type != DnsServerType.info) ...[
              Icon(
                Icons.chevron_right,
                color: AppTheme.textSecondary,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 处理服务器配置项点击
  void _handleServerItemTap(DnsServerItem item, int index) {
    switch (item.title) {
      case 'DNS服务器':
      case '代理服务器':
      case '直连流量':
      case '代理流量':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DnsServerDetailPage(serverType: item.title),
          ),
        );
        break;
      case '自动设置服务器':
        _showAutoSetupDialog();
        break;
      case '重置服务器':
        _showResetDialog();
        break;
    }
  }

  /// 显示自动设置对话框
  void _showAutoSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '自动设置服务器',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          '系统将自动检测并配置最优的DNS服务器设置。这可能会覆盖当前的自定义配置。',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(context),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              safePop(context);
              _performAutoSetup();
            },
            child: const Text(
              '开始设置',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示重置对话框
  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '重置服务器',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          '确定要重置所有DNS服务器配置到默认值吗？此操作无法撤销。',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(context),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              safePop(context);
              _performReset();
            },
            child: const Text('重置', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
  }

  /// 执行自动设置
  void _performAutoSetup() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在自动配置DNS服务器...'),
        backgroundColor: AppTheme.primaryNeon,
      ),
    );

    // 模拟自动设置过程
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          final proxyIndex = _serverItems.indexWhere(
            (item) => item.title == '代理流量',
          );
          if (proxyIndex != -1) {
            _serverItems[proxyIndex] = _serverItems[proxyIndex].copyWith(
              subtitle: 'https://cloudflare-dns.com/dns-query',
            );
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('DNS服务器自动配置完成'),
              backgroundColor: AppTheme.successGreen,
            ),
          );
        }
      }
    });
  }

  /// 执行重置
  void _performReset() {
    setState(() {
      final proxyIndex = _serverItems.indexWhere(
        (item) => item.title == '代理流量',
      );
      if (proxyIndex != -1) {
        _serverItems[proxyIndex] = _serverItems[proxyIndex].copyWith(
          subtitle: 'https://1.1.1.1/dns-query',
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DNS服务器配置已重置为默认值'),
        backgroundColor: AppTheme.successGreen,
      ),
    );
  }
}

/// DNS服务器配置项类型
enum DnsServerType {
  info, // 信息展示
  config, // 可配置
  setting, // 设置项
}

/// DNS服务器配置项
class DnsServerItem {
  final String title;
  final String subtitle;
  final IconData? icon;
  final DnsServerType type;

  const DnsServerItem({
    required this.title,
    required this.subtitle,
    this.icon,
    required this.type,
  });

  DnsServerItem copyWith({
    String? title,
    String? subtitle,
    IconData? icon,
    DnsServerType? type,
  }) {
    return DnsServerItem(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      type: type ?? this.type,
    );
  }
}
