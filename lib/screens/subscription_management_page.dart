import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider_v2.dart';
import '../models/subscription_info.dart';
import '../theme/app_theme.dart';

class SubscriptionManagementPage extends StatefulWidget {
  const SubscriptionManagementPage({super.key});

  @override
  State<SubscriptionManagementPage> createState() => _SubscriptionManagementPageState();
}

class _SubscriptionManagementPageState extends State<SubscriptionManagementPage> {
  final _addUrlController = TextEditingController();
  bool _isLoading = false;
  String? _loadingUrl;

  @override
  void dispose() {
    _addUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // 顶部标题
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
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
                  const Text(
                    '订阅管理',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // 添加订阅区域
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '添加订阅',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addUrlController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: '输入订阅链接 (https://...)',
                        hintStyle: const TextStyle(color: AppTheme.textHint),
                        prefixIcon: const Icon(Icons.link, color: AppTheme.primaryNeon),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppTheme.borderColor.withAlpha(100)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppTheme.borderColor.withAlpha(100)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.primaryNeon),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _addSubscription,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryNeon,
                          foregroundColor: AppTheme.bgDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.bgDark),
                                ),
                              )
                            : const Text('添加订阅'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 订阅列表
              Consumer<VPNProviderV2>(
                builder: (context, provider, child) {
                  final subscriptionUrls = provider.getAllSubscriptionUrls();
                  final subscriptionInfos = provider.getSubscriptionInfos();

                  if (subscriptionUrls.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.rss_feed_outlined,
                            size: 64,
                            color: AppTheme.textSecondary.withAlpha(128),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无订阅',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.textSecondary.withAlpha(128),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '添加订阅链接来获取代理配置',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textHint.withAlpha(128),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: subscriptionUrls.map((url) {
                      final info = subscriptionInfos[url] as SubscriptionInfo?;
                      final configCount = provider.getSubscriptionConfigCount(url);
                      final isUpdating = _isLoading && _loadingUrl == url;

                      return _buildSubscriptionCard(
                        url: url,
                        info: info,
                        configCount: configCount,
                        isUpdating: isUpdating,
                        provider: provider,
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard({
    required String url,
    required SubscriptionInfo? info,
    required int configCount,
    required bool isUpdating,
    required VPNProviderV2 provider,
  }) {
    // 提取网站名称
    String displayName = url;
    try {
      final uri = Uri.parse(url);
      displayName = uri.host;
    } catch (e) {
      if (url.length > 20) {
        displayName = '${url.substring(0, 17)}...';
      }
    }

    // 获取最后更新时间
    final lastUpdated = provider.getSubscriptionLastUpdated(url);
    String updateTimeText = '未更新';
    if (lastUpdated != null) {
      final diff = DateTime.now().difference(lastUpdated);
      if (diff.inMinutes < 60) {
        updateTimeText = '${diff.inMinutes}分钟前';
      } else if (diff.inHours < 24) {
        updateTimeText = '${diff.inHours}小时前';
      } else {
        updateTimeText = '${diff.inDays}天前';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryNeon.withAlpha(80)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // 左侧蓝色装饰条
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: AppTheme.primaryNeon,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            // 主要内容区域
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第一行：网站名称 + 操作按钮
                    Row(
                      children: [
                        Icon(
                          Icons.language,
                          size: 16,
                          color: AppTheme.primaryNeon,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 操作按钮
                        _buildActionButton(
                          icon: isUpdating ? null : Icons.refresh,
                          onTap: isUpdating ? null : () => _updateSubscription(url),
                          tooltip: '更新订阅',
                          isLoading: isUpdating,
                        ),
                        _buildActionButton(
                          icon: Icons.copy,
                          onTap: () => _copyUrl(url),
                          tooltip: '复制链接',
                        ),
                        _buildActionButton(
                          icon: Icons.delete,
                          onTap: () => _deleteSubscription(url),
                          tooltip: '删除订阅',
                          color: AppTheme.errorRed,
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // 第二行：订阅网址
                    Text(
                      url.length > 50 ? '${url.substring(0, 47)}...' : url,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 6),

                    // 第三行：流量信息 + 到期时间
                    Row(
                      children: [
                        Text(
                          info != null ? '${info.formattedUsed} / ${info.formattedTotal}' : '流量信息未提供',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          info?.formattedExpireDate ?? '到期时间未提供',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // 第四行：刷新时间
                    Row(
                      children: [
                        Icon(
                          Icons.update,
                          size: 12,
                          color: AppTheme.textHint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '上次更新：$updateTimeText',
                          style: const TextStyle(
                            color: AppTheme.textHint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建操作按钮
  Widget _buildActionButton({
    IconData? icon,
    VoidCallback? onTap,
    String? tooltip,
    Color? color,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: (onTap != null) ? AppTheme.bgDark.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: isLoading
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(color ?? AppTheme.primaryNeon),
                ),
              )
            : Icon(
                icon,
                size: 14,
                color: (onTap != null) ? (color ?? AppTheme.textSecondary) : AppTheme.textSecondary.withAlpha(100),
              ),
      ),
    );
  }


  Color _getStatusColor(SubscriptionInfo info) {
    if (info.isExpired || info.usagePercentage >= 95) return AppTheme.errorRed;
    if (info.usagePercentage >= 80 || (info.remainingDays != null && info.remainingDays! <= 7)) {
      return Colors.orange;
    }
    return AppTheme.successGreen;
  }

  Future<void> _addSubscription() async {
    final url = _addUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入订阅链接')),
      );
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的HTTP/HTTPS链接')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingUrl = url;
    });

    try {
      final provider = context.read<VPNProviderV2>();

      // 使用异步执行避免阻塞UI
      final success = await Future.microtask(() async {
        return await provider.importFromRemoteSubscription(url);
      }).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('请求超时，请检查网络连接或稍后重试');
        },
      );

      if (mounted) {
        if (success) {
          _addUrlController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('订阅添加成功')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('订阅添加失败，请检查链接')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingUrl = null;
        });
      }
    }
  }

  Future<void> _updateSubscription(String url) async {
    setState(() {
      _isLoading = true;
      _loadingUrl = url;
    });

    try {
      final provider = context.read<VPNProviderV2>();

      // 使用异步执行避免阻塞UI
      final success = await Future.microtask(() async {
        return await provider.updateSubscription(url);
      }).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('请求超时，请检查网络连接或稍后重试');
        },
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('订阅更新成功')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('订阅更新失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingUrl = null;
        });
      }
    }
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('链接已复制到剪贴板')),
    );
  }

  Future<void> _deleteSubscription(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '删除订阅',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          '确定要删除这个订阅吗？这将删除该订阅下的所有节点配置。',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final provider = context.read<VPNProviderV2>();
        final success = await provider.deleteSubscription(url);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('订阅删除成功')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('订阅删除失败')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }
}