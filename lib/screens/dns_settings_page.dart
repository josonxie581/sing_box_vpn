import 'package:flutter/material.dart';
import '../utils/navigation.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider_v2.dart';
import '../theme/app_theme.dart';
import '../services/dns_manager.dart';
import 'dns_servers_page.dart';
import 'static_ip_mapping_page.dart';
import 'dns_test_page.dart';
// 规则集管理功能已迁移至分流规则配置页面

/// DNS 设置页面
class DnsSettingsPage extends StatefulWidget {
  const DnsSettingsPage({super.key});

  @override
  State<DnsSettingsPage> createState() => _DnsSettingsPageState();
}

class _DnsSettingsPageState extends State<DnsSettingsPage> {
  final DnsManager _dnsManager = DnsManager(); // 使用单例，确保与VPNProvider同步

  @override
  void initState() {
    super.initState();
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
        title: const Text(
          'DNS',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Consumer<VPNProviderV2>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TUN HijackDNS
                _buildSwitchCard(
                  'TUN HijackDNS',
                  '拦截所有DNS请求并重定向到本地DNS服务器',
                  _dnsManager.tunHijackDns,
                  (value) {
                    setState(() => _dnsManager.tunHijackDns = value);
                    // 通知VPN提供者配置已更改
                    context.read<VPNProviderV2>().onDnsSettingsChanged();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 12),

                // 静态IP
                _buildStaticIpCard(),

                const SizedBox(height: 12),

                // 解析入站域名
                _buildSwitchCard(
                  '解析入站域名',
                  '自动解析入站连接的域名以提高路由准确性',
                  _dnsManager.resolveInboundDomains,
                  (value) {
                    setState(() => _dnsManager.resolveInboundDomains = value);
                    context.read<VPNProviderV2>().onDnsSettingsChanged();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 12),

                // 本地端口
                _buildLocalPortCard(),

                const SizedBox(height: 12),

                // 测试域名
                _buildTestDomainCard(),

                const SizedBox(height: 12),

                // TTL
                _buildTtlCard(),

                const SizedBox(height: 12),

                // 启用DNS分流规则
                _buildSwitchCard(
                  '启用DNS分流规则',
                  '根据域名规则分流DNS查询以优化解析速度',
                  _dnsManager.enableDnsRouting,
                  (value) {
                    setState(() => _dnsManager.enableDnsRouting = value);
                    context.read<VPNProviderV2>().onDnsSettingsChanged();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 12),

                // DNS严格路由
                _buildSwitchCard(
                  'DNS严格路由',
                  '确保DNS查询严格按照路由规则进行，提高安全性',
                  _dnsManager.strictRoute,
                  (value) {
                    setState(() => _dnsManager.strictRoute = value);
                    context
                        .read<VPNProviderV2>()
                        .syncStrictRouteFromDnsManager();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 12),

                // 直连流量启用ECS
                _buildSwitchCard(
                  '直连流量启用ECS',
                  '为直连流量启用EDNS客户端子网以获得更精确的CDN定位',
                  _dnsManager.enableEcs,
                  (value) {
                    setState(() => _dnsManager.enableEcs = value);
                    context.read<VPNProviderV2>().onDnsSettingsChanged();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 12),

                // 启用IPv6
                _buildSwitchCard(
                  '启用IPv6',
                  'VPS必须支持IPv6才能启用。若VPS无IPv6支持，请保持关闭',
                  _dnsManager.enableIpv6,
                  (value) {
                    setState(() => _dnsManager.enableIpv6 = value);
                    context.read<VPNProviderV2>().onDnsSettingsChanged();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 12),

                // Tailscale Endpoint
                _buildTailscaleEndpointCard(),

                const SizedBox(height: 12),

                // WireGuard Endpoint
                _buildWireGuardEndpointCard(),

                const SizedBox(height: 12),

                // 代理流量解析通道
                _buildProxyResolverCard(),

                const SizedBox(height: 12),

                // 服务器
                _buildServerCard(),

                const SizedBox(height: 12),

                // 规则集管理入口已迁移到“分流规则配置”页面
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建开关卡片
  Widget _buildSwitchCard(
    String title,
    String description,
    bool value,
    ValueChanged<bool> onChanged, {
    bool hasInfo = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
      ),
      child: Row(
        children: [
          if (hasInfo) ...[
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppTheme.primaryNeon.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.info_outline,
                size: 12,
                color: AppTheme.primaryNeon,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
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

  /// 构建静态IP卡片
  Widget _buildStaticIpCard() {
    final mappingCount = _dnsManager.staticIpMappings.length;
    final enabledCount = _dnsManager.staticIpMappings
        .where((m) => m.enabled)
        .length;

    return GestureDetector(
      onTap: () => _navigateToStaticIpMapping(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
        ),
        child: Row(
          children: [
            // 图标
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryNeon.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.dns_outlined,
                color: AppTheme.primaryNeon,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '静态IP映射',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mappingCount > 0
                        ? '已配置 $mappingCount 条规则，$enabledCount 条启用中'
                        : '域名到IP地址的静态映射配置',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            if (mappingCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNeon.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$enabledCount',
                  style: const TextStyle(
                    color: AppTheme.primaryNeon,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            const Icon(
              Icons.chevron_right,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建测试域名卡片
  Widget _buildTestDomainCard() {
    return Row(
      children: [
        // 测试域名设置
        Expanded(
          child: GestureDetector(
            onTap: () => _showTestDomainDialog(),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
              ),
              child: Row(
                children: [
                  // 图标
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNeon.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.settings_outlined,
                      color: AppTheme.primaryNeon,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '测试域名',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dnsManager.testDomain,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                            height: 1.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 4),
                  const Icon(
                    Icons.expand_more,
                    color: AppTheme.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        // DNS测试按钮
        GestureDetector(
          onTap: () => _navigateToDnsTest(),
          child: Container(
            width: 48,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primaryNeon,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.network_check, color: Colors.black, size: 20),
                SizedBox(height: 2),
                Text(
                  '测试',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建TTL卡片
  Widget _buildTtlCard() {
    // TTL值到中文标签的映射
    final ttlLabels = {
      '30s': '30秒',
      '1m': '1分钟',
      '5m': '5分钟',
      '10m': '10分钟',
      '30m': '30分钟',
      '1h': '1小时',
      '2h': '2小时',
      '6h': '6小时',
      '12h': '12小时',
      '24h': '24小时',
      '48h': '48小时',
      '72h': '72小时',
      '1 h': '1小时',  // 兼容旧格式
      '12 h': '12小时', // 兼容旧格式
    };

    final currentTtl = _dnsManager.ttl;
    final displayLabel = ttlLabels[currentTtl] ?? currentTtl;

    return GestureDetector(
      onTap: () => _showTtlDialog(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TTL',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'DNS缓存存活时间，控制DNS记录的缓存时长',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              displayLabel,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  /// 构建Tailscale Endpoint卡片
  Widget _buildTailscaleEndpointCard() {
    final provider = context.read<VPNProviderV2>();

    String advertiseRoutesPreview() {
      final list = _dnsManager.tsAdvertiseRoutes;
      if (list.isEmpty) return '未配置';
      return list.join(', ');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNeon.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.link_outlined,
                  color: AppTheme.primaryNeon,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Tailscale Endpoint',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: _dnsManager.tailscaleEnabled,
                onChanged: (v) {
                  setState(() => _dnsManager.tailscaleEnabled = v);
                  provider.onDnsSettingsChanged();
                },
                thumbColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) => states.contains(WidgetState.selected)
                      ? AppTheme.primaryNeon
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '接入 Tailscale 控制面，允许通过 Tailscale 网络解析/访问（需要 with_tailscale 构建标签）。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          if (_dnsManager.tailscaleEnabled) ...[
            if (_dnsManager.tsAuthKeyMissing)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warningOrange.withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.warningOrange.withAlpha(80),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.warningOrange,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '未设置 Auth Key：首次连接可能需要登录链接授权（见日志页右上角“链接”按钮）',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _kvRow(
              label: 'State 目录',
              value: _dnsManager.tsStateDirectory.isEmpty
                  ? 'tailscale (默认)'
                  : _dnsManager.tsStateDirectory,
              onTap: () async {
                await _editText(
                  title: 'State 目录',
                  initial: _dnsManager.tsStateDirectory,
                  hint: '例如 C:/Users/you/.tailscale',
                  onSave: (v) {
                    setState(() => _dnsManager.tsStateDirectory = v);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'Auth Key',
              value: _dnsManager.tsAuthKey.isEmpty ? '未设置' : '已设置（点击修改）',
              obscure: true,
              onTap: () async {
                await _editText(
                  title: 'Auth Key',
                  initial: _dnsManager.tsAuthKey,
                  hint: '可留空使用登录链接',
                  onSave: (v) {
                    setState(() => _dnsManager.tsAuthKey = v);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'Control URL',
              value: _dnsManager.tsControlUrl.isEmpty
                  ? '默认 https://controlplane.tailscale.com'
                  : _dnsManager.tsControlUrl,
              onTap: () async {
                await _editText(
                  title: 'Control URL',
                  initial: _dnsManager.tsControlUrl,
                  hint: '可留空使用默认',
                  onSave: (v) {
                    setState(() => _dnsManager.tsControlUrl = v);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _toggleRow(
              label: 'Ephemeral 临时节点',
              value: _dnsManager.tsEphemeral,
              onChanged: (v) {
                setState(() => _dnsManager.tsEphemeral = v);
                provider.onDnsSettingsChanged();
              },
            ),
            _kvRow(
              label: 'Hostname',
              value: _dnsManager.tsHostname.isEmpty
                  ? '系统主机名（默认）'
                  : _dnsManager.tsHostname,
              onTap: () async {
                await _editText(
                  title: 'Hostname',
                  initial: _dnsManager.tsHostname,
                  hint: '可留空使用系统主机名',
                  onSave: (v) {
                    setState(() => _dnsManager.tsHostname = v);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _toggleRow(
              label: '接受路由 (accept_routes)',
              value: _dnsManager.tsAcceptRoutes,
              onChanged: (v) {
                setState(() => _dnsManager.tsAcceptRoutes = v);
                provider.onDnsSettingsChanged();
              },
            ),
            _kvRow(
              label: 'Exit Node',
              value: _dnsManager.tsExitNode.isEmpty
                  ? '未设置'
                  : _dnsManager.tsExitNode,
              onTap: () async {
                await _editText(
                  title: 'Exit Node',
                  initial: _dnsManager.tsExitNode,
                  hint: '节点名或 IP，可留空',
                  onSave: (v) {
                    setState(() => _dnsManager.tsExitNode = v);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _toggleRow(
              label: 'Exit Node 允许访问局域网',
              value: _dnsManager.tsExitNodeAllowLanAccess,
              onChanged: (v) {
                setState(() => _dnsManager.tsExitNodeAllowLanAccess = v);
                provider.onDnsSettingsChanged();
              },
            ),
            _kvRow(
              label: 'Advertise Routes',
              value: advertiseRoutesPreview(),
              onTap: () async {
                await _editText(
                  title: 'Advertise Routes (CIDR，逗号分隔)',
                  initial: _dnsManager.tsAdvertiseRoutes.join(', '),
                  hint: '例如 192.168.1.0/24, 10.0.0.0/8',
                  onSave: (v) {
                    final items = v
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    setState(() => _dnsManager.tsAdvertiseRoutes = items);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _toggleRow(
              label: 'Advertise Exit Node',
              value: _dnsManager.tsAdvertiseExitNode,
              onChanged: (v) {
                setState(() => _dnsManager.tsAdvertiseExitNode = v);
                provider.onDnsSettingsChanged();
              },
            ),
            _kvRow(
              label: 'UDP 超时',
              value: _dnsManager.tsUdpTimeout,
              onTap: () async {
                await _editText(
                  title: 'UDP 超时(如 5m, 30s)',
                  initial: _dnsManager.tsUdpTimeout,
                  hint: 'sing-box 缺省 5m',
                  onSave: (v) {
                    setState(() => _dnsManager.tsUdpTimeout = v);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _kvRow({
    required String label,
    required String value,
    bool obscure = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 180,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                obscure ? '••••••••' : value,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.edit, size: 16, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
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

  Future<void> _editText({
    required String title,
    required String initial,
    required String hint,
    required ValueChanged<String> onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => safePop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                onSave(controller.text);
                safePop(context);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  // ===== Missing methods/cards re-implemented below =====

  Widget _buildLocalPortCard() {
    final provider = context.read<VPNProviderV2>();
    return GestureDetector(
      onTap: () async {
        await _editText(
          title: '本地端口',
          initial: _dnsManager.localPort.toString(),
          hint: '1024-65535',
          onSave: (v) {
            final port = int.tryParse(v.trim());
            if (port != null && port >= 1024 && port <= 65535) {
              setState(() => _dnsManager.localPort = port);
              provider.syncLocalPortFromDnsManager();
            }
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '本地端口',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '混合入站监听端口 (mixed)',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _dnsManager.localPort.toString(),
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _getProxyResolverLabel(String value) {
    switch (value) {
      case 'Auto':
        return '自动';
      case 'FakeIP':
        return '虚拟IP';
      case 'Remote':
        return '远程解析';
      default:
        return value;
    }
  }

  Widget _buildProxyResolverCard() {
    final provider = context.read<VPNProviderV2>();

    // 选项与描述映射
    final optionsMap = {
      'Auto': '自动选择最佳策略',
      'FakeIP': '使用虚拟IP（推荐）',
      'Remote': '使用远程解析',
    };

    return GestureDetector(
      onTap: () async {
        final selected = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            backgroundColor: AppTheme.bgDark,
            title: const Text(
              '代理流量解析通道',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            children: optionsMap.entries
                .map(
                  (entry) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          if (_dnsManager.proxyResolver == entry.key)
                            const Icon(
                              Icons.check_circle,
                              size: 20,
                              color: AppTheme.primaryNeon,
                            )
                          else
                            Icon(
                              Icons.radio_button_unchecked,
                              size: 20,
                              color: AppTheme.textSecondary.withAlpha(100),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: _dnsManager.proxyResolver == entry.key
                                        ? AppTheme.primaryNeon
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  entry.value,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
        if (selected != null) {
          setState(() => _dnsManager.proxyResolver = selected);
          provider.onDnsSettingsChanged();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '代理流量解析通道',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '选择代理侧的域名解析路径',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _getProxyResolverLabel(_dnsManager.proxyResolver),
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerCard() {
    return GestureDetector(
      onTap: () async => _navigateToDnsServers(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
        ),
        child: Row(
          children: const [
            Expanded(
              child: Text(
                'DNS 服务器',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  void _navigateToStaticIpMapping() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StaticIpMappingPage()));
  }

  void _navigateToDnsTest() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DnsTestPage()));
  }

  void _navigateToDnsServers() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DnsServersPage()));
  }

  Future<void> _showTestDomainDialog() async {
    final provider = context.read<VPNProviderV2>();
    await _editText(
      title: '测试域名',
      initial: _dnsManager.testDomain,
      hint: '例如 gstatic.com',
      onSave: (v) {
        setState(() => _dnsManager.testDomain = v.trim());
        provider.onDnsSettingsChanged();
      },
    );
  }

  Future<void> _showTtlDialog() async {
    final provider = context.read<VPNProviderV2>();

    // 预定义的TTL选项
    final ttlOptions = [
      {'value': '30s', 'label': '30秒'},
      {'value': '1m', 'label': '1分钟'},
      {'value': '5m', 'label': '5分钟'},
      {'value': '10m', 'label': '10分钟'},
      {'value': '30m', 'label': '30分钟'},
      {'value': '1h', 'label': '1小时'},
      {'value': '2h', 'label': '2小时'},
      {'value': '6h', 'label': '6小时'},
      {'value': '12h', 'label': '12小时'},
      {'value': '24h', 'label': '24小时'},
      {'value': '48h', 'label': '48小时'},
      {'value': '72h', 'label': '72小时'},
    ];

    String? selectedTtl = _dnsManager.ttl;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgDark,
          title: const Text(
            'TTL设置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DNS缓存存活时间，控制DNS记录的缓存时长',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: ttlOptions.map((option) {
                            final isSelected = selectedTtl == option['value'];
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  selectedTtl = option['value'] as String;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryNeon.withAlpha(30)
                                      : AppTheme.bgCard,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryNeon
                                        : AppTheme.borderColor.withAlpha(100),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option['label'] as String,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              color: isSelected
                                                  ? AppTheme.primaryNeon
                                                  : AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            option['value'] as String,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isSelected
                                                  ? AppTheme.primaryNeon.withAlpha(180)
                                                  : AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        size: 20,
                                        color: AppTheme.primaryNeon,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '取消',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                if (selectedTtl != null && selectedTtl != _dnsManager.ttl) {
                  this.setState(() => _dnsManager.ttl = selectedTtl!);
                  provider.onDnsSettingsChanged();
                }
                Navigator.of(context).pop();
              },
              child: Text(
                '确定',
                style: TextStyle(color: AppTheme.primaryNeon),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建 WireGuard Endpoint 卡片
  Widget _buildWireGuardEndpointCard() {
    final provider = context.read<VPNProviderV2>();

    String joinList(List<String> list) =>
        list.isEmpty ? '未配置' : list.join(', ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNeon.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.vpn_lock,
                  color: AppTheme.primaryNeon,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'WireGuard Endpoint',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: _dnsManager.wgEnabled,
                onChanged: (v) {
                  setState(() => _dnsManager.wgEnabled = v);
                  provider.onDnsSettingsChanged();
                },
                thumbColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) => states.contains(WidgetState.selected)
                      ? AppTheme.primaryNeon
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '通过 WireGuard Endpoint 为解析与路由注入 WireGuard 接入（需要 with_wireguard 构建标签）。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          if (_dnsManager.wgEnabled) ...[
            if (!_dnsManager.wgConfigComplete)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warningOrange.withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.warningOrange.withAlpha(80),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.warningOrange,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '配置不完整：需至少填写 私钥、Peer 的 address/port/public_key/allowed_ips，未填将跳过注入',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _toggleRow(
              label: '使用系统 WireGuard (system)',
              value: _dnsManager.wgSystem,
              onChanged: (v) {
                setState(() => _dnsManager.wgSystem = v);
                provider.onDnsSettingsChanged();
              },
            ),
            _kvRow(
              label: '接口名称 name',
              value: _dnsManager.wgName.isEmpty
                  ? '未设置（可选）'
                  : _dnsManager.wgName,
              onTap: () async {
                await _editText(
                  title: '接口名称 name',
                  initial: _dnsManager.wgName,
                  hint: '例如 wg0，可留空',
                  onSave: (v) {
                    setState(() => _dnsManager.wgName = v.trim());
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'MTU',
              value: _dnsManager.wgMtu.toString(),
              onTap: () async {
                await _editText(
                  title: 'MTU',
                  initial: _dnsManager.wgMtu.toString(),
                  hint: '默认 1408',
                  onSave: (v) {
                    final n = int.tryParse(v) ?? 1408;
                    setState(() => _dnsManager.wgMtu = n);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'Address 列表',
              value: joinList(_dnsManager.wgAddress),
              onTap: () async {
                await _editText(
                  title: 'Address 列表 (逗号分隔)',
                  initial: _dnsManager.wgAddress.join(', '),
                  hint: '例如 10.0.0.2/24, fd00::2/64',
                  onSave: (v) {
                    final list = v
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    setState(() => _dnsManager.wgAddress = list);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: '私钥 private_key',
              value: _dnsManager.wgPrivateKey.isEmpty ? '未设置' : '已设置（点击修改）',
              obscure: true,
              onTap: () async {
                await _editText(
                  title: '私钥 private_key',
                  initial: _dnsManager.wgPrivateKey,
                  hint: 'base64 私钥',
                  onSave: (v) {
                    setState(() => _dnsManager.wgPrivateKey = v.trim());
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: '监听端口 listen_port (可选)',
              value: _dnsManager.wgListenPort == 0
                  ? '未设置'
                  : _dnsManager.wgListenPort.toString(),
              onTap: () async {
                await _editText(
                  title: '监听端口 listen_port (可选)',
                  initial: _dnsManager.wgListenPort.toString(),
                  hint: '0 表示不设置',
                  onSave: (v) {
                    setState(
                      () => _dnsManager.wgListenPort = int.tryParse(v) ?? 0,
                    );
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            const Divider(height: 24),
            const Text(
              'Peer 配置',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            _kvRow(
              label: '服务器地址 address',
              value: _dnsManager.wgPeerAddress.isEmpty
                  ? '未设置'
                  : _dnsManager.wgPeerAddress,
              onTap: () async {
                await _editText(
                  title: '服务器地址 address',
                  initial: _dnsManager.wgPeerAddress,
                  hint: '域名或 IP',
                  onSave: (v) {
                    setState(() => _dnsManager.wgPeerAddress = v.trim());
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: '端口 port',
              value: _dnsManager.wgPeerPort == 0
                  ? '未设置'
                  : _dnsManager.wgPeerPort.toString(),
              onTap: () async {
                await _editText(
                  title: '端口 port',
                  initial: _dnsManager.wgPeerPort.toString(),
                  hint: '0 表示未设置',
                  onSave: (v) {
                    setState(
                      () => _dnsManager.wgPeerPort = int.tryParse(v) ?? 0,
                    );
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'public_key',
              value: _dnsManager.wgPeerPublicKey.isEmpty ? '未设置' : '已设置（点击修改）',
              onTap: () async {
                await _editText(
                  title: 'public_key',
                  initial: _dnsManager.wgPeerPublicKey,
                  hint: '对端公钥',
                  onSave: (v) {
                    setState(() => _dnsManager.wgPeerPublicKey = v.trim());
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'pre_shared_key (可选)',
              value: _dnsManager.wgPeerPreSharedKey.isEmpty
                  ? '未设置'
                  : '已设置（点击修改）',
              obscure: true,
              onTap: () async {
                await _editText(
                  title: 'pre_shared_key (可选)',
                  initial: _dnsManager.wgPeerPreSharedKey,
                  hint: 'PSK，可留空',
                  onSave: (v) {
                    setState(() => _dnsManager.wgPeerPreSharedKey = v.trim());
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'allowed_ips 列表',
              value: joinList(_dnsManager.wgPeerAllowedIps),
              onTap: () async {
                await _editText(
                  title: 'allowed_ips 列表 (逗号分隔)',
                  initial: _dnsManager.wgPeerAllowedIps.join(', '),
                  hint: '例如 0.0.0.0/0, ::/0',
                  onSave: (v) {
                    final list = v
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    setState(() => _dnsManager.wgPeerAllowedIps = list);
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'keepalive 秒 (可选)',
              value: _dnsManager.wgPeerKeepalive == 0
                  ? '未设置'
                  : _dnsManager.wgPeerKeepalive.toString(),
              onTap: () async {
                await _editText(
                  title: 'keepalive 秒 (可选)',
                  initial: _dnsManager.wgPeerKeepalive.toString(),
                  hint: '0 表示未设置',
                  onSave: (v) {
                    setState(
                      () => _dnsManager.wgPeerKeepalive = int.tryParse(v) ?? 0,
                    );
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'reserved 3字节 (逗号分隔, 0-255)',
              value: _dnsManager.wgPeerReserved.join(', '),
              onTap: () async {
                await _editText(
                  title: 'reserved 3字节 (逗号分隔, 0-255)',
                  initial: _dnsManager.wgPeerReserved.join(', '),
                  hint: '例如 0,0,0',
                  onSave: (v) {
                    final list = v
                        .split(',')
                        .map((e) => int.tryParse(e.trim()) ?? 0)
                        .toList();
                    while (list.length < 3) list.add(0);
                    setState(
                      () => _dnsManager.wgPeerReserved = list.take(3).toList(),
                    );
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'udp_timeout (可选)',
              value: _dnsManager.wgUdpTimeout.isEmpty
                  ? '默认 5m'
                  : _dnsManager.wgUdpTimeout,
              onTap: () async {
                await _editText(
                  title: 'udp_timeout (可选)',
                  initial: _dnsManager.wgUdpTimeout,
                  hint: '如 5m / 30s，留空使用默认',
                  onSave: (v) {
                    setState(() => _dnsManager.wgUdpTimeout = v.trim());
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
            _kvRow(
              label: 'workers (0=CPU 数)',
              value: _dnsManager.wgWorkers.toString(),
              onTap: () async {
                await _editText(
                  title: 'workers (0=CPU 数)',
                  initial: _dnsManager.wgWorkers.toString(),
                  hint: '0 表示自动',
                  onSave: (v) {
                    setState(
                      () => _dnsManager.wgWorkers = int.tryParse(v) ?? 0,
                    );
                    provider.onDnsSettingsChanged();
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
