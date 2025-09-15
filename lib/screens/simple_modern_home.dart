import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider_v2.dart';
import '../services/improved_traffic_stats_service.dart';
import '../models/proxy_mode.dart';
import '../models/vpn_config.dart';
import '../theme/app_theme.dart';
import '../services/ping_service.dart';
// import 'add_config_page.dart';
import 'connection_status_page.dart';
import 'routing_rules_page.dart';
import 'dns_settings_page.dart';
import 'config_management_page.dart';
import 'logs_page.dart';
import '../widgets/animated_connection_button.dart';
import '../widgets/hover_scale.dart';
import 'package:gsou/utils/privilege_manager.dart';

class SimpleModernHome extends StatelessWidget {
  const SimpleModernHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VPNProviderV2>(
      builder: (context, provider, _) {
        return Scaffold(
          body: Container(
            decoration: AppTheme.gradientBackground(),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Handle small window size during transition
                  if (constraints.maxWidth < 400) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        // 当前配置显示（小卡片 + 绝对居中按钮）
                        HoverScale(
                          enabled: true,
                          scale: 1.04,
                          child: Container(
                            width: double.infinity,
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppTheme.borderColor.withAlpha(80),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  offset: const Offset(0, 4),
                                  blurRadius: 12,
                                  spreadRadius: 0,
                                ),
                                BoxShadow(
                                  color: AppTheme.primaryNeon.withOpacity(0.05),
                                  offset: const Offset(0, 1),
                                  blurRadius: 3,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                // 顶部标题与状态点
                                Positioned(
                                  top: 10,
                                  left: 12,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.list_alt,
                                        color: AppTheme.primaryNeon,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '当前配置',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (provider.currentConfig != null)
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: provider.isConnected
                                                ? AppTheme.successGreen
                                                : AppTheme.warningOrange,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // 顶部右侧连接状态文字
                                // Positioned(
                                //   top: 10,
                                //   right: 12,
                                //   child: Text(
                                //     provider.isConnected ? '已连接' : '未连接',
                                //     style: TextStyle(
                                //       fontSize: 11,
                                //       color: provider.isConnected
                                //           ? AppTheme.successGreen
                                //           : AppTheme.textSecondary,
                                //       fontWeight: FontWeight.w500,
                                //     ),
                                //   ),
                                // ),

                                // 名称与类型（靠上，避免遮挡中心按钮）
                                if (provider.currentConfig != null)
                                  Positioned(
                                    left: 12,
                                    right: 12,
                                    top: 36,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                provider.currentConfig!.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                            ),
                                            // 延时显示
                                            Builder(
                                              builder: (context) {
                                                // 构建延时显示组件
                                                return _buildCurrentConfigPing(
                                                  provider,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _getConfigTypeDisplay(
                                            provider.currentConfig!,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  const Positioned(
                                    left: 12,
                                    top: 40,
                                    child: Text(
                                      '暂无配置',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),

                                // 中央连接/断开按钮（水平+垂直居中）
                                Align(
                                  alignment: Alignment.center,
                                  child: AnimatedConnectionButton(
                                    isConnected: provider.isConnected,
                                    isConnecting: provider.isConnecting,
                                    isDisconnecting: provider.isDisconnecting,
                                    size: 80,
                                    onTap: () async {
                                      if (provider.isConnected) {
                                        provider.disconnect();
                                      } else {
                                        if (provider.currentConfig != null) {
                                          provider.connect(
                                            provider.currentConfig!,
                                          );
                                        } else if (provider
                                            .configs
                                            .isNotEmpty) {
                                          await provider.setCurrentConfig(
                                            provider.configs.first,
                                          );
                                          provider.connect(
                                            provider.configs.first,
                                          );
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('请先添加服务器配置'),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),
                        // 连接时长与流量统计（始终显示；未连接时显示 0）
                        Row(
                          children: [
                            Expanded(
                              child: HoverScale(
                                scale: 1.05,
                                child: GestureDetector(
                                  onTap: () =>
                                      _showConnectionStatusPage(context),
                                  child: _buildMiniStatCard(
                                    icon: Icons.timer,
                                    label: '连接时长',
                                    value:
                                        ImprovedTrafficStatsService.formatDuration(
                                          provider.connectionDuration,
                                        ),
                                    rightValue: '${provider.activeConnections}',
                                    rightLabel: '连接数',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildMiniTrafficCard(
                                icon: Icons.arrow_upward,
                                label: '上传',
                                value: ImprovedTrafficStatsService.formatSpeed(
                                  provider.uploadSpeed,
                                ),
                                sub: ImprovedTrafficStatsService.formatBytes(
                                  provider.uploadBytes,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildMiniTrafficCard(
                                icon: Icons.arrow_downward,
                                label: '下载',
                                value: ImprovedTrafficStatsService.formatSpeed(
                                  provider.downloadSpeed,
                                ),
                                sub: ImprovedTrafficStatsService.formatBytes(
                                  provider.downloadBytes,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // 代理模式按钮（三个卡片）
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    provider.setProxyMode(ProxyMode.rule),
                                child: _buildModeButton(
                                  '智能',
                                  provider.proxyMode == ProxyMode.rule,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    provider.setProxyMode(ProxyMode.global),
                                child: _buildModeButton(
                                  '全局',
                                  provider.proxyMode == ProxyMode.global,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    provider.setProxyMode(ProxyMode.custom),
                                child: _buildModeButton(
                                  '自定义',
                                  provider.proxyMode == ProxyMode.custom,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // 节点配置 & DNS
                        Row(
                          children: [
                            Expanded(
                              child: HoverScale(
                                child: GestureDetector(
                                  onTap: () =>
                                      _showConfigManagementPage(context),
                                  child: _buildFeatureButton(
                                    '节点配置',
                                    Icons.list_alt,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: HoverScale(
                                child: GestureDetector(
                                  onTap: () => _showDnsSettingsPage(context),
                                  child: _buildDnsCard(),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // 日志 & 分流规则
                        Row(
                          children: [
                            Expanded(
                              child: HoverScale(
                                child: GestureDetector(
                                  onTap: () => _showLogsPage(context, provider),
                                  child: _buildLogsCard(context, provider),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: HoverScale(
                                child: GestureDetector(
                                  onTap: () => _showRoutingRulesPage(context),
                                  child: Container(
                                    height: 80,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppTheme.bgCard,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppTheme.borderColor.withAlpha(
                                          80,
                                        ),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.06),
                                          offset: const Offset(0, 2),
                                          blurRadius: 6,
                                          spreadRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.route,
                                          color: AppTheme.primaryNeon,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: const [
                                              Text(
                                                '分流',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                '路由规则',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppTheme.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right,
                                          color: AppTheme.textSecondary,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // TUN / 守护进程 卡片（这里用 TUN 模式卡片）
                        _buildDaemonCard(context, provider),

                        const SizedBox(height: 12),

                        // 系统代理开关
                        _buildSystemProxyToggle(provider),

                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // 配置类型展示
  String _getConfigTypeDisplay(VPNConfig config) {
    final type = config.type.toUpperCase();
    // 简化展示：直接返回协议名，必要时可拼接子信息
    return type;
  }

  // 简洁统计卡片（仅主值）
  Widget _buildMiniStatCard({
    required IconData icon,
    required String label,
    required String value,
    String? rightValue,
    String? rightLabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (rightValue != null && rightLabel != null) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  rightValue,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryNeon,
                  ),
                ),
                Text(
                  rightLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textHint,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // 简洁流量卡片（主值 + 次值：累计字节）
  Widget _buildMiniTrafficCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 199, 230, 22),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color.fromARGB(255, 54, 98, 231),
                      ),
                    ),
                  ],
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 构建模式按钮
  Widget _buildModeButton(String title, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color.fromARGB(255, 75, 140, 57).withAlpha(30)
            : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? const Color.fromARGB(255, 101, 165, 55)
              : AppTheme.borderColor.withAlpha(100),
        ),
      ),
      child: Center(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppTheme.primaryNeon : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  // 构建功能按钮
  Widget _buildFeatureButton(String title, IconData icon) {
    return Container(
      height: 80, // 统一高度与DNS卡片一致
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryNeon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title == '节点配置' ? '服务器管理' : '功能设置',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 16),
        ],
      ),
    );
  }

  // 构建 DNS 卡片
  Widget _buildDnsCard() {
    return Container(
      height: 80, // 统一高度
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.dns, color: AppTheme.primaryNeon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'DNS',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '智能解析',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 18),
        ],
      ),
    );
  }

  // 构建日志卡片
  Widget _buildLogsCard(BuildContext context, VPNProviderV2 provider) {
    return Container(
      height: 80, // 统一高度
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.article_outlined, color: AppTheme.primaryNeon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      '日志',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNeon.withAlpha(50),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${provider.logs.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.primaryNeon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  provider.logs.isNotEmpty
                      ? provider.logs.last.length > 25
                            ? '${provider.logs.last.substring(0, 25)}...'
                            : provider.logs.last
                      : '暂无日志',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 18),
        ],
      ),
    );
  }

  // 构建TUN模式卡片
  Widget _buildDaemonCard(BuildContext context, VPNProviderV2 provider) {
    return Container(
      height: 80, // 统一高度
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: provider.useTun ? AppTheme.accentNeon : AppTheme.primaryNeon,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      'TUN模式',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accentNeon.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '全局',
                        style: TextStyle(
                          fontSize: 8,
                          color: AppTheme.accentNeon,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _getTunDescription(provider),
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: provider.useTun,
            onChanged: (v) async {
              await _handleTunToggle(context, provider, v);
            },
            thumbColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => states.contains(WidgetState.selected)
                  ? AppTheme.accentNeon
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  // 系统代理开关
  Widget _buildSystemProxyToggle(VPNProviderV2 provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.settings_ethernet,
            color: provider.autoSystemProxy
                ? AppTheme.primaryNeon
                : AppTheme.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      '系统代理',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 实时状态指示器
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getProxyStatusColor(provider).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getProxyStatusColor(provider),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _getProxyStatusText(provider),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _getProxyStatusColor(provider),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _getProxyDescription(provider),
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: provider.autoSystemProxy,
            onChanged: provider.useTun
                ? null
                : (v) => provider.setAutoSystemProxy(v),
            thumbColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => states.contains(WidgetState.selected)
                  ? AppTheme.primaryNeon
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  // 显示添加服务器页面

  // 显示连接状态页面
  // 显示连接状态页面
  void _showConnectionStatusPage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ConnectionStatusPage(),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.ease;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  // 显示分流规则页面
  void _showRoutingRulesPage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const RoutingRulesPage(),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.ease;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  // 显示DNS设置页面
  void _showDnsSettingsPage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const DnsSettingsPage(),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.ease;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  // 显示配置管理页面
  void _showConfigManagementPage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ConfigManagementPage(),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.ease;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  // 显示日志页面
  void _showLogsPage(BuildContext context, VPNProviderV2 provider) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            LogsPage(provider: provider),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.ease;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  /// 构建当前配置的延时显示
  Widget _buildCurrentConfigPing(VPNProviderV2 provider) {
    if (provider.currentConfig == null) {
      return const SizedBox.shrink();
    }

    final config = provider.currentConfig!;
    final ping = provider.getConfigPing(config.id);
    final pingLevel = provider.getConfigPingLevel(config.id);
    final pingText = provider.getConfigPingText(config.id);

    Color pingColor;
    IconData pingIcon;
    String displayText = pingText;

    if (!provider.isConnected && ping == -1) {
      // 未连接且没有延时数据时，显示测试状态
      pingColor = AppTheme.textSecondary;
      pingIcon = Icons.pending;
    } else if (ping > 0) {
      // 有延时数据时，无论是否连接都显示延时
      // 有延时数据，准备显示
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
        default:
          pingColor = AppTheme.textSecondary;
          pingIcon = Icons.speed;
          break;
      }
      displayText = pingText;
      // 显示状态: $displayText
    } else {
      // ping == -1 且已经测试过，显示失败状态
      // 延时测试失败分支
      if (provider.isConnected) {
        pingColor = AppTheme.textSecondary;
        pingIcon = Icons.close;
        displayText = "超时";
        // 显示状态: 超时（已连接）
      } else {
        // 未连接时测试失败
        pingColor = AppTheme.errorRed;
        pingIcon = Icons.error_outline;
        displayText = "连接失败";
        // 显示状态: 连接失败（未连接）
      }
    }

    final containerWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: pingColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pingIcon, size: 25, color: pingColor),
          const SizedBox(width: 3),
          Text(
            displayText,
            style: TextStyle(
              //右侧延迟显示文字的字体
              fontSize: 25,
              color: pingColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    // Container组件已创建
    return containerWidget;
  }

  // 获取系统代理状态颜色
  Color _getProxyStatusColor(VPNProviderV2 provider) {
    if (!provider.isSystemProxySupported) {
      return Colors.grey;
    }

    if (provider.useTun) {
      return Colors.orange; // TUN模式时显示橙色
    }

    if (provider.isSystemProxyEnabled) {
      return Colors.green; // 系统代理已启用显示绿色
    } else {
      return Colors.red; // 系统代理未启用显示红色
    }
  }

  // 获取系统代理状态文本
  String _getProxyStatusText(VPNProviderV2 provider) {
    if (!provider.isSystemProxySupported) {
      return '不支持';
    }

    if (provider.useTun) {
      return 'TUN接管';
    }

    if (provider.isSystemProxyEnabled) {
      return '已启用';
    } else {
      return '未启用';
    }
  }

  // 获取系统代理描述文本
  String _getProxyDescription(VPNProviderV2 provider) {
    if (!provider.isSystemProxySupported) {
      return '当前系统不支持自动代理配置';
    }

    if (provider.useTun) {
      return 'TUN模式已接管系统流量，系统代理已自动关闭';
    }

    if (provider.autoSystemProxy) {
      if (provider.isSystemProxyEnabled) {
        final server = provider.systemProxyServer;
        return server.isNotEmpty ? '已自动配置: $server' : '已自动配置系统网络代理';
      } else {
        return '已启用自动配置，但系统代理当前未生效';
      }
    } else {
      return provider.isSystemProxyEnabled ? '系统代理已手动配置' : '需手动配置网络代理';
    }
  }

  // 获取TUN模式描述文本
  String _getTunDescription(VPNProviderV2 provider) {
    if (provider.useTun) {
      if (provider.autoSystemProxy) {
        return '全局接管系统流量，已自动关闭系统代理';
      } else {
        return '全局接管系统流量';
      }
    } else {
      final tunStatus = provider.tunAvailability;
      if (tunStatus.needsElevation) {
        return '需要管理员权限启用 TUN 模式';
      } else if (provider.autoSystemProxy && provider.isSystemProxySupported) {
        return '仅代理模式，系统代理将自动配置';
      } else {
        return '仅代理模式';
      }
    }
  }

  /// 处理 TUN 模式开关
  Future<void> _handleTunToggle(
    BuildContext context,
    VPNProviderV2 provider,
    bool enabled,
  ) async {
    if (!enabled) {
      // 关闭 TUN 模式，无需权限检查
      await provider.setUseTun(false);
      return;
    }

    // 启用 TUN 模式，检查权限
    final tunStatus = provider.tunAvailability;

    switch (tunStatus) {
      case TunAvailability.available:
        // 直接启用
        await provider.setUseTun(true);
        break;

      case TunAvailability.needElevation:
        // 需要管理员权限，提示用户重启应用
        _showError(
          context,
          '需要管理员权限',
          'TUN 模式需要管理员权限才能运行。\n'
              '请关闭应用后，右键选择"以管理员身份运行"重新启动。',
        );
        break;

      case TunAvailability.missingWintun:
        // 缺少 wintun.dll
        _showError(context, '缺少 wintun.dll', '请重新编译应用或确保 wintun.dll 存在于应用目录中');
        break;

      case TunAvailability.notSupported:
        // 平台不支持
        _showError(context, '平台不支持', '当前平台不支持 TUN 模式');
        break;
    }
  }

  /// 显示错误对话框
  void _showError(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        title: Row(
          children: [
            const Icon(Icons.error, color: Color(0xFFFF6B6B), size: 24),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '确定',
              style: TextStyle(
                color: Color(0xFFFF6B6B),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
