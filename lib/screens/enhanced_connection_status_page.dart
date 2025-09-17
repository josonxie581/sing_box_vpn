import 'package:flutter/material.dart';
import '../utils/navigation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/vpn_provider_v2.dart';
import '../services/improved_traffic_stats_service.dart';

class EnhancedConnectionStatusPage extends StatefulWidget {
  const EnhancedConnectionStatusPage({super.key});

  @override
  State<EnhancedConnectionStatusPage> createState() => _EnhancedConnectionStatusPageState();
}

class _EnhancedConnectionStatusPageState extends State<EnhancedConnectionStatusPage> {
  bool isPaused = false;
  String sortBy = 'time'; // time, upload, download, total
  String filterProtocol = 'all'; // all, tcp, udp
  final Set<String> _expandedItems = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  void _sortConnections(List<Map<String, dynamic>> connections) {
    switch (sortBy) {
      case 'upload':
        connections.sort(
          (a, b) => (b['uploadBytes'] as int).compareTo(a['uploadBytes'] as int),
        );
        break;
      case 'download':
        connections.sort(
          (a, b) => (b['downloadBytes'] as int).compareTo(a['downloadBytes'] as int),
        );
        break;
      case 'total':
        connections.sort(
          (a, b) => (b['totalBytes'] as int).compareTo(a['totalBytes'] as int),
        );
        break;
      default:
        connections.sort(
          (a, b) => (b['duration'] as Duration).inSeconds.compareTo(
            (a['duration'] as Duration).inSeconds,
          ),
        );
    }
  }

  List<Map<String, dynamic>> _filterConnections(List<Map<String, dynamic>> connections) {
    var filtered = connections.toList();

    // 协议过滤
    if (filterProtocol != 'all') {
      filtered = filtered.where((conn) =>
        conn['protocol'].toString().toLowerCase() == filterProtocol.toLowerCase()
      ).toList();
    }

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((conn) {
        return conn['host'].toString().toLowerCase().contains(query) ||
               conn['process'].toString().toLowerCase().contains(query) ||
               conn['rule'].toString().toLowerCase().contains(query) ||
               conn['target'].toString().toLowerCase().contains(query);
      }).toList();
    }

