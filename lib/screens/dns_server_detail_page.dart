import 'package:flutter/material.dart';
import '../utils/navigation.dart';
import '../theme/app_theme.dart';
import 'dart:math';

/// DNS服务器详细配置页面
class DnsServerDetailPage extends StatefulWidget {
  final String serverType;

  const DnsServerDetailPage({super.key, required this.serverType});

  @override
  State<DnsServerDetailPage> createState() => _DnsServerDetailPageState();
}

class _DnsServerDetailPageState extends State<DnsServerDetailPage> {
  List<DnsServerEntry> _servers = [];
  final Map<String, bool> _testingStatus = {};

  @override
  void initState() {
    super.initState();
    _initializeServers();
  }

  /// 初始化不同类型的DNS服务器
  void _initializeServers() {
    switch (widget.serverType) {
      case 'DNS服务器':
        _servers = [
          DnsServerEntry(
            name: 'Local',
            address: 'local',
            delay: 0,
            status: DnsServerStatus.success,
            isDefault: true,
          ),
          DnsServerEntry(
            name: 'Cloudflare',
            address: 'udp://1.1.1.1',
            delay: 15,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'Google',
            address: 'udp://8.8.8.8',
            delay: 22,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'AliDNS',
            address: 'udp://223.5.5.5',
            delay: 12,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'AliDNS备用',
            address: 'udp://223.6.6.6',
            delay: 14,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
        ];
        break;
      case '代理服务器':
        _servers = [
          DnsServerEntry(
            name: 'Local',
            address: 'local',
            delay: 0,
            status: DnsServerStatus.success,
            isDefault: true,
          ),
          DnsServerEntry(
            name: 'Cloudflare DoH',
            address: 'https://1.1.1.1/dns-query',
            delay: 45,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'Google DoH',
            address: 'https://8.8.8.8/dns-query',
            delay: 52,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'Quad9 DoH',
            address: 'https://9.9.9.9/dns-query',
            delay: 48,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'Cloudflare DoT',
            address: 'tls://1.1.1.1',
            delay: 41,
            status: DnsServerStatus.disabled,
            isDefault: false,
          ),
        ];
        break;
      case '直连流量':
        _servers = [
          DnsServerEntry(
            name: 'Local',
            address: 'local',
            delay: 0,
            status: DnsServerStatus.success,
            isDefault: true,
          ),
          DnsServerEntry(
            name: 'DHCP',
            address: 'dhcp://auto',
            delay: null,
            status: DnsServerStatus.warning,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'AliDNS',
            address: 'udp://223.5.5.5',
            delay: 9,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'AliDNS备用',
            address: 'udp://223.6.6.6',
            delay: 11,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: '腾讯DNS',
            address: 'udp://119.29.29.29',
            delay: 13,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: '百度DNS',
            address: 'udp://180.76.76.76',
            delay: 16,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
        ];
        break;
      case '代理流量':
        _servers = [
          DnsServerEntry(
            name: 'AliDNS',
            address: 'udp://223.5.5.5',
            delay: 9,
            status: DnsServerStatus.success,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'AliDNS',
            address: 'udp://223.6.6.6',
            delay: 9,
            status: DnsServerStatus.success,
            isDefault: true,
          ),
          DnsServerEntry(
            name: 'AliDNS',
            address: 'tls://223.5.5.5',
            delay: 37,
            status: DnsServerStatus.disabled,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'AliDNS',
            address: 'tls://223.6.6.6',
            delay: 32,
            status: DnsServerStatus.disabled,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'AliDNS',
            address: 'tls://dns.alidns.com',
            delay: 34,
            status: DnsServerStatus.disabled,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'AliDNS',
            address: 'https://223.5.5.5/dns-query',
            delay: 27,
            status: DnsServerStatus.disabled,
            isDefault: false,
          ),
          DnsServerEntry(
            name: 'AliDNS',
            address: 'https://223.6.6.6/dns-query',
            delay: 29,
            status: DnsServerStatus.disabled,
            isDefault: false,
          ),
        ];
        break;
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
        title: Text(
          widget.serverType,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: AppTheme.textPrimary),
            onPressed: _testAllServers,
            tooltip: '测试全部',
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppTheme.textPrimary),
            onPressed: _showMoreOptions,
            tooltip: '更多选项',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _servers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final server = _servers[index];
                return _buildServerItem(server, index);
              },
            ),
          ),

