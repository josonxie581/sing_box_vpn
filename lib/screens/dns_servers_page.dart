import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gsou/utils/safe_navigator.dart';
import '../theme/app_theme.dart';
import '../services/dns_manager.dart';
import '../providers/vpn_provider_v2.dart';

/// DNS服务器配置页面
class DnsServersPage extends StatefulWidget {
  const DnsServersPage({super.key});

  @override
  State<DnsServersPage> createState() => _DnsServersPageState();
}

class _DnsServersPageState extends State<DnsServersPage> {
  final DnsManager _dnsManager = DnsManager();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _dnsManager.init();
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final servers = _dnsManager.dnsServers;

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
          '服务器',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.textPrimary),
            onPressed: () => _showEditDialog(),
            tooltip: '添加DNS服务器',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryNeon),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: servers.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildPresetsCard();
                }
                final server = servers[index - 1];
                return _buildServerItem(server, index - 1);
              },
            ),
    );
  }

  Widget _buildPresetsCard() {
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
          const Text(
            '境外DNS预设',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '一键添加常用境外DNS（默认走 Proxy）',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip('Cloudflare DoH', () {
                _addPresets([
                  const DnsServer(
                    name: 'Cloudflare DoH',
                    address: 'cloudflare-dns.com',
                    type: DnsServerType.doh,
                    detour: 'proxy',
                    enabled: true,
                  ),
                ]);
              }),
              _buildPresetChip('Google DoH', () {
                _addPresets([
                  const DnsServer(
                    name: 'Google DoH',
                    address: 'dns.google',
                    type: DnsServerType.doh,
                    detour: 'proxy',
                    enabled: true,
                  ),
                ]);
              }),
              _buildPresetChip('Quad9 DoH', () {
                _addPresets([
                  const DnsServer(
                    name: 'Quad9 DoH',
                    address: 'dns.quad9.net',
                    type: DnsServerType.doh,
                    detour: 'proxy',
                    enabled: true,
                  ),
                ]);
              }),
              _buildPresetChip('All 3', () {
                _addPresets([
                  const DnsServer(
                    name: 'Cloudflare DoH',
                    address: 'cloudflare-dns.com',
                    type: DnsServerType.doh,
                    detour: 'proxy',
                    enabled: true,
                  ),
                  const DnsServer(
                    name: 'Google DoH',
                    address: 'dns.google',
                    type: DnsServerType.doh,
                    detour: 'proxy',
                    enabled: true,
                  ),
                  const DnsServer(
                    name: 'Quad9 DoH',
                    address: 'dns.quad9.net',
                    type: DnsServerType.doh,
                    detour: 'proxy',
                    enabled: true,
                  ),
                ]);
              }),
              _buildPresetChip('Cloudflare DoT', () {
                _addPresets([
                  const DnsServer(
                    name: 'Cloudflare DoT',
                    address: '1.1.1.1',
                    type: DnsServerType.dot,
                    detour: 'proxy',
                    enabled: true,
                  ),
                ]);
              }),
              _buildPresetChip('Google DoT', () {
                _addPresets([
                  const DnsServer(
                    name: 'Google DoT',
                    address: 'dns.google',
                    type: DnsServerType.dot,
                    detour: 'proxy',
                    enabled: true,
                  ),
                ]);
              }),
              _buildPresetChip('DoT x2', () {
                _addPresets([
                  const DnsServer(
                    name: 'Cloudflare DoT',
                    address: '1.1.1.1',
                    type: DnsServerType.dot,
                    detour: 'proxy',
                    enabled: true,
                  ),
                  const DnsServer(
                    name: 'Google DoT',
                    address: 'dns.google',
                    type: DnsServerType.dot,
                    detour: 'proxy',
                    enabled: true,
                  ),
                ]);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: AppTheme.bgDark,
      side: BorderSide(color: AppTheme.borderColor.withAlpha(100)),
      onPressed: onTap,
    );
  }

  void _addPresets(List<DnsServer> servers) {
    int added = 0;
    for (final server in servers) {
      final exists = _dnsManager.dnsServers.any(
        (s) =>
            s.name == server.name &&
            s.address == server.address &&
            s.type == server.type &&
            s.detour == server.detour,
      );
      if (!exists) {
        _dnsManager.addDnsServer(server);
        added++;
      }
    }

    context.read<VPNProviderV2>().onDnsSettingsChanged();
    setState(() {});

    final msg = added > 0 ? '已添加 $added 个DNS服务器' : '预设已存在';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: added > 0
            ? AppTheme.successGreen
            : AppTheme.textSecondary,
      ),
    );
  }

  Widget _buildServerItem(DnsServer server, int index) {
    final typeLabel = server.type.name.toUpperCase();
    final detourLabel = server.detour.toLowerCase() == 'proxy'
        ? 'Proxy'
        : 'Direct';

    return GestureDetector(
      onTap: () => _showEditDialog(server: server, index: index),
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
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.primaryNeon.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.dns_outlined,
                size: 16,
                color: AppTheme.primaryNeon,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    server.address,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildChip(typeLabel),
                      const SizedBox(width: 6),
                      _buildChip(detourLabel),
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: server.enabled,
              onChanged: (value) {
                _dnsManager.updateDnsServer(
                  index,
                  server.copyWith(enabled: value),
                );
                context.read<VPNProviderV2>().onDnsSettingsChanged();
                setState(() {});
              },
              thumbColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.selected)
                    ? AppTheme.primaryNeon
                    : null,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed),
              onPressed: () => _confirmDelete(index, server.name),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryNeon.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primaryNeon.withAlpha(60)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.primaryNeon,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(int index, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '删除DNS服务器',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要删除 "$name" 吗？',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(context, result: false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => safePop(context, result: true),
            child: const Text('删除', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );

    if (ok == true) {
      _dnsManager.removeDnsServer(index);
      context.read<VPNProviderV2>().onDnsSettingsChanged();
      setState(() {});
    }
  }

  Future<void> _showEditDialog({DnsServer? server, int? index}) async {
    final isEdit = server != null && index != null;
    final nameCtrl = TextEditingController(text: server?.name ?? '');
    final addrCtrl = TextEditingController(text: server?.address ?? '');
    var type = server?.type ?? DnsServerType.udp;
    var detour = server?.detour ?? 'direct';
    var enabled = server?.enabled ?? true;

    String hintForType(DnsServerType t) {
      switch (t) {
        case DnsServerType.udp:
        case DnsServerType.tcp:
          return '示例: 1.1.1.1 或 1.1.1.1:53';
        case DnsServerType.doh:
          return '示例: cloudflare-dns.com 或 https://cloudflare-dns.com/dns-query';
        case DnsServerType.dot:
          return '示例: 1.1.1.1 或 tls://1.1.1.1';
        case DnsServerType.doq:
          return '示例: dns.google 或 quic://dns.google';
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(
            isEdit ? '编辑DNS服务器' : '添加DNS服务器',
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
          content: StatefulBuilder(
            builder: (context, setInner) {
              return SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: addrCtrl,
                      decoration: InputDecoration(
                        labelText: '地址',
                        hintText: hintForType(type),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          '类型',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<DnsServerType>(
                          value: type,
                          dropdownColor: AppTheme.bgCard,
                          items: DnsServerType.values
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.name.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setInner(() => type = v);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          '通道',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: detour,
                          dropdownColor: AppTheme.bgCard,
                          items: const [
                            DropdownMenuItem(
                              value: 'direct',
                              child: Text('Direct'),
                            ),
                            DropdownMenuItem(
                              value: 'proxy',
                              child: Text('Proxy'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setInner(() => detour = v);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          '启用',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        const Spacer(),
                        Switch(
                          value: enabled,
                          onChanged: (v) => setInner(() => enabled = v),
                          thumbColor: WidgetStateProperty.resolveWith<Color?>(
                            (states) => states.contains(WidgetState.selected)
                                ? AppTheme.primaryNeon
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
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
                final name = nameCtrl.text.trim();
                var addr = addrCtrl.text.trim();
                if (name.isEmpty || addr.isEmpty) {
                  return;
                }

                addr = _normalizeAddress(addr, type);
                final newServer = DnsServer(
                  name: name,
                  address: addr,
                  type: type,
                  detour: detour,
                  enabled: enabled,
                );

                if (isEdit) {
                  _dnsManager.updateDnsServer(index!, newServer);
                } else {
                  _dnsManager.addDnsServer(newServer);
                }

                context.read<VPNProviderV2>().onDnsSettingsChanged();
                setState(() {});
                safePop(context);
              },
              child: const Text(
                '保存',
                style: TextStyle(color: AppTheme.primaryNeon),
              ),
            ),
          ],
        );
      },
    );
  }

  String _normalizeAddress(String raw, DnsServerType type) {
    var value = raw.trim();
    if (value.isEmpty) return value;

    if (value.startsWith('http://') || value.startsWith('https://')) {
      try {
        final uri = Uri.parse(value);
        if (uri.host.isNotEmpty) {
          value = uri.host;
        } else {
          value = value.replaceFirst(RegExp(r'^https?://'), '');
        }
      } catch (_) {}
    }

    value = value.replaceFirst(RegExp(r'^(udp|tcp|tls|quic)://'), '');

    if (type == DnsServerType.doh && value.contains('/')) {
      value = value.split('/').first;
    }

    if (type == DnsServerType.doh && value.endsWith('/dns-query')) {
      value = value.substring(0, value.length - '/dns-query'.length);
    }

    return value;
  }
}
