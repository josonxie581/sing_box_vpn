import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gsou/utils/safe_navigator.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/vpn_provider_v2.dart';
import '../models/vpn_config.dart';
import '../theme/app_theme.dart';
import '../services/ping_service.dart';
import '../services/yaml_parser_service.dart';
import 'add_config_page.dart';

/// 配置管理页面
class ConfigManagementPage extends StatefulWidget {
  const ConfigManagementPage({super.key});

  @override
  State<ConfigManagementPage> createState() => _ConfigManagementPageState();
}

class _ConfigManagementPageState extends State<ConfigManagementPage> {
  // 排序状态
  bool _isSortedByPing = false;
  bool _isAscending = true;

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
          '我的配置',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // 排序按钮
          Consumer<VPNProviderV2>(
            builder: (context, provider, _) => IconButton(
              icon: Icon(
                _isSortedByPing
                    ? (_isAscending ? Icons.trending_up : Icons.trending_down)
                    : Icons.sort,
                color: _isSortedByPing ? AppTheme.accentNeon : AppTheme.textSecondary,
              ),
              onPressed: provider.configs.isEmpty
                  ? null
                  : () {
                      setState(() {
                        if (!_isSortedByPing) {
                          _isSortedByPing = true;
                          _isAscending = true;
                        } else if (_isAscending) {
                          _isAscending = false;
                        } else {
                          _isSortedByPing = false;
                        }
                      });
                    },
              tooltip: _isSortedByPing
                  ? (_isAscending ? '延时升序' : '延时降序')
                  : '按延时排序',
            ),
          ),
          // 刷新延时按钮
          Consumer<VPNProviderV2>(
            builder: (context, provider, _) => IconButton(
              icon: provider.isPingingAll
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryNeon,
                      ),
                    )
                  : const Icon(Icons.refresh, color: AppTheme.primaryNeon),
              onPressed: provider.isPingingAll
                  ? null
                  : () => provider.refreshAllPings(),
              tooltip: '刷新延时',
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.file_upload_outlined,
              color: AppTheme.accentNeon,
            ),
            onPressed: () => _importFromYaml(context),
            tooltip: '导入YAML配置',
          ),
          // 删除所有配置按钮
          Consumer<VPNProviderV2>(
            builder: (context, provider, _) => IconButton(
              icon: const Icon(Icons.delete_sweep, color: AppTheme.errorRed),
              onPressed: provider.configs.isEmpty
                  ? null
                  : () => _showDeleteAllConfirmDialog(context, provider),
              tooltip: '删除所有配置',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primaryNeon),
            onPressed: () => _showAddConfigPage(context),
          ),
        ],
      ),
      body: Consumer<VPNProviderV2>(
        builder: (context, provider, _) {
          if (provider.configs.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              // 自动选择设置
              _buildAutoSelectSettings(provider),
              // 配置列表
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: provider.configs.length,
                  itemBuilder: (context, index) {
                    // 获取排序后的配置列表
                    final sortedConfigs = _getSortedConfigs(provider);
                    final config = sortedConfigs[index];
                    // 找到原始索引
                    final originalIndex = provider.configs.indexOf(config);
                    final isConnected =
                        provider.currentConfig == config &&
                        provider.isConnected;
                    final isCurrent = provider.currentConfig == config;

                    return _buildConfigCard(
                      context,
                      config,
                      originalIndex, // 使用原始索引进行编辑和删除
                      isConnected,
                      isCurrent,
                      provider,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 获取排序后的配置列表
  List<VPNConfig> _getSortedConfigs(VPNProviderV2 provider) {
    if (!_isSortedByPing) {
      return provider.configs;
    }

    // 复制列表以避免修改原始列表
    final sortedList = List<VPNConfig>.from(provider.configs);

    // 按延时排序
    sortedList.sort((a, b) {
      final pingA = provider.getConfigPing(a.id);
      final pingB = provider.getConfigPing(b.id);

      // 超时的配置放在最后
      if (pingA == -1 && pingB == -1) return 0;
      if (pingA == -1) return 1;
      if (pingB == -1) return -1;

      // 根据升序或降序排序
      if (_isAscending) {
        return pingA.compareTo(pingB);
      } else {
        return pingB.compareTo(pingA);
      }
    });

    return sortedList;
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.storage_outlined,
            size: 80,
            color: AppTheme.textSecondary.withAlpha(100),
          ),
          const SizedBox(height: 20),
          Text(
            '暂无配置',
            style: TextStyle(
              fontSize: 18,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角添加配置',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary.withAlpha(150),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () => _showAddConfigPage(context),
            icon: const Icon(Icons.add),
            label: const Text('添加配置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryNeon,
              foregroundColor: AppTheme.bgDark,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建配置卡片
  Widget _buildConfigCard(
    BuildContext context,
    VPNConfig config,
    int index,
    bool isConnected,
    bool isCurrent,
    VPNProviderV2 provider,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent
              ? AppTheme.primaryNeon.withAlpha(100)
              : AppTheme.borderColor.withAlpha(100),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectOrSwitch(provider, config),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 状态指示器
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isConnected
                            ? AppTheme.successGreen
                            : isCurrent
                            ? AppTheme.warningOrange
                            : AppTheme.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 配置名称
                    Expanded(
                      child: Text(
                        config.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),

                    // 延时显示
                    _buildPingIndicator(provider, config),
                    const SizedBox(width: 8),

                    // 状态文本
                    Builder(
                      builder: (context) {
                        final pingLevel = provider.getConfigPingLevel(
                          config.id,
                        );
                        final isTimeout = pingLevel == PingLevel.timeout;

                        String statusText;
                        Color statusColor;

                        if (isConnected) {
                          statusText = '已连接';
                          statusColor = AppTheme.successGreen;
                        } else if (isCurrent) {
                          statusText = '当前';
                          statusColor = AppTheme.warningOrange;
                        } else if (isTimeout) {
                          statusText = '超时';
                          statusColor = AppTheme.errorRed;
                        } else {
                          statusText = '';
                          statusColor = AppTheme.textSecondary;
                        }

                        return Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),

                    // 更多选项按钮
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      color: AppTheme.bgCard,
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _editConfig(context, config, index);
                            break;
                          case 'delete':
                            _deleteConfig(
                              context,
                              provider,
                              index,
                              config.name,
                            );
                            break;
                          case 'connect':
                            _connectConfig(provider, config);
                            break;
                          case 'switch':
                            provider.toggleConnection(config);
                            break;
                          case 'disconnect':
                            provider.disconnect();
                            break;
                          case 'ping':
                            provider.refreshConfigPing(config);
                            break;
                          case 'copy':
                            _copyConfigToClipboard(context, config);
                            break;
                        }
                      },
                      itemBuilder: (context) {
                        final items = <PopupMenuEntry<String>>[];
                        // 连接状态下：当前卡片若已连接 -> 提供断开；未连接 -> 提供切换
                        if (provider.isConnected) {
                          if (isConnected) {
                            items.add(
                              const PopupMenuItem(
                                value: 'disconnect',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.stop,
                                      color: AppTheme.errorRed,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '断开连接',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          } else {
                            items.add(
                              const PopupMenuItem(
                                value: 'switch',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.swap_horiz,
                                      color: AppTheme.primaryNeon,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '切换到此配置',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        } else {
                          // 未连接：提供连接
                          items.add(
                            const PopupMenuItem(
                              value: 'connect',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.play_arrow,
                                    color: AppTheme.successGreen,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '连接',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // 通用项：延时测试、拷贝、编辑、删除
                        items.addAll([
                          const PopupMenuItem(
                            value: 'ping',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.speed,
                                  color: AppTheme.primaryNeon,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '测试延时',
                                  style: TextStyle(color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'copy',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.copy,
                                  color: AppTheme.accentNeon,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '拷贝JSON',
                                  style: TextStyle(color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit,
                                  color: AppTheme.primaryNeon,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '编辑',
                                  style: TextStyle(color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete,
                                  color: AppTheme.errorRed,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '删除',
                                  style: TextStyle(color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ]);

                        return items;
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 配置详情
                Row(
                  children: [
                    _buildDetailChip('类型', _getConfigTypeDisplay(config)),
                    const SizedBox(width: 12),
                    _buildDetailChip('地址', '${config.server}:${config.port}'),
                    const SizedBox(width: 12),
                    _buildPingDetailChip(provider, config),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: config.id));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('ID 已复制: ${config.id}'),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: _buildIdChip(config.id),
                    ),
                  ],
                ),

                if (config.remarks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    config.remarks,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建详情标签
  Widget _buildDetailChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 获取配置类型显示文本
  String _getConfigTypeDisplay(VPNConfig config) {
    switch (config.type) {
      case 'ss':
        return 'Shadowsocks';
      case 'vmess':
        return 'VMess';
      case 'trojan':
        return 'Trojan';
      default:
        return config.type.toUpperCase();
    }
  }

  /// 选择配置
  Future<void> _selectConfig(VPNProviderV2 provider, VPNConfig config) async {
    if (provider.currentConfig != config) {
      // 设置为当前配置（但不连接）
      await provider.setCurrentConfig(config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已选择配置 "${config.name}"'),
            backgroundColor: AppTheme.primaryNeon,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  /// 点击卡片时：未连接 -> 仅选择；已连接 -> 若是其他节点则弹出切换确认
  Future<void> _selectOrSwitch(VPNProviderV2 provider, VPNConfig config) async {
    if (!provider.isConnected) {
      await _selectConfig(provider, config);
      return;
    }

    // 已连接：点击其他节点 -> 直接切换；点击当前节点 -> 不做处理
    final isSame = provider.currentConfig?.id == config.id;
    if (!isSame) {
      await provider.toggleConnection(config);
    }
  }

  /// 显示切换配置对话框
  // 已移除切换确认弹窗，点击即切换

  /// 连接配置
  void _connectConfig(VPNProviderV2 provider, VPNConfig config) {
    provider.connect(config);
  }

  /// 编辑配置
  void _editConfig(BuildContext context, VPNConfig config, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddConfigPage(config: config, configIndex: index),
      ),
    );
  }

  /// 删除配置
  void _deleteConfig(
    BuildContext context,
    VPNProviderV2 provider,
    int index,
    String name,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '删除配置',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要删除配置 "$name" 吗？此操作不可撤销。',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteConfig(index);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已删除配置 "$name"'),
                  backgroundColor: AppTheme.successGreen,
                ),
              );
            },
            child: const Text('删除', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
  }

  /// 显示添加配置页面
  void _showAddConfigPage(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const AddConfigPage()));
  }

  /// 从 YAML 文件导入配置
  Future<void> _importFromYaml(BuildContext context) async {
    try {
      // 选择文件
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['yaml', 'yml'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;

        // 显示导入进度
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            backgroundColor: AppTheme.bgCard,
            content: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryNeon),
                  SizedBox(width: 16),
                  Text(
                    '正在导入配置...',
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        );

        // 解析 YAML 文件
        final configs = await YamlParserService.parseYamlFile(filePath);

        if (!mounted) return;
        Navigator.of(context).pop(); // 关闭进度对话框

        if (configs.isNotEmpty) {
          // 添加配置到提供者
          final provider = Provider.of<VPNProviderV2>(context, listen: false);
          int successCount = 0;

          for (final config in configs) {
            try {
              await provider.addConfig(config);
              successCount++;
            } catch (e) {
              print('添加配置失败: ${config.name} - $e');
            }
          }

          // 显示导入结果
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: AppTheme.bgCard,
              title: const Text(
                '导入完成',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              content: Text(
                '成功导入 $successCount / ${configs.length} 个配置',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '确定',
                    style: TextStyle(color: AppTheme.primaryNeon),
                  ),
                ),
              ],
            ),
          );
        } else {
          // 没有找到有效配置
          if (!mounted) return;
          _showErrorDialog(context, '导入失败', '未在文件中找到有效的代理配置');
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 确保关闭可能的进度对话框
      _showErrorDialog(context, '导入失败', '文件解析错误: $e');
    }
  }

  /// 显示错误对话框
  void _showErrorDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title, style: const TextStyle(color: AppTheme.errorRed)),
        content: Text(
          message,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '确定',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建延时指示器
  Widget _buildPingIndicator(VPNProviderV2 provider, VPNConfig config) {
    final pingLevel = provider.getConfigPingLevel(config.id);
    final pingText = provider.getConfigPingText(config.id);

    Color pingColor;
    IconData pingIcon;

    switch (pingLevel) {
      case PingLevel.excellent:
        pingColor = AppTheme.successGreen;
        pingIcon = Icons.speed;
        break;
      case PingLevel.good:
        pingColor = const Color(0xFF7DD3FC); // 浅蓝
        pingIcon = Icons.speed;
        break;
      case PingLevel.fair:
        pingColor = AppTheme.warningOrange;
        pingIcon = Icons.access_time;
        break;
      case PingLevel.poor:
        pingColor = AppTheme.errorRed;
        pingIcon = Icons.access_time;
        break;
      case PingLevel.timeout:
        pingColor = AppTheme.textSecondary;
        pingIcon = Icons.close;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(pingIcon, size: 12, color: pingColor),
        // 超时时只显示图标，不显示文本，避免重复显示
        if (pingLevel != PingLevel.timeout) ...[
          const SizedBox(width: 4),
          Text(
            pingText,
            style: TextStyle(
              fontSize: 11,
              color: pingColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  /// 构建 ID 标签（淡色，可复制）
  Widget _buildIdChip(String id) {
    // 仅显示截断前 8 位，完整通过复制获得
    final short = id.length > 8 ? id.substring(0, 8) : id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.bgDark.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.fingerprint,
            size: 10,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 3),
          Text(
            short,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建延时详情标签
  Widget _buildPingDetailChip(VPNProviderV2 provider, VPNConfig config) {
    final ping = provider.getConfigPing(config.id);
    final pingLevel = provider.getConfigPingLevel(config.id);
    final pingDescription = PingService.getPingDescription(ping);

    Color backgroundColor;
    switch (pingLevel) {
      case PingLevel.excellent:
        backgroundColor = AppTheme.successGreen.withOpacity(0.2);
        break;
      case PingLevel.good:
        backgroundColor = const Color(0xFF7DD3FC).withOpacity(0.2);
        break;
      case PingLevel.fair:
        backgroundColor = AppTheme.warningOrange.withOpacity(0.2);
        break;
      case PingLevel.poor:
        backgroundColor = AppTheme.errorRed.withOpacity(0.2);
        break;
      case PingLevel.timeout:
        backgroundColor = AppTheme.textSecondary.withOpacity(0.2);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '延时: ',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          Text(
            pingDescription,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建自动选择设置
  Widget _buildAutoSelectSettings(VPNProviderV2 provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: provider.autoSelectBestServer
              ? AppTheme.accentNeon.withOpacity(0.3)
              : AppTheme.borderColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 左侧图标和文字
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: provider.autoSelectBestServer
                  ? AppTheme.accentNeon.withOpacity(0.2)
                  : AppTheme.textSecondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 20,
              color: provider.autoSelectBestServer
                  ? AppTheme.accentNeon
                  : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '自动选择最佳服务器',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (provider.autoSelectBestServer)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentNeon.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'AUTO',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.accentNeon,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  provider.autoSelectBestServer
                      ? '开启后将在每次延时检测完成时自动选择延时最佳的服务器'
                      : '手动选择服务器，不自动切换',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
                if (provider.autoSelectBestServer) ...[
                  const SizedBox(height: 8),
                  _buildIntervalSelector(provider),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 开关
          Switch(
            value: provider.autoSelectBestServer,
            onChanged: (v) async {
              await provider.setAutoSelectBestServer(v);
            },
            thumbColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => states.contains(WidgetState.selected)
                  ? AppTheme.accentNeon
                  : null,
            ),
            trackColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => states.contains(WidgetState.selected)
                  ? AppTheme.accentNeon.withOpacity(0.3)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建间隔时间选择器
  Widget _buildIntervalSelector(VPNProviderV2 provider) {
    final intervals = [1, 2, 3, 5, 10, 15, 20, 30, 60]; // 可选的分钟数

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgDark.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.accentNeon.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 16, color: AppTheme.accentNeon),
          const SizedBox(width: 8),
          Text(
            '检测间隔:',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppTheme.accentNeon.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: provider.pingIntervalMinutes,
                  isDense: true,
                  dropdownColor: AppTheme.bgCard,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: AppTheme.accentNeon,
                    size: 18,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  items: intervals.map<DropdownMenuItem<int>>((int minutes) {
                    return DropdownMenuItem<int>(
                      value: minutes,
                      child: Text(
                        '${minutes}分钟',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (int? newValue) {
                    if (newValue != null) {
                      provider.setPingIntervalMinutes(newValue);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示删除所有配置的确认对话框
  void _showDeleteAllConfirmDialog(BuildContext context, VPNProviderV2 provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.errorRed,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text('删除所有配置', style: TextStyle(color: AppTheme.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '确定要删除所有配置吗？',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.errorRed.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppTheme.errorRed,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '注意事项：',
                        style: TextStyle(
                          color: AppTheme.errorRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• 将删除所有 ${provider.configs.length} 个配置\n• 如果当前已连接，将自动断开连接\n• 此操作不可撤销',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              // 显示删除进度
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  backgroundColor: AppTheme.bgCard,
                  content: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.errorRed),
                        const SizedBox(width: 16),
                        const Text(
                          '正在删除配置...',
                          style: TextStyle(color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              );

              try {
                await provider.deleteAllConfigs();

                if (context.mounted) {
                  Navigator.of(context).pop(); // 关闭进度对话框

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('已删除所有配置'),
                      backgroundColor: AppTheme.successGreen,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop(); // 关闭进度对话框
                  _showErrorDialog(context, '删除失败', '删除配置时出错: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  /// 拷贝配置到剪贴板（JSON格式）
  Future<void> _copyConfigToClipboard(
    BuildContext context,
    VPNConfig config,
  ) async {
    try {
      // 将配置转换为JSON格式
      final jsonMap = config.toJson();

      // 将JSON格式化为可读的字符串
      final encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(jsonMap);

      // 复制到剪贴板
      await Clipboard.setData(ClipboardData(text: jsonString));

      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('配置 "${config.name}" 已复制到剪贴板'),
            backgroundColor: AppTheme.successGreen,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: '查看',
              textColor: Colors.white,
              onPressed: () {
                // 显示JSON内容预览
                _showJsonPreview(context, config.name, jsonString);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorDialog(context, '复制失败', '复制配置到剪贴板时出错: $e');
      }
    }
  }

  /// 显示JSON预览对话框
  void _showJsonPreview(
    BuildContext context,
    String configName,
    String jsonString,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            Icon(Icons.code, color: AppTheme.accentNeon, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '配置JSON: $configName',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.borderColor.withOpacity(0.3),
                ),
              ),
              child: SelectableText(
                jsonString,
                style: TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // 再次复制到剪贴板
              await Clipboard.setData(ClipboardData(text: jsonString));
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('JSON已复制到剪贴板'),
                    backgroundColor: AppTheme.successGreen,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            child: const Text(
              '复制',
              style: TextStyle(color: AppTheme.accentNeon),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '关闭',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
