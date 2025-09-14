import 'package:flutter/material.dart';
import 'package:gsou/utils/safe_navigator.dart' as sn;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../theme/app_theme.dart';

/// 日志页面
class LogsPage extends StatefulWidget {
  final VPNProvider provider;

  const LogsPage({super.key, required this.provider});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    // 自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听日志变化，自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    final provider = context.watch<VPNProvider>();
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => sn.safePop(context),
        ),
        title: const Text(
          '日志',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // 自动滚动开关
          IconButton(
            icon: Icon(
              _autoScroll
                  ? Icons.vertical_align_bottom
                  : Icons.vertical_align_bottom_outlined,
              color: _autoScroll
                  ? AppTheme.primaryNeon
                  : AppTheme.textSecondary,
            ),
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
              if (_autoScroll) {
                _scrollToBottom();
              }
            },
            tooltip: _autoScroll ? '关闭自动滚动' : '开启自动滚动',
          ),
          // 清空日志
          IconButton(
            icon: const Icon(Icons.clear_all, color: AppTheme.textSecondary),
            onPressed: () => _showClearLogsDialog(),
            tooltip: '清空日志',
          ),
          // 复制所有日志
          IconButton(
            icon: const Icon(Icons.copy_all, color: AppTheme.textSecondary),
            onPressed: () => _copyAllLogs(),
            tooltip: '复制所有日志',
          ),
          // 更多操作（重置偏好）
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) async {
              if (value == 'reset_prefs') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppTheme.bgCard,
                    title: const Text(
                      '重置偏好',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                    content: const Text(
                      '这将清除所有偏好设置并恢复默认值（保留服务器配置）。确定继续？',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => sn.safePop(ctx),
                        child: const Text(
                          '取消',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await provider.resetPreferences(includeConfigs: false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('偏好已重置'),
                        backgroundColor: AppTheme.successGreen,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              } else if (value == 'reset_all') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppTheme.bgCard,
                    title: const Text(
                      '危险操作',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                    content: const Text(
                      '这将删除所有偏好和服务器配置，且不可恢复，确定继续？',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => sn.safePop(ctx),
                        child: const Text(
                          '取消',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.errorRed,
                        ),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await provider.resetPreferences(includeConfigs: true);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('全部已重置'),
                        backgroundColor: AppTheme.errorRed,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'reset_prefs', child: Text('重置偏好(保留配置)')),
              PopupMenuItem(value: 'reset_all', child: Text('重置全部(含配置)')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Icon(Icons.more_vert, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 日志统计信息
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: AppTheme.bgCard,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.primaryNeon),
                const SizedBox(width: 8),
                Text(
                  '共 ${provider.logs.length} 条日志',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                if (provider.logs.isNotEmpty) ...[
                  Text(
                    '最新: ${_formatTime(DateTime.now())}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 日志列表
          Expanded(
            child: provider.logs.isEmpty
                ? _buildEmptyState()
                : _buildLogsList(),
          ),
        ],
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.article_outlined,
            size: 80,
            color: AppTheme.textSecondary.withAlpha(100),
          ),
          const SizedBox(height: 20),
          Text(
            '暂无日志',
            style: TextStyle(
              fontSize: 18,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '连接VPN后将显示日志信息',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary.withAlpha(150),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建日志列表
  Widget _buildLogsList() {
    final provider = context.watch<VPNProvider>();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: provider.logs.length,
      itemBuilder: (context, index) {
        final log = provider.logs[index];
        return _buildLogItem(log, index);
      },
    );
  }

  /// 构建单个日志项
  Widget _buildLogItem(String log, int index) {
    final logType = _getLogType(log);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getLogColor(logType).withAlpha(100),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showLogDetail(log, index),
          onLongPress: () => _copyLog(log),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 日志类型图标
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _getLogColor(logType).withAlpha(50),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getLogIcon(logType),
                    size: 12,
                    color: _getLogColor(logType),
                  ),
                ),

                const SizedBox(width: 12),

                // 日志内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textPrimary,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '#${index + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary.withAlpha(150),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            logType.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: _getLogColor(logType),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 复制按钮
                GestureDetector(
                  onTap: () => _copyLog(log),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.textSecondary.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.copy,
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 获取日志类型
  String _getLogType(String log) {
    final lower = log.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('错误') ||
        lower.contains('失败')) {
      return 'error';
    } else if (lower.contains('warn') || lower.contains('警告')) {
      return 'warning';
    } else if (lower.contains('success') ||
        lower.contains('成功') ||
        lower.contains('连接')) {
      return 'success';
    } else {
      return 'info';
    }
  }

  /// 获取日志颜色
  Color _getLogColor(String logType) {
    switch (logType) {
      case 'error':
        return AppTheme.errorRed;
      case 'warning':
        return AppTheme.warningOrange;
      case 'success':
        return AppTheme.successGreen;
      default:
        return AppTheme.primaryNeon;
    }
  }

  /// 获取日志图标
  IconData _getLogIcon(String logType) {
    switch (logType) {
      case 'error':
        return Icons.error_outline;
      case 'warning':
        return Icons.warning_outlined;
      case 'success':
        return Icons.check_circle_outline;
      default:
        return Icons.info_outline;
    }
  }

  /// 格式化时间
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  /// 复制单条日志
  void _copyLog(String log) {
    Clipboard.setData(ClipboardData(text: log));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('日志已复制到剪贴板'),
        backgroundColor: AppTheme.successGreen,
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// 复制所有日志
  void _copyAllLogs() {
    final provider = context.read<VPNProvider>();
    if (provider.logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无日志可复制'),
          backgroundColor: AppTheme.warningOrange,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final allLogs = provider.logs.join('\n');
    Clipboard.setData(ClipboardData(text: allLogs));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${provider.logs.length} 条日志到剪贴板'),
        backgroundColor: AppTheme.successGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 显示日志详情
  void _showLogDetail(String log, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            Text(
              '日志详情 #${index + 1}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, color: AppTheme.primaryNeon),
              onPressed: () {
                _copyLog(log);
                sn.safePop(context);
              },
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: SelectableText(
              log,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => sn.safePop(context),
            child: const Text(
              '关闭',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示清空日志对话框
  void _showClearLogsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '清空日志',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Builder(
          builder: (ctx) {
            final count = ctx.watch<VPNProvider>().logs.length;
            return Text(
              '确定要清空所有日志吗？此操作不可撤销。\n当前共有 $count 条日志。',
              style: const TextStyle(color: AppTheme.textSecondary),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => sn.safePop(context),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<VPNProvider>().clearLogs();
              sn.safePop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('日志已清空'),
                  backgroundColor: AppTheme.successGreen,
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text('清空', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
  }
}
