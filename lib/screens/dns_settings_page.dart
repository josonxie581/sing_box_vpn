import 'package:flutter/material.dart';
import '../utils/navigation.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../theme/app_theme.dart';
import '../services/dns_manager.dart';
import 'dns_servers_page.dart';
import 'static_ip_mapping_page.dart';
import 'dns_test_page.dart';

/// DNS 设置页面
class DnsSettingsPage extends StatefulWidget {
  const DnsSettingsPage({super.key});

  @override
  State<DnsSettingsPage> createState() => _DnsSettingsPageState();
}

class _DnsSettingsPageState extends State<DnsSettingsPage> {
  final DnsManager _dnsManager = DnsManager(); // 使用单例，确保与VPNProvider同步

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
      body: Consumer<VPNProvider>(
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
                    context.read<VPNProvider>().notifyListeners();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 16),

                // 静态IP
                _buildStaticIpCard(),

                const SizedBox(height: 16),

                // 解析入站域名
                _buildSwitchCard(
                  '解析入站域名',
                  '自动解析入站连接的域名以提高路由准确性',
                  _dnsManager.resolveInboundDomains,
                  (value) {
                    setState(() => _dnsManager.resolveInboundDomains = value);
                    context.read<VPNProvider>().notifyListeners();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 16),

                // 本地端口
                _buildLocalPortCard(),

                const SizedBox(height: 16),

                // 测试域名
                _buildTestDomainCard(),

                const SizedBox(height: 16),

                // TTL
                _buildTtlCard(),

                const SizedBox(height: 16),

                // 启用DNS分流规则
                _buildSwitchCard(
                  '启用DNS分流规则',
                  '根据域名规则分流DNS查询以优化解析速度',
                  _dnsManager.enableDnsRouting,
                  (value) {
                    setState(() => _dnsManager.enableDnsRouting = value);
                    context.read<VPNProvider>().notifyListeners();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 16),

                // DNS严格路由
                _buildSwitchCard(
                  'DNS严格路由',
                  '确保DNS查询严格按照路由规则进行，提高安全性',
                  _dnsManager.strictRoute,
                  (value) {
                    setState(() => _dnsManager.strictRoute = value);
                    context.read<VPNProvider>().syncStrictRouteFromDnsManager();
                  },
                  hasInfo: true,
                ),

                // 直连流量启用ECS
                _buildSwitchCard(
                  '直连流量启用ECS',
                  '为直连流量启用EDNS客户端子网以获得更精确的CDN定位',
                  _dnsManager.enableEcs,
                  (value) {
                    setState(() => _dnsManager.enableEcs = value);
                    context.read<VPNProvider>().notifyListeners();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 16),

                // 启用IPv6
                _buildSwitchCard(
                  '启用IPv6',
                  'VPS必须支持IPv6才能启用。若VPS无IPv6支持，请保持关闭',
                  _dnsManager.enableIpv6,
                  (value) {
                    setState(() => _dnsManager.enableIpv6 = value);
                    context.read<VPNProvider>().notifyListeners();
                  },
                  hasInfo: true,
                ),

                const SizedBox(height: 16),

                // 代理流量解析通道
                _buildProxyResolverCard(),

                const SizedBox(height: 16),

                // 服务器
                _buildServerCard(),
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
              _dnsManager.ttl,
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

  /// 构建代理流量解析通道卡片
  Widget _buildProxyResolverCard() {
    return GestureDetector(
      onTap: () => _showProxyResolverDialog(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
        ),
        child: Row(
          children: [
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '代理流量解析通道',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'FakeIP可减少DNS泄漏，Remote使用真实IP',
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
              _dnsManager.proxyResolver,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.expand_more, color: AppTheme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  /// 构建服务器卡片
  Widget _buildServerCard() {
    return GestureDetector(
      onTap: () => _showServerDialog(),
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
                    '服务器',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '管理DNS服务器列表，配置上游DNS解析器',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  /// 导航到静态IP映射页面
  void _navigateToStaticIpMapping() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StaticIpMappingPage()),
    ).then((_) {
      // 页面返回后刷新状态
      setState(() {});
    });
  }

  /// 导航到DNS测试页面
  void _navigateToDnsTest() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DnsTestPage()),
    );
  }

  /// 显示测试域名对话框
  void _showTestDomainDialog() {
    final controller = TextEditingController(text: _dnsManager.testDomain);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '测试域名',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: '输入测试域名',
            hintStyle: TextStyle(color: AppTheme.textSecondary),
          ),
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
              setState(() => _dnsManager.testDomain = controller.text);
              context.read<VPNProvider>().notifyListeners();
              safePop(context);
            },
            child: const Text(
              '确定',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示TTL对话框
  void _showTtlDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          'TTL设置',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTtlOption('1 min', '1m'),
            _buildTtlOption('5 min', '5m'),
            _buildTtlOption('1 h', '1h'),
            _buildTtlOption('12 h', '12h'),
            _buildTtlOption('24 h', '24h'),
          ],
        ),
      ),
    );
  }

  Widget _buildTtlOption(String display, String value) {
    return ListTile(
      title: Text(display, style: const TextStyle(color: AppTheme.textPrimary)),
      trailing: _dnsManager.ttl == display
          ? const Icon(Icons.check, color: AppTheme.primaryNeon)
          : null,
      onTap: () {
        setState(() => _dnsManager.ttl = display);
        context.read<VPNProvider>().notifyListeners();
        safePop(context);
      },
    );
  }

  /// 显示代理解析器对话框
  void _showProxyResolverDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '代理流量解析通道',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProxyResolverOption('Auto', 'auto'),
            _buildProxyResolverOption('FakeIP', 'fakeip'),
            _buildProxyResolverOption('Remote', 'remote'),
          ],
        ),
      ),
    );
  }

  Widget _buildProxyResolverOption(String display, String value) {
    return ListTile(
      title: Text(display, style: const TextStyle(color: AppTheme.textPrimary)),
      trailing: _dnsManager.proxyResolver == display
          ? const Icon(Icons.check, color: AppTheme.primaryNeon)
          : null,
      onTap: () {
        setState(() => _dnsManager.proxyResolver = display);
        context.read<VPNProvider>().notifyListeners();
        safePop(context);
      },
    );
  }

  /// 构建本地端口配置卡片
  Widget _buildLocalPortCard() {
    return GestureDetector(
      onTap: () => _showLocalPortDialog(),
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
                Icons.settings_ethernet_outlined,
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
                    '本地端口',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_dnsManager.localPort}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(
              Icons.expand_more,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// 显示本地端口设置对话框
  void _showLocalPortDialog() {
    final controller = TextEditingController(
      text: _dnsManager.localPort.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '本地端口设置',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '设置混合代理服务器的本地监听端口',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: '输入端口号 (1024-65535)',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryNeon),
                ),
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
          TextButton(
            onPressed: () {
              final port = int.tryParse(controller.text);
              if (port != null && port >= 1024 && port <= 65535) {
                setState(() => _dnsManager.localPort = port);
                context.read<VPNProvider>().syncLocalPortFromDnsManager();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('端口设置已保存，重新连接后生效'),
                    backgroundColor: AppTheme.primaryNeon,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入有效的端口号 (1024-65535)'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(
              '确定',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示服务器配置页面
  void _showServerDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DnsServersPage()),
    );
  }
}
