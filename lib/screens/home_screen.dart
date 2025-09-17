import 'package:flutter/material.dart';
import 'package:gsou/utils/safe_navigator.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/vpn_provider_v2.dart';
import 'add_config_dialog.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 左侧配置列表
          SizedBox(width: 300, child: _buildConfigList(context)),

          // 分隔线
          const VerticalDivider(width: 1),

          // 右侧内容区域
          Expanded(child: _buildMainContent(context)),
        ],
      ),
    );
  }

  /// 构建配置列表
  Widget _buildConfigList(BuildContext context) {
    return Consumer<VPNProviderV2>(
      builder: (context, provider, _) {
        return Column(
          children: [
            // 标题栏
            Container(
              height: 60,
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('服务器列表', style: Theme.of(context).textTheme.titleMedium),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: '添加配置',
                        onPressed: () => _showAddConfigDialog(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.file_upload),
                        tooltip: '导入订阅',
                        onPressed: () => _importSubscription(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 配置列表
            Expanded(
              child: ListView.builder(
                itemCount: provider.configs.length,
                itemBuilder: (context, index) {
                  final config = provider.configs[index];
                  final isConnected =
                      provider.isConnected && provider.currentConfig == config;

                  return ListTile(
                    leading: Icon(
                      isConnected ? Icons.check_circle : Icons.circle_outlined,
                      color: isConnected ? Colors.green : null,
                    ),
                    title: Text(config.name),
                    subtitle: Text(
                      '${config.type.toUpperCase()} • ${config.server}:${config.port}',
                    ),
                    selected: isConnected,
                    onTap: () => provider.toggleConnection(config),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                        const PopupMenuItem(value: 'test', child: Text('测试')),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'delete':
                            _deleteConfig(context, provider, index);
                            break;
                          case 'edit':
                            showDialog(
                              context: context,
                              builder: (context) => AddConfigDialog(
                                initialConfig: provider.configs[index],
                                editIndex: index,
                              ),
                            );
                            break;
                          case 'test':
                            // TODO: 实现测试功能
                            break;
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建主内容区域
  Widget _buildMainContent(BuildContext context) {
    return Consumer<VPNProviderV2>(
      builder: (context, provider, _) {
        return Column(
          children: [
            // 状态卡片（自适应高度，避免溢出）
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        provider.isConnected
                            ? Icons.shield
                            : Icons.shield_outlined,
                        size: 48,
                        color: provider.isConnected
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        provider.status,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (provider.currentConfig != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '当前服务器: ${provider.currentConfig!.name}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // 控制按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  if (provider.isConnected)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => provider.disconnect(),
                        icon: const Icon(Icons.stop),
                        label: const Text('断开连接'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    )
                  else if (provider.configs.isNotEmpty)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            provider.connect(provider.configs.first),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('快速连接'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _showAddConfigDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('添加服务器'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),

                  const SizedBox(width: 16),
                  // 系统代理开关
                  Expanded(
                    child: Consumer<VPNProviderV2>(
                      builder: (context, provider, _) {
                        return SwitchListTile(
                          contentPadding: const EdgeInsets.only(left: 8),
                          dense: true,
                          title: const Text('自动切换系统代理'),
                          value: provider.autoSystemProxy,
                          onChanged: (v) => provider.setAutoSystemProxy(v),
                        );
                      },
                    ),
                  ),

                  IconButton(
                    onPressed: () => provider.clearLogs(),
                    icon: const Icon(Icons.clear_all),
                    tooltip: '清空日志',
                  ),
                ],
              ),
            ),

            // 日志区域
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '运行日志',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: '复制全部',
                              icon: const Icon(Icons.copy_all),
                              onPressed: () async {
                                final text = provider.logs.join('\n');
                                await Clipboard.setData(
                                  ClipboardData(text: text),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已复制全部日志')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        itemCount: provider.logs.length,
                        itemBuilder: (context, index) {
                          final reversedIndex =
                              provider.logs.length - 1 - index;
                          return SelectableText(
                            provider.logs[reversedIndex],
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 显示添加配置对话框
  void _showAddConfigDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => const AddConfigDialog());
  }

  /// 导入订阅
  Future<void> _importSubscription(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'yaml', 'json'],
    );

    if (result != null && result.files.single.path != null) {
      // TODO: 实现文件导入
      // Removed unused provider variable after refactor
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在导入订阅...')));
    }
  }

  /// 删除配置
  void _deleteConfig(BuildContext context, VPNProviderV2 provider, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${provider.configs[index].name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => safePop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              provider.deleteConfig(index);
              safePop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
