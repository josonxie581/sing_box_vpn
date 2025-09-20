import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/geosite_manager.dart';
import '../utils/navigation.dart';

class GeositeManagerPage extends StatefulWidget {
  const GeositeManagerPage({super.key});

  @override
  State<GeositeManagerPage> createState() => _GeositeManagerPageState();
}

class _GeositeManagerPageState extends State<GeositeManagerPage> {
  final GeositeManager _geositeManager = GeositeManager();
  List<String> _downloadedRulesets = [];
  bool _isLoading = false;
  final Map<String, double> _downloadProgress = {};
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadDownloadedRulesets();
  }

  Future<void> _loadDownloadedRulesets() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final downloaded = await _geositeManager.getDownloadedRulesets();
      setState(() {
        _downloadedRulesets = downloaded;
      });
    } catch (e) {
      _showMessage('加载规则集列表失败: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorRed : AppTheme.successGreen,
      ),
    );
  }

  Future<void> _downloadAllCommonRulesets() async {
    // 先获取统计信息
    final stats = await _geositeManager.getCommonRulesetsStats();
    final missingCount = stats['missing'] as int;

    if (missingCount == 0) {
      _showMessage('所有常用规则集已下载完成');
      return;
    }

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '一键下载',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '即将下载 ${stats['total']} 个常用规则集：',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '• Geosite 规则集：${stats['geosite']} 个',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            Text(
              '• GeoIP 规则集：${stats['geoip']} 个',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '已下载：${stats['downloaded']} 个',
              style: const TextStyle(
                color: AppTheme.successGreen,
                fontSize: 14,
              ),
            ),
            Text(
              '待下载：$missingCount 个',
              style: const TextStyle(color: AppTheme.primaryNeon, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryNeon.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '⚠️ 下载过程可能需要较长时间，请保持网络连接稳定',
                style: TextStyle(color: AppTheme.primaryNeon, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.successGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('开始下载'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '准备一键下载...';
    });

    try {
      final results = await _geositeManager.downloadAllCommonRulesets(
        onStatus: (status) {
          setState(() {
            _statusMessage = status;
          });
        },
        onProgress: (ruleset, progress) {
          // 可以在这里更新单个规则集的下载进度
        },
      );

      final successCount = results.values.where((v) => v).length;
      final totalCount = results.length;

      if (successCount == totalCount) {
        _showMessage('全部规则集下载完成！($successCount/$totalCount)');
      } else {
        _showMessage(
          '下载完成：$successCount/$totalCount 个规则集成功',
          isError: successCount < totalCount * 0.8,
        );
      }

      await _loadDownloadedRulesets();
    } catch (e) {
      _showMessage('一键下载失败: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
    }
  }

  Future<void> _downloadCategoryRulesets(String categoryName) async {
    setState(() {
      _isLoading = true;
      _statusMessage = '准备下载 $categoryName 分类...';
    });

    try {
      final results = await _geositeManager.downloadCategoryRulesets(
        categoryName,
        onStatus: (status) {
          setState(() {
            _statusMessage = status;
          });
        },
        onProgress: (ruleset, progress) {
          setState(() {
            _downloadProgress[ruleset] = progress;
          });
        },
      );

      final successCount = results.values.where((v) => v).length;
      final totalCount = results.length;

      // 清理下载进度
      for (final ruleset in results.keys) {
        _downloadProgress.remove(ruleset);
      }

      if (successCount == totalCount) {
        _showMessage('$categoryName 分类下载完成！($successCount/$totalCount)');
      } else {
        _showMessage(
          '$categoryName 分类下载完成：$successCount/$totalCount 个规则集成功',
          isError: successCount < totalCount * 0.8,
        );
      }

      await _loadDownloadedRulesets();
    } catch (e) {
      _showMessage('下载 $categoryName 分类失败: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
    }
  }

  Future<void> _downloadBasicRulesets() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '准备下载基础规则集...';
    });

    try {
      final success = await _geositeManager.downloadBasicRulesets(
        onStatus: (status) {
          setState(() {
            _statusMessage = status;
          });
        },
      );

      if (success) {
        _showMessage('基础规则集下载完成');
        await _loadDownloadedRulesets();
      } else {
        _showMessage('基础规则集下载失败', isError: true);
      }
    } catch (e) {
      _showMessage('下载失败: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
    }
  }

  Future<void> _forceUpdateAllRulesets() async {
    // 先获取统计信息
    final stats = await _geositeManager.getCommonRulesetsStats();
    final downloadedCount = stats['downloaded'] as int;

    if (downloadedCount == 0) {
      _showMessage('没有已下载的规则集，请使用"一键下载全部"');
      return;
    }

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '更新全部',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '即将强制更新 ${stats['total']} 个规则集（包括已下载的）：',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '• Geosite 规则集：${stats['geosite']} 个',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            Text(
              '• GeoIP 规则集：${stats['geoip']} 个',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前已下载：$downloadedCount 个',
              style: const TextStyle(
                color: AppTheme.successGreen,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warningOrange.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: AppTheme.warningOrange, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '这将重新下载所有规则集，覆盖现有文件',
                      style: TextStyle(
                        color: AppTheme.warningOrange,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warningOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('强制更新'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '准备强制更新...';
    });

    try {
      final results = await _geositeManager.downloadAllCommonRulesets(
        forceUpdate: true, // 强制更新
        onStatus: (status) {
          setState(() {
            _statusMessage = status;
          });
        },
        onProgress: (ruleset, progress) {
          // 可以在这里更新单个规则集的下载进度
        },
      );

      final successCount = results.values.where((v) => v).length;
      final totalCount = results.length;

      if (successCount == totalCount) {
        _showMessage('全部规则集更新完成！($successCount/$totalCount)');
      } else {
        _showMessage(
          '更新完成：$successCount/$totalCount 个规则集成功',
          isError: successCount < totalCount * 0.8,
        );
      }

      await _loadDownloadedRulesets();
    } catch (e) {
      _showMessage('一键更新失败: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
    }
  }

  Future<void> _downloadRuleset(String rulesetName) async {
    setState(() {
      _downloadProgress[rulesetName] = 0.0;
    });

    try {
      final success = await _geositeManager.downloadRuleset(
        rulesetName,
        onProgress: (progress) {
          setState(() {
            _downloadProgress[rulesetName] = progress;
          });
        },
      );

      if (success) {
        _showMessage('$rulesetName 下载完成');
        await _loadDownloadedRulesets();
      } else {
        _showMessage('$rulesetName 下载失败', isError: true);
      }
    } catch (e) {
      _showMessage('下载 $rulesetName 失败: $e', isError: true);
    } finally {
      setState(() {
        _downloadProgress.remove(rulesetName);
      });
    }
  }

  Future<void> _deleteRuleset(String rulesetName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '确认删除',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要删除规则集 $rulesetName 吗？',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _geositeManager.deleteRuleset(rulesetName);
        _showMessage('$rulesetName 已删除');
        await _loadDownloadedRulesets();
      } catch (e) {
        _showMessage('删除失败: $e', isError: true);
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.primaryNeon,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesetCard(String categoryName, List<String> rulesets) {
    final downloadedCount = rulesets
        .where((r) => _downloadedRulesets.contains(r))
        .length;
    final totalCount = rulesets.length;

    return Card(
      color: AppTheme.bgCard,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                categoryName,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 分类统计和批量下载按钮
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 统计信息
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: downloadedCount == totalCount
                          ? AppTheme.successGreen.withAlpha(30)
                          : AppTheme.primaryNeon.withAlpha(30),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '$downloadedCount/$totalCount',
                      style: TextStyle(
                        color: downloadedCount == totalCount
                            ? AppTheme.successGreen
                            : AppTheme.primaryNeon,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 批量下载按钮
                  if (downloadedCount < totalCount)
                    InkWell(
                      onTap: _isLoading
                          ? null
                          : () => _downloadCategoryRulesets(categoryName),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.cloud_download,
                          size: 16,
                          color: _isLoading
                              ? AppTheme.textSecondary
                              : AppTheme.primaryNeon,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        iconColor: AppTheme.primaryNeon,
        collapsedIconColor: AppTheme.textSecondary,
        children: rulesets.map((ruleset) {
          final isDownloaded = _downloadedRulesets.contains(ruleset);
          final isDownloading = _downloadProgress.containsKey(ruleset);

          return ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  GeositeManager.isGeoIPRuleset(ruleset)
                      ? Icons.location_on_outlined
                      : Icons.language_outlined,
                  color: GeositeManager.isGeoIPRuleset(ruleset)
                      ? Colors.orange
                      : AppTheme.primaryNeon,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Icon(
                  isDownloaded ? Icons.check_circle : Icons.download_outlined,
                  color: isDownloaded
                      ? AppTheme.successGreen
                      : AppTheme.textSecondary,
                ),
              ],
            ),
            title: Text(
              ruleset,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            ),
            subtitle: isDownloading
                ? LinearProgressIndicator(
                    value: _downloadProgress[ruleset],
                    backgroundColor: AppTheme.borderColor.withAlpha(50),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryNeon,
                    ),
                  )
                : null,
            trailing: isDownloaded
                ? IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppTheme.errorRed,
                    ),
                    onPressed: () => _deleteRuleset(ruleset),
                  )
                : IconButton(
                    icon: isDownloading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.primaryNeon,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.download,
                            color: AppTheme.primaryNeon,
                          ),
                    onPressed: isDownloading
                        ? null
                        : () => _downloadRuleset(ruleset),
                  ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
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
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              border: Border(
                bottom: BorderSide(color: AppTheme.borderColor.withAlpha(50)),
              ),
            ),
            child: Row(
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
                // const SizedBox(width: 12),
                // const Expanded(
                //   child: Text(
                //     '规则集管理',
                //     style: TextStyle(
                //       fontSize: 20,
                //       fontWeight: FontWeight.bold,
                //       color: AppTheme.textPrimary,
                //     ),
                //   ),
                // ),
                // 快速下载按钮
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _downloadBasicRulesets,
                      // icon: const Icon(Icons.download_for_offline, size: 12),
                      label: const Text('基础下载'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryNeon,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(100, 36),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _downloadAllCommonRulesets,
                      // icon: const Icon(Icons.cloud_download, size: 12),
                      label: const Text('一键下载'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successGreen,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(120, 36),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _forceUpdateAllRulesets,
                      // icon: const Icon(Icons.refresh, size: 12),
                      label: const Text('一键更新'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.warningOrange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(100, 36),
                      ),
                    ),
                    // Container(
                    //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    //   decoration: BoxDecoration(
                    //     color: AppTheme.primaryNeon.withAlpha(30),
                    //     borderRadius: BorderRadius.circular(4),
                    //   ),
                    //   child: Text(
                    //     'Geosite + GeoIP',
                    //     style: TextStyle(
                    //       color: AppTheme.primaryNeon,
                    //       fontSize: 12,
                    //       fontWeight: FontWeight.w500,
                    //     ),
                    //   ),
                    // ),
                  ],
                ),
              ],
            ),
          ),

          // 状态信息
          if (_statusMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppTheme.primaryNeon.withAlpha(20),
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: AppTheme.primaryNeon,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // 规则集统计信息
          FutureBuilder<Map<String, dynamic>>(
            future: _geositeManager.getCommonRulesetsStats(),
            builder: (context, snapshot) {
              final stats = snapshot.data;
              return Container(
                margin: const EdgeInsets.all(20),
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
                    Row(
                      children: [
                        const Icon(
                          Icons.analytics_outlined,
                          color: AppTheme.primaryNeon,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '规则集统计',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (_downloadedRulesets.isNotEmpty)
                          TextButton(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: AppTheme.bgCard,
                                  title: const Text(
                                    '清理所有规则集',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  content: const Text(
                                    '确定要删除所有已下载的规则集吗？',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text(
                                        '清理',
                                        style: TextStyle(
                                          color: AppTheme.errorRed,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                try {
                                  await _geositeManager.clearAllRulesets();
                                  _showMessage('所有规则集已清理');
                                  await _loadDownloadedRulesets();
                                } catch (e) {
                                  _showMessage('清理失败: $e', isError: true);
                                }
                              }
                            },
                            child: const Text(
                              '清理全部',
                              style: TextStyle(color: AppTheme.errorRed),
                            ),
                          ),
                      ],
                    ),
                    if (stats != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatItem(
                              '总计',
                              '${stats['total']}',
                              AppTheme.textPrimary,
                            ),
                          ),
                          Expanded(
                            child: _buildStatItem(
                              'Geosite',
                              '${stats['geosite']}',
                              AppTheme.primaryNeon,
                            ),
                          ),
                          Expanded(
                            child: _buildStatItem(
                              'GeoIP',
                              '${stats['geoip']}',
                              Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatItem(
                              '已下载',
                              '${stats['downloaded']}',
                              AppTheme.successGreen,
                            ),
                          ),
                          Expanded(
                            child: _buildStatItem(
                              '待下载',
                              '${stats['missing']}',
                              AppTheme.errorRed,
                            ),
                          ),
                          Expanded(
                            child: _buildStatItem(
                              '完成度',
                              '${(stats['downloaded'] / stats['total'] * 100).toStringAsFixed(0)}%',
                              stats['downloaded'] == stats['total']
                                  ? AppTheme.successGreen
                                  : AppTheme.primaryNeon,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      const Text(
                        '正在加载统计信息...',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          // 规则集列表
          Expanded(
            child: _isLoading && _statusMessage.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryNeon,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // Geosite 分类
                      _buildSectionHeader('Geosite 域名规则'),
                      ...GeositeManager.geositeCategories.entries.map(
                        (entry) => _buildRulesetCard(entry.key, entry.value),
                      ),

                      const SizedBox(height: 20),

                      // GeoIP 分类
                      _buildSectionHeader('GeoIP 地址规则'),
                      ...GeositeManager.geoipCategories.entries.map(
                        (entry) => _buildRulesetCard(entry.key, entry.value),
                      ),

                      // 底部说明
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNeon.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primaryNeon.withAlpha(50),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline,
                                  color: AppTheme.primaryNeon,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '使用提示',
                                  style: TextStyle(
                                    color: AppTheme.primaryNeon,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '• 建议先下载"基础规则"，包含最常用的分流规则\n'
                              '• 使用"一键下载全部"可获取所有常用规则集\n'
                              '• 点击分类右侧的下载图标可批量下载该分类\n'
                              '• 下载完成后，在"分流规则配置"中启用所需规则',
                              style: TextStyle(
                                color: AppTheme.primaryNeon,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
