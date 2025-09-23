import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/connection_traffic_history_service.dart';
import '../services/improved_traffic_stats_service.dart';

class TrafficHistoryPage extends StatefulWidget {
  const TrafficHistoryPage({super.key});

  @override
  State<TrafficHistoryPage> createState() => _TrafficHistoryPageState();
}

class _TrafficHistoryPageState extends State<TrafficHistoryPage> {
  String sortBy = 'total'; // total, upload, download, time

  @override
  void initState() {
    super.initState();
    // 确保加载历史
    ConnectionTrafficHistoryService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: ConnectionTrafficHistoryService.instance,
      child: Scaffold(
        backgroundColor: AppTheme.bgDark,
        appBar: AppBar(
          backgroundColor: AppTheme.bgDark,
          elevation: 0,
          title: const Text(
            '流量历史',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          iconTheme: const IconThemeData(color: AppTheme.textPrimary),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              color: AppTheme.bgCard,
              onSelected: (v) async {
                if (v == 'clear') {
                  await ConnectionTrafficHistoryService.instance.clearHistory();
                } else if (v.startsWith('sort_')) {
                  setState(() {
                    sortBy = v.substring('sort_'.length);
                  });
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'clear', child: Text('清空历史')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'sort_total', child: Text('按合计排序')),
                PopupMenuItem(value: 'sort_upload', child: Text('按上传排序')),
                PopupMenuItem(value: 'sort_download', child: Text('按下载排序')),
                PopupMenuItem(value: 'sort_time', child: Text('按时长排序')),
              ],
            ),
          ],
        ),
        body: Consumer<ConnectionTrafficHistoryService>(
          builder: (context, svc, _) {
            final records = List.of(svc.allRecords);

            // 排序
            switch (sortBy) {
              case 'upload':
                records.sort((a, b) => b.uploadBytes.compareTo(a.uploadBytes));
                break;
              case 'download':
                records.sort(
                  (a, b) => b.downloadBytes.compareTo(a.downloadBytes),
                );
                break;
              case 'time':
                records.sort((a, b) => b.duration.compareTo(a.duration));
                break;
              default:
                records.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
            }

            if (records.isEmpty) {
              return Center(
                child: Text(
                  '暂无记录',
                  style: TextStyle(
                    color: AppTheme.textSecondary.withAlpha(180),
                    fontSize: 14,
                  ),
                ),
              );
            }

            final totalUpload = records.fold<int>(
              0,
              (s, r) => s + r.uploadBytes,
            );
            final totalDownload = records.fold<int>(
              0,
              (s, r) => s + r.downloadBytes,
            );
            final totalAll = totalUpload + totalDownload;

            return Column(
              children: [
                // 汇总条
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.borderColor.withAlpha(100),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '合计: ${ImprovedTrafficStatsService.formatBytes(totalAll)}',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  '↑ ${ImprovedTrafficStatsService.formatBytes(totalUpload)}',
                                  style: const TextStyle(
                                    color: AppTheme.successGreen,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '↓ ${ImprovedTrafficStatsService.formatBytes(totalDownload)}',
                                  style: const TextStyle(
                                    color: AppTheme.primaryNeon,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '共 ${records.length} 条',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final r = records[index];
                      final upRatio = totalUpload > 0
                          ? r.uploadBytes / totalUpload
                          : 0;
                      final downRatio = totalDownload > 0
                          ? r.downloadBytes / totalDownload
                          : 0;
                      final totalRatio = totalAll > 0
                          ? r.totalBytes / totalAll
                          : 0;
                      final title = r.domain?.isNotEmpty == true
                          ? r.domain!
                          : r.host;
                      return Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        padding: const EdgeInsets.all(12),
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (r.active)
                                      const Text(
                                        '进行中',
                                        style: TextStyle(
                                          color: AppTheme.textHint,
                                          fontSize: 11,
                                        ),
                                      )
                                    else
                                      Text(
                                        '${r.startTime.toLocal().toString().split(".").first} ~ ${(r.endTime ?? DateTime.now()).toLocal().toString().split(".").first}',
                                        style: const TextStyle(
                                          color: AppTheme.textHint,
                                          fontSize: 11,
                                        ),
                                      ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      tooltip: '复制详情',
                                      icon: const Icon(
                                        Icons.copy,
                                        size: 18,
                                        color: AppTheme.textSecondary,
                                      ),
                                      onPressed: () {
                                        final startStr = r.startTime
                                            .toLocal()
                                            .toString()
                                            .split('.')
                                            .first;
                                        final endStr =
                                            (r.endTime ?? DateTime.now())
                                                .toLocal()
                                                .toString()
                                                .split('.')
                                                .first;
                                        String info = '流量记录\n';
                                        info +=
                                            '时间: ${DateTime.now().toString()}\n\n';
                                        info += '标题: ' + title + '\n';
                                        info += '主机: ' + r.host + '\n';
                                        if (r.domain != null &&
                                            r.domain!.isNotEmpty) {
                                          info += '域名: ' + r.domain! + '\n';
                                        }
                                        info += '进程: ' + r.process + '\n';
                                        info +=
                                            '协议: ' +
                                            r.protocol.toUpperCase() +
                                            '\n';
                                        info += '规则: ' + r.rule + '\n';
                                        info += '目标: ' + r.target + '\n';
                                        info +=
                                            '上传: ' +
                                            ImprovedTrafficStatsService.formatBytes(
                                              r.uploadBytes,
                                            ) +
                                            ' (' +
                                            (upRatio * 100)
                                                .toStringAsFixed(1)
                                                .replaceAll('.0', '') +
                                            '%)\n';
                                        info +=
                                            '下载: ' +
                                            ImprovedTrafficStatsService.formatBytes(
                                              r.downloadBytes,
                                            ) +
                                            ' (' +
                                            (downRatio * 100)
                                                .toStringAsFixed(1)
                                                .replaceAll('.0', '') +
                                            '%)\n';
                                        info +=
                                            '合计: ' +
                                            ImprovedTrafficStatsService.formatBytes(
                                              r.totalBytes,
                                            ) +
                                            ' (' +
                                            (totalRatio * 100)
                                                .toStringAsFixed(1)
                                                .replaceAll('.0', '') +
                                            '%)\n';
                                        info +=
                                            '时长: ' +
                                            ImprovedTrafficStatsService.formatDuration(
                                              r.duration,
                                            ) +
                                            '\n';
                                        if (r.active) {
                                          info += '状态: 进行中\n';
                                        } else {
                                          info +=
                                              '时间范围: ' +
                                              startStr +
                                              ' ~ ' +
                                              endStr +
                                              '\n';
                                        }
                                        Clipboard.setData(
                                          ClipboardData(text: info),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('已复制该记录详情到剪贴板'),
                                            backgroundColor:
                                                AppTheme.successGreen,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
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
                                    '↑ ${ImprovedTrafficStatsService.formatBytes(r.uploadBytes)}',
                                    style: const TextStyle(
                                      color: AppTheme.successGreen,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
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
                                    '↓ ${ImprovedTrafficStatsService.formatBytes(r.downloadBytes)}',
                                    style: const TextStyle(
                                      color: AppTheme.primaryNeon,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '合计 ${ImprovedTrafficStatsService.formatBytes(r.totalBytes)}',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // 占比
                            Row(
                              children: [
                                Text(
                                  '↑占比 ${(upRatio * 100).toStringAsFixed(1)}%'
                                      .replaceAll('.0%', '%'),
                                  style: const TextStyle(
                                    color: AppTheme.successGreen,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '↓占比 ${(downRatio * 100).toStringAsFixed(1)}%'
                                      .replaceAll('.0%', '%'),
                                  style: const TextStyle(
                                    color: AppTheme.primaryNeon,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '合计 ${(totalRatio * 100).toStringAsFixed(1)}%'
                                      .replaceAll('.0%', '%'),
                                  style: const TextStyle(
                                    color: AppTheme.textHint,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // 其它信息
                            Text(
                              '${r.process}  •  ${r.protocol.toUpperCase()}  •  ${r.rule} → ${r.target}',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '时长 ${ImprovedTrafficStatsService.formatDuration(r.duration)}',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