          // 底部添加按钮
          Container(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showAddServerDialog,
                icon: const Icon(Icons.add),
                label: const Text('添加DNS服务器'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryNeon,
                  foregroundColor: AppTheme.bgDark,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建DNS服务器项
  Widget _buildServerItem(DnsServerEntry server, int index) {
    final isTesting = _testingStatus[server.address] ?? false;

    return GestureDetector(
      onTap: () => _editServer(server, index),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: server.isDefault
                ? AppTheme.primaryNeon.withAlpha(100)
                : AppTheme.borderColor.withAlpha(100),
            width: server.isDefault ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 服务器信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        server.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (server.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryNeon,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '默认',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.bgDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    server.address,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // 延迟显示
            if (isTesting) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryNeon,
                ),
              ),
            ] else ...[
              if (server.delay != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getDelayColor(server.delay!).withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${server.delay} ms',
                    style: TextStyle(
                      fontSize: 12,
                      color: _getDelayColor(server.delay!),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],

            const SizedBox(width: 12),

            // 状态图标
            _buildStatusIcon(server.status),

            const SizedBox(width: 8),

            // 测试按钮
            GestureDetector(
              onTap: () => _testServer(server),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNeon.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.speed,
                  size: 16,
                  color: AppTheme.primaryNeon,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建状态图标
  Widget _buildStatusIcon(DnsServerStatus status) {
    switch (status) {
      case DnsServerStatus.success:
        return const Icon(
          Icons.check_circle,
          color: AppTheme.successGreen,
          size: 20,
        );
      case DnsServerStatus.warning:
        return const Icon(
          Icons.warning,
          color: AppTheme.warningOrange,
          size: 20,
        );
      case DnsServerStatus.error:
        return const Icon(Icons.error, color: AppTheme.errorRed, size: 20);
      case DnsServerStatus.disabled:
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.textSecondary, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        );
    }
  }

  /// 获取延迟颜色
  Color _getDelayColor(int delay) {
    if (delay <= 50) return AppTheme.successGreen;
    if (delay <= 100) return AppTheme.warningOrange;
    return AppTheme.errorRed;
  }

  /// 测试单个服务器
  void _testServer(DnsServerEntry server) async {
    setState(() {
      _testingStatus[server.address] = true;
    });

    // 模拟测试
    await Future.delayed(Duration(milliseconds: 1000 + Random().nextInt(2000)));

    if (mounted) {
      final newDelay = Random().nextInt(200) + 10;
      setState(() {
        _testingStatus[server.address] = false;
        final index = _servers.indexWhere((s) => s.address == server.address);
        if (index != -1) {
          _servers[index] = _servers[index].copyWith(delay: newDelay);
        }
      });
    }
  }

  /// 测试所有服务器
  void _testAllServers() async {
    for (final server in _servers) {
      _testServer(server);
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  /// 显示添加服务器对话框
  void _showAddServerDialog() {
    final ispController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '添加DNS服务器',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ispController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'ISP',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                hintText: '例如: Cloudflare, Google, AliDNS',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'URL',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                hintText: '8.8.8.8 或 https://1.1.1.1/dns-query',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '支持格式:\n• UDP: 8.8.8.8\n• DoT: tls://1.1.1.1\n• DoH: https://1.1.1.1/dns-query',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
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
              if (ispController.text.isNotEmpty &&
                  urlController.text.isNotEmpty) {
                _addServer(ispController.text, urlController.text);
                safePop(context);
              }
            },
            child: const Text(
              '添加',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
        ],
      ),
    );
  }

  /// 添加DNS服务器
  void _addServer(String name, String address) {
    setState(() {
      _servers.add(
        DnsServerEntry(
          name: name,
          address: address,
          delay: null,
          status: DnsServerStatus.disabled,
          isDefault: false,
        ),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加DNS服务器: $name'),
        backgroundColor: AppTheme.successGreen,
      ),
    );
  }

  /// 编辑服务器
  void _editServer(DnsServerEntry server, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              server.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              server.address,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (!server.isDefault) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _setAsDefault(index);
                        safePop(context);
                      },
                      icon: const Icon(Icons.star),
                      label: const Text('设为默认'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryNeon,
                        foregroundColor: AppTheme.bgDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _testServer(server);
                      safePop(context);
                    },
                    icon: const Icon(Icons.speed),
                    label: const Text('测试延迟'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.bgCard,
                      foregroundColor: AppTheme.textPrimary,
                      side: const BorderSide(color: AppTheme.borderColor),
                    ),
                  ),
                ),
                if (!server.isDefault) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _deleteServer(index);
                        safePop(context);
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('删除'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorRed,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// 设为默认服务器
  void _setAsDefault(int index) {
    setState(() {
      for (int i = 0; i < _servers.length; i++) {
        _servers[i] = _servers[i].copyWith(isDefault: i == index);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已设置 ${_servers[index].name} 为默认服务器'),
        backgroundColor: AppTheme.successGreen,
      ),
    );
  }

  /// 删除服务器
  void _deleteServer(int index) {
    final serverName = _servers[index].name;
    setState(() {
      _servers.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除DNS服务器: $serverName'),
        backgroundColor: AppTheme.successGreen,
      ),
    );
  }

  /// 显示更多选项
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh, color: AppTheme.primaryNeon),
              title: const Text(
                '重置到默认',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                safePop(context);
                _resetToDefault();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.import_export,
                color: AppTheme.primaryNeon,
              ),
              title: const Text(
                '导入配置',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                safePop(context);
                _showImportDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: AppTheme.primaryNeon),
              title: const Text(
                '导出配置',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                safePop(context);
                _exportConfig();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 重置到默认配置
  void _resetToDefault() {
    setState(() {
      _initializeServers();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已重置到默认配置'),
        backgroundColor: AppTheme.successGreen,
      ),
    );
  }

  /// 显示导入对话框
  void _showImportDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('导入功能开发中'),
        backgroundColor: AppTheme.warningOrange,
      ),
    );
  }

  /// 导出配置
  void _exportConfig() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('导出功能开发中'),
        backgroundColor: AppTheme.warningOrange,
      ),
    );
  }
}

/// DNS服务器状态
enum DnsServerStatus { success, warning, error, disabled }

/// DNS服务器条目
class DnsServerEntry {
  final String name;
  final String address;
  final int? delay;
  final DnsServerStatus status;
  final bool isDefault;

  const DnsServerEntry({
    required this.name,
    required this.address,
    this.delay,
    required this.status,
    required this.isDefault,
  });

  DnsServerEntry copyWith({
    String? name,
    String? address,
    int? delay,
    DnsServerStatus? status,
    bool? isDefault,
  }) {
    return DnsServerEntry(
      name: name ?? this.name,
      address: address ?? this.address,
      delay: delay ?? this.delay,
      status: status ?? this.status,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
