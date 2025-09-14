import 'package:flutter/material.dart';
import '../utils/navigation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/vpn_provider.dart';
import '../services/connection_stats_service.dart';

class ConnectionStatusPage extends StatefulWidget {
  const ConnectionStatusPage({super.key});

  @override
  State<ConnectionStatusPage> createState() => _ConnectionStatusPageState();
}

class _ConnectionStatusPageState extends State<ConnectionStatusPage> {
  bool isPaused = false;
  String sortBy = 'time'; // time, upload, download

  void _sortConnections(List<Map<String, dynamic>> connections) {
    switch (sortBy) {
      case 'upload':
        connections.sort(
          (a, b) =>
              (b['uploadSpeed'] as int).compareTo(a['uploadSpeed'] as int),
        );
        break;
      case 'download':
        connections.sort(
          (a, b) =>
              (b['downloadSpeed'] as int).compareTo(a['downloadSpeed'] as int),
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

  void _copyConnectionInfo(List<Map<String, dynamic>> connections) {
    String info = '连接状态信息\n\n';
    for (int i = 0; i < connections.length; i++) {
      final conn = connections[i];
      info += '${i + 1}. ${conn['host']}\n';
      info += '   ${conn['localPort']} ${conn['process']}\n';
      info +=
          '   ${conn['protocol']} ↑${_formatBytes(conn['uploadBytes'])} ↓${_formatBytes(conn['downloadBytes'])}\n';
      info += '   ${conn['rule']}\n';
      info += '   ${conn['target']}\n';
      info += '   时长: ${_formatDuration(conn['duration'])}\n\n';
    }

    Clipboard.setData(ClipboardData(text: info));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('连接状态已复制到剪贴板'),
        backgroundColor: AppTheme.successGreen,
      ),
    );
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
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => safePop(context),
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
                      Consumer<VPNProvider>(
                        builder: (context, provider, _) {
                          if (!provider.isConnected) return Container();
                          
                          String sourceText;
                          Color sourceColor;
                          IconData sourceIcon;
                          
                          switch (provider.connectionSource) {
                            case ConnectionSource.clashAPI:
                              sourceText = 'Clash API';
                              sourceColor = AppTheme.successGreen;
                              sourceIcon = Icons.api;
                              break;
                            case ConnectionSource.system:
                              sourceText = '系统';
                              sourceColor = AppTheme.primaryNeon;
                              sourceIcon = Icons.computer;
                              break;
                          }
                          
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
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
                                Icon(
                                  sourceIcon,
                                  size: 12,
                                  color: sourceColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  sourceText,
                                  style: TextStyle(
                                    fontSize: 10,
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
                // 菜单按钮
                Consumer<VPNProvider>(
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
                            _copyConnectionInfo(provider.connections);
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
                              Text('复制'),
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
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              const Text('按时长排序'),
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
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              const Text('按上传排序'),
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
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              const Text('按下载排序'),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          // 连接列表
          Expanded(
            child: Consumer<VPNProvider>(
              builder: (context, provider, _) {
                if (!provider.isConnected) {
                  // VPN未连接时显示提示
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

                // VPN已连接时显示连接列表
                final connections = List<Map<String, dynamic>>.from(
                  provider.connections,
                );
                _sortConnections(connections);

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: connections.length,
                  itemBuilder: (context, index) {
                    final connection = connections[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.borderColor.withAlpha(100),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 第一行：序号和主机地址、时长
                          Row(
                            children: [
                              // 序号圆圈
                              Container(
                                width: 24,
                                height: 24,
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
                              Expanded(
                                child: Text(
                                  connection['host'],
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                _formatDuration(connection['duration']),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 展开按钮
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: AppTheme.textHint,
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // 第二行：本地端口和进程
                          Text(
                            '${connection['localPort']} ${connection['process']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),

                          const SizedBox(height: 4),

                          // 第三行：协议和传输数据
                          Row(
                            children: [
                              Text(
                                connection['protocol'],
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.successGreen.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '↑${_formatBytes(connection['uploadBytes'])}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.successGreen,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryNeon.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '↓${_formatBytes(connection['downloadBytes'])}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.primaryNeon,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 显示当前上传/下载速度
                              if (connection['uploadSpeed'] != null && connection['uploadSpeed'] > 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.textHint.withAlpha(30),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '↑${_formatSpeed(connection['uploadSpeed'])}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: AppTheme.textHint,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (connection['downloadSpeed'] != null && connection['downloadSpeed'] > 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.textHint.withAlpha(30),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '↓${_formatSpeed(connection['downloadSpeed'])}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: AppTheme.textHint,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: 4),

                          // 第四行：规则
                          Text(
                            connection['rule'],
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),

                          const SizedBox(height: 4),

                          // 第五行：目标
                          Text(
                            connection['target'],
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '${bytesPerSecond}B/s';
    if (bytesPerSecond < 1024 * 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(1)}KB/s';
    if (bytesPerSecond < 1024 * 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)}MB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB/s';
  }
}