    return filtered;
  }

  void _copyConnectionInfo(List<Map<String, dynamic>> connections) {
    String info = '连接状态详细信息\n';
    info += '时间: ${DateTime.now().toString()}\n';
    info += '总连接数: ${connections.length}\n\n';

    for (int i = 0; i < connections.length; i++) {
      final conn = connections[i];
      info += '═══ 连接 ${i + 1} ═══\n';
      info += '目标地址: ${conn['hostAddr']}:${conn['hostPort']}\n';
      info += '本地地址: ${conn['localAddr']}:${conn['localPortOnly']}\n';
      info += '进程: ${conn['process']} (PID: ${conn['pid']})\n';
      info += '协议: ${conn['protocol']} ${conn['state']}\n';
      info += '上传: ${ImprovedTrafficStatsService.formatBytes(conn['uploadBytes'])}';
      if (conn['uploadSpeed'] > 0) {
        info += ' (${ImprovedTrafficStatsService.formatSpeed(conn['uploadSpeed'])})';
      }
      info += '\n';
      info += '下载: ${ImprovedTrafficStatsService.formatBytes(conn['downloadBytes'])}';
      if (conn['downloadSpeed'] > 0) {
        info += ' (${ImprovedTrafficStatsService.formatSpeed(conn['downloadSpeed'])})';
      }
      info += '\n';
      info += '规则: ${conn['rule']}\n';
      info += '目标: ${conn['target']}\n';
      info += '时长: ${ImprovedTrafficStatsService.formatDuration(conn['duration'])}\n';
      info += '开始时间: ${conn['startTime']}\n\n';
    }

    Clipboard.setData(ClipboardData(text: info));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('连接状态详情已复制到剪贴板'),
        backgroundColor: AppTheme.successGreen,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Column(
        children: [
          // 顶部标题栏
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.borderColor.withAlpha(50),
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => safePop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.bgDark,
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
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            '连接状态',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Consumer<VPNProviderV2>(
                            builder: (context, provider, _) {
                              if (!provider.isConnected) return Container();

                              final sourceText = provider.connectionSource;
                              final sourceColor = sourceText == 'Clash API'
                                ? AppTheme.successGreen
                                : AppTheme.warningOrange;
                              final sourceIcon = sourceText == 'Clash API'
                                ? Icons.api
                                : Icons.computer;

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: sourceColor.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: sourceColor.withAlpha(100),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(sourceIcon, size: 12, color: sourceColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      sourceText,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: sourceColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    // 统计信息
                    Consumer<VPNProviderV2>(
                      builder: (context, provider, _) {
                        if (!provider.isConnected) return Container();

                        final connections = provider.connections;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryNeon.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${connections.length} 连接',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryNeon,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // 菜单按钮
                    Consumer<VPNProviderV2>(
                      builder: (context, provider, _) {
                        if (!provider.isConnected) return Container();

                        return PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert,
                            color: AppTheme.textSecondary,
                          ),
                          color: AppTheme.bgCard,
                          onSelected: (value) {
                            switch (value) {
                              case 'pause':
                                setState(() {
                                  isPaused = !isPaused;
                                });
                                break;
                              case 'copy':
                                final filtered = _filterConnections(provider.connections);
                                _copyConnectionInfo(filtered);
                                break;
                              case 'sort_time':
                                setState(() {
                                  sortBy = 'time';
                                });
                                break;
                              case 'sort_upload':
                                setState(() {
                                  sortBy = 'upload';
                                });
                                break;
                              case 'sort_download':
                                setState(() {
                                  sortBy = 'download';
                                });
                                break;
                              case 'sort_total':
                                setState(() {
                                  sortBy = 'total';
                                });
                                break;
                              case 'expand_all':
                                setState(() {
                                  for (final conn in provider.connections) {
                                    _expandedItems.add(conn['id']);
                                  }
                                });
                                break;
                              case 'collapse_all':
                                setState(() {
                                  _expandedItems.clear();
                                });
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'pause',
                              child: Row(
                                children: [
                                  Icon(
                                    isPaused ? Icons.play_arrow : Icons.pause,
                                    size: 18,
                                    color: AppTheme.primaryNeon,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(isPaused ? '继续' : '暂停'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'copy',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.copy,
                                    size: 18,
                                    color: AppTheme.primaryNeon,
                                  ),
                                  SizedBox(width: 8),
                                  Text('复制详情'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'expand_all',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.unfold_more,
                                    size: 18,
                                    color: AppTheme.textSecondary,
                                  ),
                                  SizedBox(width: 8),
                                  Text('全部展开'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'collapse_all',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.unfold_less,
                                    size: 18,
                                    color: AppTheme.textSecondary,
                                  ),
                                  SizedBox(width: 8),
                                  Text('全部收起'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'sort_time',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 18,
                                    color: sortBy == 'time' ? AppTheme.primaryNeon : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('按时长排序'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'sort_upload',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.upload,
                                    size: 18,
                                    color: sortBy == 'upload' ? AppTheme.primaryNeon : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('按上传排序'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'sort_download',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.download,
                                    size: 18,
                                    color: sortBy == 'download' ? AppTheme.primaryNeon : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('按下载排序'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'sort_total',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.data_usage,
                                    size: 18,
                                    color: sortBy == 'total' ? AppTheme.primaryNeon : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('按总流量排序'),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 搜索栏和过滤器
                Row(
                  children: [
                    // 搜索框
                    Expanded(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.bgDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.borderColor.withAlpha(50),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            hintText: '搜索主机、进程、规则...',
                            hintStyle: TextStyle(
                              color: AppTheme.textHint,
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppTheme.textHint,
                              size: 18,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 协议过滤
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.borderColor.withAlpha(50),
                        ),
                      ),
                      child: DropdownButton<String>(
                        value: filterProtocol,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('全部')),
                          DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                          DropdownMenuItem(value: 'udp', child: Text('UDP')),
                        ],
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                        dropdownColor: AppTheme.bgCard,
                        underline: Container(),
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        onChanged: (value) {
                          setState(() {
                            filterProtocol = value ?? 'all';
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 连接列表
          Expanded(
            child: Consumer<VPNProviderV2>(
              builder: (context, provider, _) {
                if (!provider.isConnected) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_off,
                          size: 80,
                          color: AppTheme.textSecondary.withAlpha(100),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'VPN未连接',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '连接VPN后可查看连接详情',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // 暂停时显示暂停状态
                if (isPaused) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.pause_circle_outline,
                          size: 60,
                          color: AppTheme.warningOrange.withAlpha(150),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '监控已暂停',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.warningOrange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // 过滤和排序连接列表
                var connections = List<Map<String, dynamic>>.from(
                  provider.connections,
                );
                connections = _filterConnections(connections);
                _sortConnections(connections);

                if (connections.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 60,
                          color: AppTheme.textSecondary.withAlpha(100),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '没有找到符合条件的连接',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: connections.length,
                  itemBuilder: (context, index) {
                    final connection = connections[index];
                    final isExpanded = _expandedItems.contains(connection['id']);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isExpanded
                            ? AppTheme.primaryNeon.withAlpha(100)
                            : AppTheme.borderColor.withAlpha(100),
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedItems.remove(connection['id']);
                            } else {
                              _expandedItems.add(connection['id']);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 主要信息行
                              Row(
                                children: [
                                  // 序号
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryNeon.withAlpha(30),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryNeon,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // 主机信息
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // 显示域名或IP
                                            Expanded(
                                              child: connection['domain'] != null
                                                ? Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        connection['domain'],
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w600,
                                                          color: AppTheme.textPrimary,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      Text(
                                                        connection['hostAddr'],
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppTheme.textSecondary,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  )
                                                : Text(
                                                    connection['hostAddr'],
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppTheme.textPrimary,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                            ),
                                            const SizedBox(width: 4),
                                            // 端口
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryNeon.withAlpha(20),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                ':${connection['hostPort']}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.primaryNeon,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            // 代理协议标签（如果有）
                                            if (connection['proxyProtocol'] != null) ...[
                                              const SizedBox(width: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _getProtocolColor(connection['proxyProtocol']).withAlpha(30),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: _getProtocolColor(connection['proxyProtocol']).withAlpha(100),
                                                    width: 0.5,
                                                  ),
                                                ),
                                                child: Text(
                                                  connection['proxyProtocol'],
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: _getProtocolColor(connection['proxyProtocol']),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            // 协议
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.textHint.withAlpha(30),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                connection['protocol'],
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.textHint,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            // 进程
                                            Expanded(
                                              child: Text(
                                                connection['process'],
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textSecondary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 流量和时长
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        ImprovedTrafficStatsService.formatDuration(
                                          connection['duration'],
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${ImprovedTrafficStatsService.formatBytes(connection['uploadBytes'])}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.successGreen,
                                            ),
                                          ),
                                          const Text(
                                            ' / ',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.textHint,
                                            ),
                                          ),
                                          Text(
                                            '${ImprovedTrafficStatsService.formatBytes(connection['downloadBytes'])}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.primaryNeon,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  // 展开图标
                                  AnimatedRotation(
                                    turns: isExpanded ? 0.25 : 0,
                                    duration: const Duration(milliseconds: 200),
                                    child: const Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: AppTheme.textHint,
                                    ),
                                  ),
                                ],
                              ),

                              // 展开的详细信息
                              if (isExpanded) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.bgDark,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 本地地址
                                      _buildDetailRow(
                                        '本地地址',
                                        '${connection['localAddr']}:${connection['localPortOnly']}',
                                        Icons.computer,
                                      ),
                                      const SizedBox(height: 8),
                                      // 进程信息
                                      _buildDetailRow(
                                        '进程',
                                        '${connection['process']} (PID: ${connection['pid']})',
                                        Icons.apps,
                                      ),
                                      const SizedBox(height: 8),
                                      // 连接状态
                                      if (connection['state'].toString().isNotEmpty) ...[
                                        _buildDetailRow(
                                          '状态',
                                          connection['state'],
                                          Icons.info_outline,
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      // 规则
                                      _buildDetailRow(
                                        '匹配规则',
                                        connection['rule'],
                                        Icons.rule,
                                      ),
                                      const SizedBox(height: 8),
                                      // 代理链
                                      _buildDetailRow(
                                        connection['chains'] != null && (connection['chains'] as List).isNotEmpty
                                          ? '代理链'
                                          : '目标',
                                        connection['chains'] != null && (connection['chains'] as List).isNotEmpty
                                          ? (connection['chains'] as List).join(' → ')
                                          : connection['target'],
                                        Icons.route,
                                      ),
                                      const SizedBox(height: 8),
                                      // 实时速度
                                      if (connection['uploadSpeed'] > 0 || connection['downloadSpeed'] > 0) ...[
                                        _buildDetailRow(
                                          '实时速度',
                                          '↑ ${ImprovedTrafficStatsService.formatSpeed(connection['uploadSpeed'])}  ↓ ${ImprovedTrafficStatsService.formatSpeed(connection['downloadSpeed'])}',
                                          Icons.speed,
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      // 总流量
                                      _buildDetailRow(
                                        '总流量',
                                        '${ImprovedTrafficStatsService.formatBytes(connection['totalBytes'])}',
                                        Icons.data_usage,
                                      ),
                                      const SizedBox(height: 8),
                                      // 开始时间
                                      _buildDetailRow(
                                        '开始时间',
                                        _formatDateTime(connection['startTime']),
                                        Icons.access_time,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: AppTheme.textHint,
        ),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '未知';
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays > 0) {
      return '${dateTime.month}月${dateTime.day}日 ${_pad(dateTime.hour)}:${_pad(dateTime.minute)}';
    } else {
      return '今天 ${_pad(dateTime.hour)}:${_pad(dateTime.minute)}:${_pad(dateTime.second)}';
    }
  }

  String _pad(int value) {
    return value.toString().padLeft(2, '0');
  }

  // 根据代理协议返回颜色
  Color _getProtocolColor(String protocol) {
    switch (protocol.toUpperCase()) {
      case 'VMESS':
        return Colors.blue;
      case 'VLESS':
        return Colors.cyan;
      case 'TROJAN':
        return Colors.orange;
      case 'SHADOWSOCKS':
      case 'SS':
        return Colors.green;
      case 'SHADOWSOCKSR':
      case 'SSR':
        return Colors.teal;
      case 'HYSTERIA':
        return Colors.purple;
      case 'TUIC':
        return Colors.pink;
      case 'WIREGUARD':
      case 'WG':
        return Colors.indigo;
      case 'HTTP':
        return Colors.amber;
      case 'SOCKS':
        return Colors.deepOrange;
      default:
        return AppTheme.primaryNeon;
    }
  }
}