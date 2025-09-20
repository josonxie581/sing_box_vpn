import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gsou/utils/safe_navigator.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:zxing2/qrcode.dart';
import '../providers/vpn_provider_v2.dart';
import '../models/vpn_config.dart';
import '../theme/app_theme.dart';
import '../services/ping_service.dart';
import '../services/yaml_parser_service.dart';
import 'add_config_page.dart';
import 'subscription_management_page.dart';

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
          '选择节点',
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
                color: _isSortedByPing
                    ? AppTheme.accentNeon
                    : AppTheme.textSecondary,
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
          // 订阅管理按钮
          Tooltip(
            message: '机场订阅管理',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Future.delayed(Duration.zero, () {
                    if (context.mounted) {
                      _showSubscriptionManagementPage(context);
                    }
                  });
                },
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.rss_feed,
                    color: AppTheme.accentNeon,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          // 刷新延时按钮
          Consumer<VPNProviderV2>(
            builder: (context, provider, _) => Tooltip(
              message: provider.isPingingAll ? '正在刷新延时...' : '刷新延时',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: provider.isPingingAll
                      ? null
                      : () {
                          Future.delayed(Duration.zero, () {
                            if (context.mounted) {
                              provider.refreshAllPings();
                            }
                          });
                        },
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    child: provider.isPingingAll
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryNeon,
                            ),
                          )
                        : const Icon(
                            Icons.refresh,
                            color: AppTheme.primaryNeon,
                            size: 24,
                          ),
                  ),
                ),
              ),
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
            builder: (context, provider, _) => Tooltip(
              message: provider.configs.isEmpty ? '无配置可删除' : '删除所有配置',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: provider.configs.isEmpty
                      ? null
                      : () {
                          Future.delayed(Duration.zero, () {
                            if (context.mounted) {
                              _showDeleteAllConfirmDialog(context, provider);
                            }
                          });
                        },
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.delete_sweep,
                      color: provider.configs.isEmpty
                          ? AppTheme.errorRed.withOpacity(0.4)
                          : AppTheme.errorRed,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primaryNeon),
            onPressed: () => _showAddConfigPage(context),
            tooltip: '手动添加配置',
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
      margin: const EdgeInsets.only(bottom: 8),
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
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
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
                    final pingLevel = provider.getConfigPingLevel(config.id);
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
                        _deleteConfig(context, provider, index, config.name);
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
                      case 'qrcode':
                        _showQRCodeDialog(context, config);
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
                                  style: TextStyle(color: AppTheme.textPrimary),
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
                                  style: TextStyle(color: AppTheme.textPrimary),
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
                                style: TextStyle(color: AppTheme.textPrimary),
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
                        value: 'qrcode',
                        child: Row(
                          children: [
                            Icon(
                              Icons.qr_code,
                              color: AppTheme.accentNeon,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '生成二维码',
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

  /// 显示订阅管理页面
  void _showSubscriptionManagementPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SubscriptionManagementPage(),
      ),
    );
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
          color: provider.autoRefreshEnabled
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
              color: provider.autoRefreshEnabled
                  ? AppTheme.accentNeon.withOpacity(0.2)
                  : AppTheme.textSecondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.refresh,
              size: 20,
              color: provider.autoRefreshEnabled
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
                      '自动刷新延时',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (provider.autoRefreshEnabled)
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
                  provider.autoRefreshEnabled
                      ? '开启后将定期刷新所有节点延时'
                      : '手动刷新延时，不自动更新',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
                if (provider.autoRefreshEnabled) ...[
                  const SizedBox(height: 8),
                  _buildRefreshIntervalSelector(provider),
                  const SizedBox(height: 12),
                  // 自动选择开关
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: provider.autoSelectBestServer
                            ? AppTheme.accentNeon
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '自动选择最佳服务器',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
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
                  if (provider.autoSelectBestServer) ...[
                    const SizedBox(height: 8),
                    _buildIntervalSelector(provider),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 开关
          Switch(
            value: provider.autoRefreshEnabled,
            onChanged: (v) async {
              await provider.setAutoRefreshEnabled(v);
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

  /// 构建自动刷新间隔时间选择器
  Widget _buildRefreshIntervalSelector(VPNProviderV2 provider) {
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
            '刷新间隔:',
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
  void _showDeleteAllConfirmDialog(
    BuildContext context,
    VPNProviderV2 provider,
  ) {
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

  /// 将配置转换为订阅链接格式
  String _configToSubscriptionLink(VPNConfig config) {
    switch (config.type.toLowerCase()) {
      case 'shadowsocks':
        final method = config.settings['method'] ?? 'aes-256-gcm';
        final password = config.settings['password'] ?? '';
        final auth = '$method:$password';
        final serverInfo = '${config.server}:${config.port}';
        final encoded = base64.encode(utf8.encode('$auth@$serverInfo'));
        final name = Uri.encodeComponent(config.name);
        return 'ss://$encoded#$name';

      case 'vmess':
        final vmessConfig = {
          'v': '2',
          'ps': config.name,
          'add': config.server,
          'port': config.port.toString(),
          'id': config.settings['uuid'] ?? '',
          'aid': config.settings['alterId'] ?? 0,
          'scy': config.settings['security'] ?? 'auto',
          'net': config.settings['network'] ?? 'tcp',
          'type': 'none',
          'host': config.settings['host'] ?? '',
          'path': config.settings['path'] ?? '/',
          'tls': config.settings['tls'] ?? '',
          'sni': config.settings['sni'] ?? '',
        };
        final jsonStr = jsonEncode(vmessConfig);
        final encoded = base64.encode(utf8.encode(jsonStr));
        return 'vmess://$encoded';

      case 'vless':
        final uuid = config.settings['uuid'] ?? '';
        final host = config.server;
        final port = config.port;
        final params = <String, String>{};

        if (config.settings['network'] != null &&
            config.settings['network'] != 'tcp') {
          params['type'] = config.settings['network'];
        }

        if (config.settings['tlsEnabled'] == true) {
          if (config.settings['realityEnabled'] == true) {
            params['security'] = 'reality';
            if (config.settings['realityPublicKey'] != null) {
              params['pbk'] = config.settings['realityPublicKey'];
            }
            if (config.settings['realityShortId'] != null) {
              params['sid'] = config.settings['realityShortId'];
            }
          } else {
            params['security'] = 'tls';
          }
        }

        if (config.settings['sni'] != null) {
          params['sni'] = config.settings['sni'];
        }

        if (config.settings['flow'] != null) {
          params['flow'] = config.settings['flow'];
        }

        final queryString = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

        final name = Uri.encodeComponent(config.name);
        final baseUrl = 'vless://$uuid@$host:$port';
        return queryString.isEmpty
            ? '$baseUrl#$name'
            : '$baseUrl?$queryString#$name';

      case 'trojan':
        final password = config.settings['password'] ?? '';
        final host = config.server;
        final port = config.port;
        final params = <String, String>{};

        if (config.settings['sni'] != null) {
          params['sni'] = config.settings['sni'];
        }

        if (config.settings['skipCertVerify'] == true) {
          params['allowInsecure'] = '1';
        }

        final queryString = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

        final name = Uri.encodeComponent(config.name);
        final baseUrl = 'trojan://$password@$host:$port';
        return queryString.isEmpty
            ? '$baseUrl#$name'
            : '$baseUrl?$queryString#$name';

      case 'hysteria2':
        final password = config.settings['password'] ?? '';
        final host = config.server;
        final port = config.port;
        final params = <String, String>{};

        if (config.settings['sni'] != null) {
          params['sni'] = config.settings['sni'];
        }

        if (config.settings['skipCertVerify'] == true) {
          params['insecure'] = '1';
        }

        if (config.settings['alpn'] is List) {
          params['alpn'] = (config.settings['alpn'] as List).join(',');
        }

        final queryString = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

        final name = Uri.encodeComponent(config.name);
        final baseUrl = 'hysteria2://$password@$host:$port';
        return queryString.isEmpty
            ? '$baseUrl#$name'
            : '$baseUrl?$queryString#$name';

      case 'hysteria':
        // Hysteria v1
        final password = config.settings['password'] ?? '';
        final auth = config.settings['auth'] ?? '';
        final host = config.server;
        final port = config.port;
        final params = <String, String>{};

        // 认证信息
        if (auth.isNotEmpty) {
          params['auth'] = auth;
        } else if (password.isNotEmpty) {
          params['auth_str'] = password;
        }

        // 带宽设置
        if (config.settings['up_mbps'] != null) {
          params['up_mbps'] = config.settings['up_mbps'].toString();
        }
        if (config.settings['down_mbps'] != null) {
          params['down_mbps'] = config.settings['down_mbps'].toString();
        }
        if (config.settings['up'] != null) {
          params['up'] = config.settings['up'].toString();
        }
        if (config.settings['down'] != null) {
          params['down'] = config.settings['down'].toString();
        }

        // TLS设置
        if (config.settings['sni'] != null) {
          params['sni'] = config.settings['sni'];
        }
        if (config.settings['skipCertVerify'] == true) {
          params['insecure'] = '1';
        }
        if (config.settings['alpn'] is List) {
          params['alpn'] = (config.settings['alpn'] as List).join(',');
        }
        if (config.settings['obfs'] != null) {
          params['obfs'] = config.settings['obfs'];
        }

        final queryString = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

        final name = Uri.encodeComponent(config.name);
        final userInfo = password.isNotEmpty ? '$password@' : '';
        final baseUrl = 'hysteria://$userInfo$host:$port';
        return queryString.isEmpty
            ? '$baseUrl#$name'
            : '$baseUrl?$queryString#$name';

      case 'tuic':
        final uuid = config.settings['uuid'] ?? '';
        final password = config.settings['password'] ?? '';
        final host = config.server;
        final port = config.port;
        final params = <String, String>{};

        // 认证信息
        if (uuid.isNotEmpty) {
          params['uuid'] = uuid;
        }
        if (password.isNotEmpty) {
          params['password'] = password;
        }

        // 其他设置
        if (config.settings['udpRelayMode'] != null) {
          params['udp-relay-mode'] = config.settings['udpRelayMode'];
        }
        if (config.settings['congestion'] != null) {
          params['congestion'] = config.settings['congestion'];
        }
        if (config.settings['sni'] != null) {
          params['sni'] = config.settings['sni'];
        }
        if (config.settings['skipCertVerify'] == true) {
          params['insecure'] = '1';
        }
        if (config.settings['alpn'] is List) {
          params['alpn'] = (config.settings['alpn'] as List).join(',');
        }

        final queryString = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

        final name = Uri.encodeComponent(config.name);
        final userInfo = uuid.isNotEmpty && password.isNotEmpty
            ? '$uuid:$password@'
            : password.isNotEmpty
            ? '$password@'
            : '';
        final baseUrl = 'tuic://$userInfo$host:$port';
        return queryString.isEmpty
            ? '$baseUrl#$name'
            : '$baseUrl?$queryString#$name';

      case 'anytls':
        final password = config.settings['password'] ?? '';
        final host = config.server;
        final port = config.port;
        final params = <String, String>{};

        if (config.settings['sni'] != null) {
          params['sni'] = config.settings['sni'];
        }
        if (config.settings['skipCertVerify'] == true) {
          params['insecure'] = '1';
        }
        if (config.settings['alpn'] is List) {
          params['alpn'] = (config.settings['alpn'] as List).join(',');
        }
        if (config.settings['idle_session_check_interval'] != null) {
          params['idle_session_check_interval'] =
              config.settings['idle_session_check_interval'];
        }
        if (config.settings['idle_session_timeout'] != null) {
          params['idle_session_timeout'] =
              config.settings['idle_session_timeout'];
        }
        if (config.settings['min_idle_session'] != null) {
          params['min_idle_session'] = config.settings['min_idle_session']
              .toString();
        }

        final queryString = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

        final name = Uri.encodeComponent(config.name);
        final baseUrl = 'anytls://$password@$host:$port';
        return queryString.isEmpty
            ? '$baseUrl#$name'
            : '$baseUrl?$queryString#$name';

      case 'shadowtls':
        final password = config.settings['password'] ?? '';
        final host = config.server;
        final port = config.port;
        final params = <String, String>{};

        if (config.settings['version'] != null) {
          params['version'] = config.settings['version'].toString();
        }
        if (config.settings['sni'] != null) {
          params['sni'] = config.settings['sni'];
        }
        if (config.settings['skipCertVerify'] == true) {
          params['insecure'] = '1';
        }
        if (config.settings['alpn'] is List) {
          params['alpn'] = (config.settings['alpn'] as List).join(',');
        }

        final queryString = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

        final name = Uri.encodeComponent(config.name);
        final baseUrl = 'shadowtls://$password@$host:$port';
        return queryString.isEmpty
            ? '$baseUrl#$name'
            : '$baseUrl?$queryString#$name';

      case 'socks':
        final username = config.settings['username'] ?? '';
        final password = config.settings['password'] ?? '';
        final host = config.server;
        final port = config.port;
        final params = <String, String>{};

        if (config.settings['tlsEnabled'] == true) {
          params['tls'] = '1';
          if (config.settings['sni'] != null) {
            params['sni'] = config.settings['sni'];
          }
        }

        final queryString = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

        final name = Uri.encodeComponent(config.name);
        final userInfo = username.isNotEmpty && password.isNotEmpty
            ? '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}@'
            : '';
        final baseUrl = 'socks://$userInfo$host:$port';
        return queryString.isEmpty
            ? '$baseUrl#$name'
            : '$baseUrl?$queryString#$name';

      case 'http':
        final username = config.settings['username'] ?? '';
        final password = config.settings['password'] ?? '';
        final host = config.server;
        final port = config.port;
        final params = <String, String>{};

        if (config.settings['tlsEnabled'] == true) {
          params['tls'] = '1';
          if (config.settings['sni'] != null) {
            params['sni'] = config.settings['sni'];
          }
        }

        final queryString = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

        final name = Uri.encodeComponent(config.name);
        final userInfo = username.isNotEmpty && password.isNotEmpty
            ? '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}@'
            : '';
        final baseUrl = 'http://$userInfo$host:$port';
        return queryString.isEmpty
            ? '$baseUrl#$name'
            : '$baseUrl?$queryString#$name';

      case 'wireguard':
        // WireGuard 协议没有标准的订阅链接格式，返回JSON
        final jsonStr = jsonEncode(config.toJson());
        return 'wg://' + base64.encode(utf8.encode(jsonStr));

      default:
        // 对于不支持的协议，返回JSON格式
        final jsonStr = jsonEncode(config.toJson());
        return jsonStr;
    }
  }

  /// 显示二维码对话框
  void _showQRCodeDialog(BuildContext context, VPNConfig config) {
    final subscriptionLink = _configToSubscriptionLink(config);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            Icon(Icons.qr_code, color: AppTheme.accentNeon, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '节点二维码: ${config.name}',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 二维码显示
              Container(
                width: 280,
                height: 280,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FutureBuilder<Uint8List?>(
                  future: _generateQRCode(subscriptionLink),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryNeon,
                        ),
                      );
                    }

                    if (snapshot.hasError || snapshot.data == null) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: AppTheme.errorRed,
                              size: 48,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '生成二维码失败',
                              style: TextStyle(
                                color: AppTheme.errorRed,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Image.memory(snapshot.data!, fit: BoxFit.contain);
                  },
                ),
              ),
              const SizedBox(height: 16),
              // 配置信息
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.borderColor.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '配置信息',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('类型', _getConfigTypeDisplay(config)),
                    _buildInfoRow('服务器', '${config.server}:${config.port}'),
                    if (config.remarks.isNotEmpty)
                      _buildInfoRow('备注', config.remarks),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 提示信息
              Text(
                '使用支持该协议的客户端扫描二维码即可导入配置',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: subscriptionLink));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('订阅链接已复制到剪贴板'),
                    backgroundColor: AppTheme.successGreen,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            child: const Text(
              '复制链接',
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

  /// 生成二维码图像
  Future<Uint8List?> _generateQRCode(String data) async {
    try {
      final qrCode = Encoder.encode(data, ErrorCorrectionLevel.l);
      final matrix = qrCode.matrix;

      if (matrix == null) return null;

      // 计算缩放比例
      final size = 280;
      final scale = size ~/ matrix.width;
      final outputSize = matrix.width * scale;

      // 转换为图像数据
      final bytes = Uint8List(outputSize * outputSize * 4);

      for (int y = 0; y < outputSize; y++) {
        for (int x = 0; x < outputSize; x++) {
          final offset = (y * outputSize + x) * 4;
          // 计算原始矩阵中的位置
          final sourceX = x ~/ scale;
          final sourceY = y ~/ scale;

          // 获取颜色（黑色或白色）
          final isBlack =
              sourceX < matrix.width &&
              sourceY < matrix.height &&
              matrix.get(sourceX, sourceY) == 1;
          final color = isBlack ? 0xFF000000 : 0xFFFFFFFF;

          bytes[offset] = (color >> 16) & 0xFF; // R
          bytes[offset + 1] = (color >> 8) & 0xFF; // G
          bytes[offset + 2] = color & 0xFF; // B
          bytes[offset + 3] = (color >> 24) & 0xFF; // A
        }
      }

      // 创建PNG图像
      final image = await _createPngImage(bytes, outputSize, outputSize);
      return image;
    } catch (e) {
      print('生成二维码失败: $e');
      return null;
    }
  }

  /// 创建PNG图像
  Future<Uint8List> _createPngImage(
    Uint8List pixels,
    int width,
    int height,
  ) async {
    // 简单的PNG编码实现
    final png = BytesBuilder();

    // PNG签名
    png.add([137, 80, 78, 71, 13, 10, 26, 10]);

    // IHDR块
    final ihdr = BytesBuilder();
    ihdr.add(_intToBytes(width, 4));
    ihdr.add(_intToBytes(height, 4));
    ihdr.addByte(8); // 位深度
    ihdr.addByte(6); // 颜色类型 (RGBA)
    ihdr.addByte(0); // 压缩方法
    ihdr.addByte(0); // 滤波方法
    ihdr.addByte(0); // 隔行扫描方法
    _writePngChunk(png, 'IHDR', ihdr.toBytes());

    // IDAT块 (简化处理，不压缩)
    final idat = BytesBuilder();
    for (int y = 0; y < height; y++) {
      idat.addByte(0); // 滤波类型
      for (int x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        idat.add(pixels.sublist(offset, offset + 4));
      }
    }

    // 使用zlib压缩（简化版本）
    final compressed = _zlibCompress(idat.toBytes());
    _writePngChunk(png, 'IDAT', compressed);

    // IEND块
    _writePngChunk(png, 'IEND', Uint8List(0));

    return png.toBytes();
  }

  void _writePngChunk(BytesBuilder png, String type, Uint8List data) {
    png.add(_intToBytes(data.length, 4));
    png.add(utf8.encode(type));
    png.add(data);

    // CRC32
    final crcData = BytesBuilder();
    crcData.add(utf8.encode(type));
    crcData.add(data);
    png.add(_intToBytes(_crc32(crcData.toBytes()), 4));
  }

  Uint8List _intToBytes(int value, int length) {
    final bytes = Uint8List(length);
    for (int i = length - 1; i >= 0; i--) {
      bytes[i] = value & 0xFF;
      value >>= 8;
    }
    return bytes;
  }

  int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  Uint8List _zlibCompress(Uint8List data) {
    // 简化的zlib压缩（存储模式，不实际压缩）
    final result = BytesBuilder();
    result.add([0x78, 0x01]); // zlib头

    // 存储块
    int offset = 0;
    while (offset < data.length) {
      final remaining = data.length - offset;
      final blockSize = remaining > 65535 ? 65535 : remaining;
      final isLast = offset + blockSize >= data.length;

      result.addByte(isLast ? 1 : 0);
      result.add(_intToBytes(blockSize, 2).reversed.toList());
      result.add(_intToBytes(~blockSize & 0xFFFF, 2).reversed.toList());
      result.add(data.sublist(offset, offset + blockSize));

      offset += blockSize;
    }

    // Adler32校验和
    int a = 1, b = 0;
    for (final byte in data) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    result.add(_intToBytes((b << 16) | a, 4));

    return result.toBytes();
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
