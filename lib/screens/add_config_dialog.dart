import 'package:flutter/material.dart';
import '../utils/navigation.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/vpn_provider_v2.dart';
import '../models/vpn_config.dart';

class AddConfigDialog extends StatefulWidget {
  final VPNConfig? initialConfig;
  final int? editIndex; // 对应 provider.configs 的索引

  const AddConfigDialog({super.key, this.initialConfig, this.editIndex});

  @override
  State<AddConfigDialog> createState() => _AddConfigDialogState();
}

class _AddConfigDialogState extends State<AddConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serverController = TextEditingController();
  final _portController = TextEditingController();
  final _passwordController = TextEditingController();
  final _sniController = TextEditingController();
  final _alpnController = TextEditingController();
  final _uuidController = TextEditingController();
  final _alterIdController = TextEditingController(text: '0');
  final _methodController = TextEditingController(text: 'aes-256-gcm');
  // VLESS
  final _vlessUuidController = TextEditingController();
  String _vlessNetwork = 'tcp';
  final _vlessWsPathController = TextEditingController(text: '/');
  final _vlessWsHostController = TextEditingController();
  final _vlessGrpcServiceNameController = TextEditingController();
  final _vlessHttpHostController = TextEditingController(); // 逗号分隔
  final _vlessHttpPathController = TextEditingController(text: '/');
  bool _vlessTlsEnabled = true;
  bool _vlessRealityEnabled = false;
  final _realityPublicKeyController = TextEditingController();
  final _realityShortIdController = TextEditingController();
  // uTLS 指纹、XTLS Flow 与加密（encryption）
  final _realityFingerprintController =
      TextEditingController(); // 存 fingerprint
  final _vlessFlowController = TextEditingController();
  final _vlessEncryptionController = TextEditingController(text: 'none');
  // VMess: 算法与传输
  String _vmessSecurity = 'auto';
  String _vmessNetwork = 'tcp';
  final _wsPathController = TextEditingController(text: '/');
  final _wsHostController = TextEditingController();
  final _grpcServiceNameController = TextEditingController();
  final _httpHostController = TextEditingController(); // 逗号分隔
  final _httpPathController = TextEditingController(text: '/');
  // TUIC
  final _tuicUuidController = TextEditingController();
  final _tuicPasswordController = TextEditingController();
  final _tuicAlpnController = TextEditingController();
  String _tuicUdpRelayMode = 'native';
  String _tuicCongestion = 'bbr';
  // WireGuard
  final _wgPrivateKeyController = TextEditingController();
  final _wgPeerPublicKeyController = TextEditingController();
  final _wgAddressController = TextEditingController(); // 逗号分隔
  final _wgDnsController = TextEditingController(); // 逗号分隔
  final _wgReservedController = TextEditingController();
  final _wgMtuController = TextEditingController();
  // Basic auth for SOCKS/HTTP
  final _usernameController = TextEditingController();
  // 移除导入功能
  bool _skipCertVerify = false;

  String _selectedType = 'shadowsocks';
  // 已无 Tab 切换

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;
    if (cfg != null) {
      // 基本
      _nameController.text = cfg.name;
      _selectedType = cfg.type;
      _serverController.text = cfg.server;
      _portController.text = cfg.port.toString();

      // 类型特定
      final s = cfg.settings;
      switch (cfg.type.toLowerCase()) {
        case 'shadowsocks':
          _methodController.text = (s['method'] ?? 'aes-256-gcm').toString();
          _passwordController.text = (s['password'] ?? '').toString();
          break;
        case 'shadowsocks-2022':
          _methodController.text = (s['method'] ?? '2022-blake3-aes-128-gcm')
              .toString();
          _passwordController.text = (s['password'] ?? '').toString();
          break;
        case 'socks':
        case 'http':
          _usernameController.text = (s['username'] ?? '').toString();
          _passwordController.text = (s['password'] ?? '').toString();
          _sniController.text = (s['sni'] ?? '').toString();
          _skipCertVerify = (s['tlsEnabled'] ?? false) == false ? true : false;
          break;
        case 'vless':
          _vlessUuidController.text = (s['uuid'] ?? '').toString();
          _vlessNetwork = (s['network'] ?? 'tcp').toString();
          _vlessTlsEnabled = (s['tlsEnabled'] ?? true) == true;
          _vlessRealityEnabled = (s['realityEnabled'] ?? false) == true;
          _sniController.text = (s['sni'] ?? '').toString();
          _realityPublicKeyController.text = (s['realityPublicKey'] ?? '')
              .toString();
          _realityShortIdController.text = (s['realityShortId'] ?? '')
              .toString();
          _realityFingerprintController.text = (s['fingerprint'] ?? '')
              .toString();
          _vlessFlowController.text = (s['flow'] ?? '').toString();
          _vlessEncryptionController.text = (s['encryption'] ?? 'none')
              .toString();
          _vlessWsPathController.text = (s['wsPath'] ?? '/').toString();
          final vwsHeaders = s['wsHeaders'];
          if (vwsHeaders is Map && vwsHeaders['Host'] != null) {
            _vlessWsHostController.text = vwsHeaders['Host'].toString();
          }
          _vlessGrpcServiceNameController.text = (s['grpcServiceName'] ?? '')
              .toString();
          final vhttpHost = s['httpHost'];
          if (vhttpHost is List) {
            _vlessHttpHostController.text = vhttpHost.join(',');
          }
          _vlessHttpPathController.text = (s['httpPath'] ?? '/').toString();
          break;
        case 'vmess':
          _uuidController.text = (s['uuid'] ?? '').toString();
          _alterIdController.text = (s['alterId'] ?? 0).toString();
          _vmessSecurity = (s['security'] ?? 'auto').toString();
          _vmessNetwork = (s['network'] ?? 'tcp').toString();
          _wsPathController.text = (s['wsPath'] ?? '/').toString();
          final wsHeaders = s['wsHeaders'];
          if (wsHeaders is Map && wsHeaders['Host'] != null) {
            _wsHostController.text = wsHeaders['Host'].toString();
          }
          _grpcServiceNameController.text = (s['grpcServiceName'] ?? '')
              .toString();
          final httpHost = s['httpHost'];
          if (httpHost is List) {
            _httpHostController.text = httpHost.join(',');
          }
          _httpPathController.text = (s['httpPath'] ?? '/').toString();
          break;
        case 'trojan':
        case 'hysteria2':
          _passwordController.text = (s['password'] ?? '').toString();
          _sniController.text = (s['sni'] ?? '').toString();
          _skipCertVerify = (s['skipCertVerify'] ?? false) == true;
          final alpn = s['alpn'];
          if (alpn is List) {
            _alpnController.text = alpn.join(',');
          }
          break;
        case 'tuic':
          _tuicUuidController.text = (s['uuid'] ?? '').toString();
          _tuicPasswordController.text = (s['password'] ?? '').toString();
          final talpn = s['alpn'];
          if (talpn is List) _tuicAlpnController.text = talpn.join(',');
          _tuicUdpRelayMode = (s['udpRelayMode'] ?? 'native').toString();
          _tuicCongestion = (s['congestion'] ?? 'bbr').toString();
          _sniController.text = (s['sni'] ?? '').toString();
          _skipCertVerify = (s['skipCertVerify'] ?? false) == true;
          break;
        case 'wireguard':
          _wgPrivateKeyController.text = (s['privateKey'] ?? '').toString();
          _wgPeerPublicKeyController.text = (s['peerPublicKey'] ?? '')
              .toString();
          final addrs = s['localAddress'];
          if (addrs is List) _wgAddressController.text = addrs.join(',');
          final dns = s['dns'];
          if (dns is List) _wgDnsController.text = dns.join(',');
          _wgReservedController.text = (s['reserved'] ?? '').toString();
          _wgMtuController.text = (s['mtu'] ?? '').toString();
          break;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _sniController.dispose();
    _alpnController.dispose();
    _uuidController.dispose();
    _alterIdController.dispose();
    _methodController.dispose();
    _wsPathController.dispose();
    _wsHostController.dispose();
    _grpcServiceNameController.dispose();
    _httpHostController.dispose();
    _httpPathController.dispose();
    _vlessUuidController.dispose();
    _vlessWsPathController.dispose();
    _vlessWsHostController.dispose();
    _vlessGrpcServiceNameController.dispose();
    _vlessHttpHostController.dispose();
    _vlessHttpPathController.dispose();
    _realityPublicKeyController.dispose();
    _realityShortIdController.dispose();
    _realityFingerprintController.dispose();
    _vlessFlowController.dispose();
    _vlessEncryptionController.dispose();
    _tuicUuidController.dispose();
    _tuicPasswordController.dispose();
    _tuicAlpnController.dispose();
    _wgPrivateKeyController.dispose();
    _wgPeerPublicKeyController.dispose();
    _wgAddressController.dispose();
    _wgDnsController.dispose();
    _wgReservedController.dispose();
    _wgMtuController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogHeight = (MediaQuery.of(context).size.height * 0.7).clamp(
      420.0,
      720.0,
    );
    return AlertDialog(
      title: Text(widget.initialConfig == null ? '添加服务器' : '编辑服务器'),
      content: SizedBox(
        width: 500,
        child: SizedBox(
          height: dialogHeight.toDouble(),
          child: _buildManualForm(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saveManualConfig,
          child: Text(widget.initialConfig == null ? '保存' : '更新'),
        ),
      ],
    );
  }

  /// 构建手动配置表单
  Widget _buildManualForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 50),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 配置名称
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '配置名称',
                hintText: '例如: 香港节点',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入配置名称';
                }
                return null;
              },
            ),

            const SizedBox(height: 10),

            // 协议类型
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(labelText: '协议类型'),
              items: const [
                DropdownMenuItem(
                  value: 'shadowsocks',
                  child: Text('Shadowsocks'),
                ),
                DropdownMenuItem(
                  value: 'shadowsocks-2022',
                  child: Text('Shadowsocks-2022'),
                ),
                DropdownMenuItem(value: 'vmess', child: Text('VMess')),
                DropdownMenuItem(value: 'vless', child: Text('VLESS/REALITY')),
                DropdownMenuItem(value: 'trojan', child: Text('Trojan')),
                DropdownMenuItem(value: 'anytls', child: Text('AnyTLS')),
                DropdownMenuItem(value: 'shadowtls', child: Text('ShadowTLS')),
                DropdownMenuItem(value: 'hysteria', child: Text('Hysteria')),
                DropdownMenuItem(value: 'hysteria2', child: Text('Hysteria2')),
                DropdownMenuItem(value: 'tuic', child: Text('TUIC v5')),
                DropdownMenuItem(value: 'socks', child: Text('SOCKS5')),
                DropdownMenuItem(value: 'http', child: Text('HTTP')),
                DropdownMenuItem(value: 'wireguard', child: Text('WireGuard')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedType = value!;
                });
              },
            ),

            const SizedBox(height: 10),

            // SNI 与证书校验选项（适用于 trojan / hysteria2 / anytls / shadowtls / hysteria）
            if (_selectedType == 'trojan' ||
                _selectedType == 'hysteria2' ||
                _selectedType == 'anytls' ||
                _selectedType == 'shadowtls' ||
                _selectedType == 'hysteria') ...[
              TextFormField(
                controller: _sniController,
                decoration: InputDecoration(
                  labelText: 'SNI（可选）',
                  hintText: '例如：optimizationguide-pa.googleapis.com',
                  suffixIcon: IconButton(
                    tooltip: '粘贴',
                    icon: const Icon(Icons.content_paste),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      final text = data?.text?.trim();
                      if (text != null && text.isNotEmpty) {
                        setState(() => _sniController.text = text);
                      }
                    },
                  ),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                enabled: true,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _alpnController,
                decoration: InputDecoration(
                  labelText: 'ALPN（可选，逗号分隔）',
                  hintText: '例如：h3,h2,http/1.1',
                  suffixIcon: IconButton(
                    tooltip: '粘贴',
                    icon: const Icon(Icons.content_paste),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      final text = data?.text?.trim();
                      if (text != null && text.isNotEmpty) {
                        setState(() => _alpnController.text = text);
                      }
                    },
                  ),
                ),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                enabled: true,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('跳过证书验证（不安全，仅当自签证书/证书异常时开启）'),
                value: _skipCertVerify,
                onChanged: (v) => setState(() => _skipCertVerify = v ?? false),
              ),
              const SizedBox(height: 10),
            ],

            // 服务器地址
            TextFormField(
              controller: _serverController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: '例如: example.com 或 1.2.3.4',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入服务器地址';
                }
                return null;
              },
            ),

            const SizedBox(height: 10),

            // 端口
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '例如: 443',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入端口';
                }
                final port = int.tryParse(value);
                if (port == null || port < 1 || port > 65535) {
                  return '请输入有效的端口号 (1-65535)';
                }
                return null;
              },
            ),

            const SizedBox(height: 10),

            // 根据协议类型显示不同的字段
            ..._buildProtocolSpecificFields(),
          ],
        ),
      ),
    );
  }

  /// 构建协议特定字段
  List<Widget> _buildProtocolSpecificFields() {
    switch (_selectedType) {
      case 'shadowsocks':
        return [
          TextFormField(
            controller: _methodController,
            decoration: const InputDecoration(
              labelText: '加密方法',
              hintText: '例如: aes-256-gcm',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入加密方法';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: '密码'),
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              return null;
            },
          ),
        ];

      case 'vmess':
        return [
          // 基本
          TextFormField(
            controller: _uuidController,
            decoration: const InputDecoration(
              labelText: 'UUID',
              hintText: '例如: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入 UUID';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _alterIdController,
            decoration: const InputDecoration(
              labelText: 'Alter ID',
              hintText: '通常为 0',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          // 算法/加密
          DropdownButtonFormField<String>(
            value: _vmessSecurity,
            decoration: const InputDecoration(labelText: '算法/加密 (security)'),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('auto')),
              DropdownMenuItem(value: 'none', child: Text('none')),
              DropdownMenuItem(
                value: 'aes-128-gcm',
                child: Text('aes-128-gcm'),
              ),
              DropdownMenuItem(
                value: 'chacha20-poly1305',
                child: Text('chacha20-poly1305'),
              ),
            ],
            onChanged: (v) => setState(() => _vmessSecurity = v ?? 'auto'),
          ),
          const SizedBox(height: 16),
          // 传输方式
          DropdownButtonFormField<String>(
            value: _vmessNetwork,
            decoration: const InputDecoration(labelText: '传输方式 (network)'),
            items: const [
              DropdownMenuItem(value: 'tcp', child: Text('tcp')),
              DropdownMenuItem(value: 'ws', child: Text('ws')),
              DropdownMenuItem(value: 'grpc', child: Text('grpc')),
              DropdownMenuItem(value: 'http', child: Text('http')),
            ],
            onChanged: (v) => setState(() => _vmessNetwork = v ?? 'tcp'),
          ),
          const SizedBox(height: 8),
          if (_vmessNetwork == 'ws') ...[
            TextFormField(
              controller: _wsPathController,
              decoration: const InputDecoration(
                labelText: 'WebSocket 路径 (path)',
                hintText: '/',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _wsHostController,
              decoration: const InputDecoration(
                labelText: 'WebSocket Host 头 (可选)',
                hintText: '例如: example.com',
              ),
            ),
          ] else if (_vmessNetwork == 'grpc') ...[
            TextFormField(
              controller: _grpcServiceNameController,
              decoration: const InputDecoration(labelText: 'gRPC Service Name'),
            ),
          ] else if (_vmessNetwork == 'http') ...[
            TextFormField(
              controller: _httpHostController,
              decoration: const InputDecoration(
                labelText: 'HTTP Host 列表（逗号分隔，可选）',
                hintText: 'a.com,b.com',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _httpPathController,
              decoration: const InputDecoration(
                labelText: 'HTTP 路径 (path)',
                hintText: '/',
              ),
            ),
          ],
        ];

      case 'shadowsocks-2022':
        return [
          DropdownButtonFormField<String>(
            value: _methodController.text.isEmpty
                ? '2022-blake3-aes-128-gcm'
                : _methodController.text,
            decoration: const InputDecoration(labelText: '加密方法'),
            items: const [
              DropdownMenuItem(
                value: '2022-blake3-aes-128-gcm',
                child: Text('2022-blake3-aes-128-gcm'),
              ),
              DropdownMenuItem(
                value: '2022-blake3-aes-256-gcm',
                child: Text('2022-blake3-aes-256-gcm'),
              ),
              DropdownMenuItem(
                value: '2022-blake3-chacha20-poly1305',
                child: Text('2022-blake3-chacha20-poly1305'),
              ),
            ],
            onChanged: (v) => setState(
              () => _methodController.text = v ?? '2022-blake3-aes-128-gcm',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: '密码/PSK'),
            validator: (v) => (v == null || v.isEmpty) ? '请输入密码/PSK' : null,
          ),
        ];

      case 'vless':
        return [
          TextFormField(
            controller: _vlessUuidController,
            decoration: const InputDecoration(labelText: 'UUID (id)'),
            validator: (v) => (v == null || v.isEmpty) ? '请输入 UUID' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _vlessNetwork,
            decoration: const InputDecoration(labelText: '传输方式 (network)'),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('none')),
              DropdownMenuItem(value: 'tcp', child: Text('tcp')),
              DropdownMenuItem(value: 'ws', child: Text('ws')),
              DropdownMenuItem(value: 'grpc', child: Text('grpc')),
              DropdownMenuItem(value: 'http', child: Text('http')),
            ],
            onChanged: (v) => setState(() => _vlessNetwork = v ?? 'tcp'),
          ),
          const SizedBox(height: 8),
          if (_vlessNetwork == 'ws') ...[
            TextFormField(
              controller: _vlessWsPathController,
              decoration: const InputDecoration(
                labelText: 'WebSocket 路径 (path)',
                hintText: '/',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _vlessWsHostController,
              decoration: const InputDecoration(
                labelText: 'WebSocket Host（可选）',
              ),
            ),
          ] else if (_vlessNetwork == 'grpc') ...[
            TextFormField(
              controller: _vlessGrpcServiceNameController,
              decoration: const InputDecoration(labelText: 'gRPC Service Name'),
            ),
          ] else if (_vlessNetwork == 'http') ...[
            TextFormField(
              controller: _vlessHttpHostController,
              decoration: const InputDecoration(
                labelText: 'HTTP Host 列表（逗号分隔，可选）',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _vlessHttpPathController,
              decoration: const InputDecoration(
                labelText: 'HTTP 路径 (path)',
                hintText: '/',
              ),
            ),
          ],
          const SizedBox(height: 10),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('启用 TLS'),
            value: _vlessTlsEnabled,
            onChanged: (v) => setState(() => _vlessTlsEnabled = v),
          ),
          if (_vlessTlsEnabled) ...[
            TextFormField(
              controller: _sniController,
              decoration: const InputDecoration(labelText: 'SNI（可选）'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _alpnController,
              decoration: const InputDecoration(
                labelText: 'ALPN（可选，逗号分隔）',
                hintText: 'h3,h2',
              ),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('REALITY（实验性）'),
              value: _vlessRealityEnabled,
              onChanged: (v) =>
                  setState(() => _vlessRealityEnabled = v ?? false),
            ),
            if (_vlessRealityEnabled) ...[
              TextFormField(
                controller: _realityPublicKeyController,
                decoration: const InputDecoration(
                  labelText: 'Reality Public Key',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _realityShortIdController,
                decoration: const InputDecoration(
                  labelText: 'Reality Short ID（可选）',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _realityFingerprintController,
                decoration: const InputDecoration(
                  labelText: 'uTLS 指纹（可选，如 chrome）',
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              controller: _vlessFlowController,
              decoration: const InputDecoration(
                labelText: 'XTLS Flow（可选）',
                hintText: '如 xtls-rprx-vision',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _vlessEncryptionController,
              decoration: const InputDecoration(
                labelText: 'encryption（可选）',
                hintText: '默认 none',
              ),
            ),
          ],
        ];

      case 'tuic':
        return [
          TextFormField(
            controller: _tuicUuidController,
            decoration: const InputDecoration(labelText: 'UUID'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _tuicPasswordController,
            decoration: const InputDecoration(labelText: '密码（可选）'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _tuicAlpnController,
            decoration: const InputDecoration(labelText: 'ALPN（逗号分隔，可选）'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _tuicUdpRelayMode,
            decoration: const InputDecoration(labelText: 'UDP Relay Mode'),
            items: const [
              DropdownMenuItem(value: 'native', child: Text('native')),
              DropdownMenuItem(value: 'quic', child: Text('quic')),
            ],
            onChanged: (v) => setState(() => _tuicUdpRelayMode = v ?? 'native'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _tuicCongestion,
            decoration: const InputDecoration(labelText: '拥塞控制'),
            items: const [
              DropdownMenuItem(value: 'bbr', child: Text('bbr')),
              DropdownMenuItem(value: 'cubic', child: Text('cubic')),
            ],
            onChanged: (v) => setState(() => _tuicCongestion = v ?? 'bbr'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _sniController,
            decoration: const InputDecoration(labelText: 'SNI（可选）'),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('允许不安全（跳过证书验证）'),
            subtitle: const Text('不安全，仅用于测试'),
            value: _skipCertVerify,
            onChanged: (v) => setState(() => _skipCertVerify = v ?? false),
          ),
        ];

      case 'wireguard':
        return [
          TextFormField(
            controller: _wgPrivateKeyController,
            decoration: const InputDecoration(labelText: 'Private Key'),
            validator: (v) =>
                (v == null || v.isEmpty) ? '请输入 Private Key' : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _wgPeerPublicKeyController,
            decoration: const InputDecoration(labelText: 'Peer Public Key'),
            validator: (v) =>
                (v == null || v.isEmpty) ? '请输入 Peer Public Key' : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _wgAddressController,
            decoration: const InputDecoration(
              labelText: '本地地址 local_address（逗号分隔）',
              hintText: '10.0.0.2/32,fdfe:.../128',
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _wgDnsController,
            decoration: const InputDecoration(labelText: 'DNS（逗号分隔，可选）'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _wgReservedController,
            decoration: const InputDecoration(
              labelText: 'Reserved（可选）',
              hintText: '16进制或字节数组',
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _wgMtuController,
            decoration: const InputDecoration(labelText: 'MTU（可选）'),
            keyboardType: TextInputType.number,
          ),
        ];

      case 'socks':
      case 'http':
        return [
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: '用户名（可选）'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: '密码（可选）'),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('启用 TLS（可选）'),
            value: !_skipCertVerify,
            onChanged: (v) => setState(() => _skipCertVerify = !v),
          ),
          if (!_skipCertVerify) ...[
            TextFormField(
              controller: _sniController,
              decoration: const InputDecoration(labelText: 'SNI（可选）'),
            ),
          ],
        ];

      case 'trojan':
      case 'hysteria2':
      case 'anytls':
      case 'shadowtls':
      case 'hysteria':
        return [
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: '密码'),
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              return null;
            },
          ),
        ];

      default:
        return [];
    }
  }

  // 导入表单与逻辑已移除

  /// 保存手动配置
  void _saveManualConfig() {
    if (_formKey.currentState!.validate()) {
      final settings = <String, dynamic>{};

      switch (_selectedType) {
        case 'shadowsocks':
          settings['method'] = _methodController.text;
          settings['password'] = _passwordController.text;
          break;
        case 'shadowsocks-2022':
          settings['method'] = _methodController.text.isEmpty
              ? '2022-blake3-aes-128-gcm'
              : _methodController.text;
          settings['password'] = _passwordController.text;
          break;

        case 'vmess':
          settings['uuid'] = _uuidController.text;
          settings['alterId'] = int.parse(_alterIdController.text);
          settings['security'] = _vmessSecurity;
          settings['network'] = _vmessNetwork;
          if (_vmessNetwork == 'ws') {
            settings['wsPath'] = _wsPathController.text.isEmpty
                ? '/'
                : _wsPathController.text;
            if (_wsHostController.text.trim().isNotEmpty) {
              settings['wsHeaders'] = {'Host': _wsHostController.text.trim()};
            }
          } else if (_vmessNetwork == 'grpc') {
            settings['grpcServiceName'] = _grpcServiceNameController.text
                .trim();
          } else if (_vmessNetwork == 'http') {
            final hosts = _httpHostController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            if (hosts.isNotEmpty) settings['httpHost'] = hosts;
            settings['httpPath'] = _httpPathController.text.isEmpty
                ? '/'
                : _httpPathController.text;
          }
          break;
        case 'vless':
          settings['uuid'] = _vlessUuidController.text;
          settings['network'] = _vlessNetwork;
          settings['tlsEnabled'] = _vlessTlsEnabled;
          if (_sniController.text.isNotEmpty)
            settings['sni'] = _sniController.text.trim();
          if (_alpnController.text.trim().isNotEmpty) {
            settings['alpn'] = _alpnController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          settings['realityEnabled'] = _vlessRealityEnabled;
          if (_vlessNetwork == 'ws') {
            settings['wsPath'] = _vlessWsPathController.text.isEmpty
                ? '/'
                : _vlessWsPathController.text;
            if (_vlessWsHostController.text.trim().isNotEmpty) {
              settings['wsHeaders'] = {
                'Host': _vlessWsHostController.text.trim(),
              };
            }
          } else if (_vlessNetwork == 'grpc') {
            settings['grpcServiceName'] = _vlessGrpcServiceNameController.text
                .trim();
          } else if (_vlessNetwork == 'http') {
            final hosts = _vlessHttpHostController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            if (hosts.isNotEmpty) settings['httpHost'] = hosts;
            settings['httpPath'] = _vlessHttpPathController.text.isEmpty
                ? '/'
                : _vlessHttpPathController.text;
          }
          if (_vlessRealityEnabled) {
            if (_realityPublicKeyController.text.isNotEmpty)
              settings['realityPublicKey'] = _realityPublicKeyController.text
                  .trim();
            if (_realityShortIdController.text.isNotEmpty)
              settings['realityShortId'] = _realityShortIdController.text
                  .trim();
            if (_realityFingerprintController.text.isNotEmpty)
              settings['fingerprint'] = _realityFingerprintController.text
                  .trim();
          }
          if (_vlessFlowController.text.trim().isNotEmpty)
            settings['flow'] = _vlessFlowController.text.trim();
          if (_vlessEncryptionController.text.trim().isNotEmpty)
            settings['encryption'] = _vlessEncryptionController.text.trim();
          break;

        case 'trojan':
        case 'hysteria2':
        case 'anytls':
        case 'shadowtls':
        case 'hysteria':
          settings['password'] = _passwordController.text;
          if (_sniController.text.isNotEmpty) {
            settings['sni'] = _sniController.text.trim();
          }
          settings['skipCertVerify'] = _skipCertVerify;
          if (_alpnController.text.trim().isNotEmpty) {
            final list = _alpnController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            if (list.isNotEmpty) settings['alpn'] = list;
          }
          break;
        case 'tuic':
          if (_tuicUuidController.text.isNotEmpty)
            settings['uuid'] = _tuicUuidController.text.trim();
          if (_tuicPasswordController.text.isNotEmpty)
            settings['password'] = _tuicPasswordController.text.trim();
          if (_tuicAlpnController.text.trim().isNotEmpty) {
            settings['alpn'] = _tuicAlpnController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          settings['udpRelayMode'] = _tuicUdpRelayMode;
          settings['congestion'] = _tuicCongestion;
          if (_sniController.text.isNotEmpty)
            settings['sni'] = _sniController.text.trim();
          settings['skipCertVerify'] = _skipCertVerify;
          break;

        case 'wireguard':
          settings['privateKey'] = _wgPrivateKeyController.text.trim();
          settings['peerPublicKey'] = _wgPeerPublicKeyController.text.trim();
          if (_wgAddressController.text.trim().isNotEmpty) {
            settings['localAddress'] = _wgAddressController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          if (_wgDnsController.text.trim().isNotEmpty) {
            settings['dns'] = _wgDnsController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          if (_wgReservedController.text.trim().isNotEmpty)
            settings['reserved'] = _wgReservedController.text.trim();
          if (_wgMtuController.text.trim().isNotEmpty)
            settings['mtu'] = int.tryParse(_wgMtuController.text.trim());
          break;

        case 'socks':
        case 'http':
          if (_usernameController.text.isNotEmpty)
            settings['username'] = _usernameController.text.trim();
          if (_passwordController.text.isNotEmpty)
            settings['password'] = _passwordController.text.trim();
          settings['tlsEnabled'] = !_skipCertVerify; // true 表示启用TLS并校验证书
          if (settings['tlsEnabled'] == true && _sniController.text.isNotEmpty)
            settings['sni'] = _sniController.text.trim();
          break;
      }

      final config = VPNConfig(
        name: _nameController.text,
        type: _selectedType,
        server: _serverController.text,
        port: int.parse(_portController.text),
        settings: settings,
      );

      final provider = context.read<VPNProviderV2>();
      if (widget.editIndex != null) {
        provider.updateConfig(widget.editIndex!, config);
      } else {
        provider.addConfig(config);
      }
      safePop(context);
    }
  }

  // 导入逻辑已移除
}
