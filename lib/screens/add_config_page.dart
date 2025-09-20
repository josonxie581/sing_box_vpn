import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../providers/vpn_provider_v2.dart';
import '../models/vpn_config.dart';
import '../theme/app_theme.dart';
import '../services/qr_decoder.dart';
import '../services/simple_qr_functions.dart';
import '../services/smart_screenshot_service.dart';
import '../services/official_screen_capture.dart';

class AddConfigPage extends StatefulWidget {
  final VPNConfig? config;
  final int? configIndex;

  const AddConfigPage({super.key, this.config, this.configIndex});

  @override
  State<AddConfigPage> createState() => _AddConfigPageState();
}

class _AddConfigPageState extends State<AddConfigPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serverController = TextEditingController();
  final _portController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _uuidController = TextEditingController();
  final _alterIdController = TextEditingController();
  final _pathController = TextEditingController();
  final _hostController = TextEditingController();
  final _alpnController = TextEditingController();
  final _sniController = TextEditingController();
  final _fingerprintController = TextEditingController();
  final _flowController = TextEditingController();
  final _tuicVersionController = TextEditingController(text: '');
  final _vlessEncryptionController = TextEditingController(text: 'none');

  // VLESS
  String _vlessNetwork = 'tcp';
  bool _vlessTlsEnabled = true;
  bool _vlessRealityEnabled = false;
  final _realityPublicKeyController = TextEditingController();
  final _realityShortIdController = TextEditingController();

  // TUIC
  final _tuicPasswordController = TextEditingController();
  String _tuicUdpRelayMode = 'native';
  String _tuicCongestion = 'bbr';

  // WireGuard
  final _wgPrivateKeyController = TextEditingController();
  final _wgPeerPublicKeyController = TextEditingController();
  final _wgAddressController = TextEditingController(); // 逗号分隔
  final _wgDnsController = TextEditingController(); // 逗号分隔
  final _wgReservedController = TextEditingController();
  final _wgMtuController = TextEditingController();

  String _selectedType = 'shadowsocks';
  String _selectedSecurity = 'auto';
  String _selectedNetwork = 'tcp';
  bool _skipCertVerify = false;
  String _ss2022Method = '2022-blake3-aes-128-gcm';

  // 拖放状态

  // Tabs: 手动配置 / 导入配置 / 订阅
  late TabController _tabController;
  final _subscribeUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 初始化截图检测服务
    ScreenshotDetectorService.initialize();

    if (widget.config != null) {
      _initializeEditMode(widget.config!);
    }
  }

  void _initializeEditMode(VPNConfig config) {
    _nameController.text = config.name;
    _serverController.text = config.server;
    _portController.text = config.port.toString();
    _passwordController.text = config.settings['password'] ?? '';

    final type = config.type;
    switch (type) {
      case 'ss':
      case 'shadowsocks':
        _selectedType = 'shadowsocks';
        break;
      case 'shadowsocks-2022':
        _selectedType = 'shadowsocks-2022';
        _passwordController.text = (config.settings['password'] ?? '')
            .toString();
        _ss2022Method = (config.settings['method'] ?? _ss2022Method).toString();
        break;
      case 'vmess':
        _selectedType = 'vmess';
        _uuidController.text = config.settings['uuid'] ?? '';
        _alterIdController.text =
            (config.settings['alterId']?.toString() ?? '');
        _pathController.text = config.settings['path'] ?? '';
        _hostController.text = config.settings['host'] ?? '';
        final alpn = config.settings['alpn'];
        if (alpn is List) {
          _alpnController.text = alpn.join(',');
        } else {
          _alpnController.text = alpn?.toString() ?? '';
        }
        _selectedSecurity = config.settings['security'] ?? 'auto';
        _selectedNetwork = config.settings['network'] ?? 'tcp';
        _skipCertVerify = config.settings['skipCertVerify'] ?? false;
        break;
      case 'vless':
        _selectedType = 'vless';
        _uuidController.text = (config.settings['uuid'] ?? '').toString();
        _vlessNetwork = (config.settings['network'] ?? 'tcp').toString();
        // 兼容不同存储字段
        _pathController.text =
            (config.settings['wsPath'] ??
                    config.settings['httpPath'] ??
                    config.settings['path'] ??
                    '')
                .toString();
        final httpHost = config.settings['httpHost'];
        if (httpHost is List) {
          _hostController.text = httpHost.join(',');
        } else {
          _hostController.text = (config.settings['host'] ?? '').toString();
        }
        _vlessTlsEnabled = config.settings['tlsEnabled'] == true;
        _vlessRealityEnabled = config.settings['realityEnabled'] == true;
        _sniController.text = (config.settings['sni'] ?? '').toString();
        _fingerprintController.text = (config.settings['fingerprint'] ?? '')
            .toString();
        _flowController.text = (config.settings['flow'] ?? '').toString();
        final enc = (config.settings['encryption'] ?? '').toString();
        if (enc.isNotEmpty) _vlessEncryptionController.text = enc;
        final vAlpn = config.settings['alpn'];
        if (vAlpn is List) {
          _alpnController.text = vAlpn.join(',');
        } else if (vAlpn != null) {
          _alpnController.text = vAlpn.toString();
        }
        _realityPublicKeyController.text =
            (config.settings['realityPublicKey'] ?? '').toString();
        _realityShortIdController.text =
            (config.settings['realityShortId'] ?? '').toString();
        break;
      case 'trojan':
        _selectedType = 'trojan';
        _pathController.text = config.settings['path'] ?? '';
        _hostController.text = config.settings['host'] ?? '';
        final tAlpn = config.settings['alpn'];
        if (tAlpn is List) {
          _alpnController.text = tAlpn.join(',');
        } else {
          _alpnController.text = tAlpn?.toString() ?? '';
        }
        _skipCertVerify = config.settings['skipCertVerify'] ?? false;
        break;
      case 'hysteria2':
        _selectedType = 'hysteria2';
        _passwordController.text = (config.settings['password'] ?? '')
            .toString();
        final hAlpn = config.settings['alpn'];
        if (hAlpn is List) {
          _alpnController.text = hAlpn.join(',');
        } else if (hAlpn != null) {
          _alpnController.text = hAlpn.toString();
        }
        _skipCertVerify = config.settings['skipCertVerify'] ?? false;
        break;
      case 'tuic':
        _selectedType = 'tuic';
        _uuidController.text = (config.settings['uuid'] ?? '').toString();
        _tuicPasswordController.text = (config.settings['password'] ?? '')
            .toString();
        _tuicUdpRelayMode =
            (config.settings['udpRelayMode'] ?? _tuicUdpRelayMode).toString();
        _tuicCongestion = (config.settings['congestion'] ?? _tuicCongestion)
            .toString();
        _sniController.text = (config.settings['sni'] ?? '').toString();
        _skipCertVerify = (config.settings['skipCertVerify'] ?? false) == true;
        final tAlpn = config.settings['alpn'];
        if (tAlpn is List) {
          _alpnController.text = tAlpn.join(',');
        } else if (tAlpn != null) {
          _alpnController.text = tAlpn.toString();
        }
        final ver = config.settings['version'];
        if (ver != null) _tuicVersionController.text = ver.toString();
        break;
      case 'socks':
        _selectedType = 'socks';
        _usernameController.text = (config.settings['username'] ?? '')
            .toString();
        _passwordController.text = (config.settings['password'] ?? '')
            .toString();
        break;
      case 'http':
        _selectedType = 'http';
        _usernameController.text = (config.settings['username'] ?? '')
            .toString();
        _passwordController.text = (config.settings['password'] ?? '')
            .toString();
        break;
      case 'wireguard':
        _selectedType = 'wireguard';
        _wgPrivateKeyController.text = (config.settings['privateKey'] ?? '')
            .toString();
        _wgPeerPublicKeyController.text =
            (config.settings['peerPublicKey'] ?? '').toString();
        final addrs = config.settings['localAddress'];
        if (addrs is List) _wgAddressController.text = addrs.join(',');
        final dns = config.settings['dns'];
        if (dns is List) _wgDnsController.text = dns.join(',');
        _wgReservedController.text = (config.settings['reserved'] ?? '')
            .toString();
        final mtu = config.settings['mtu'];
        if (mtu != null) _wgMtuController.text = mtu.toString();
        break;
      default:
        break;
    }
  }


  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _uuidController.dispose();
    _alterIdController.dispose();
    _pathController.dispose();
    _hostController.dispose();
    _alpnController.dispose();
    _sniController.dispose();
    _fingerprintController.dispose();
    _flowController.dispose();
    _tuicVersionController.dispose();
    _vlessEncryptionController.dispose();
    _realityPublicKeyController.dispose();
    _realityShortIdController.dispose();
    _tuicPasswordController.dispose();
    _wgPrivateKeyController.dispose();
    _wgPeerPublicKeyController.dispose();
    _wgAddressController.dispose();
    _wgDnsController.dispose();
    _wgReservedController.dispose();
    _wgMtuController.dispose();
    _subscribeUrlController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // 顶部标题
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
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
                  Text(
                    widget.config != null ? '编辑配置' : '添加服务',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // 表单/订阅 Tabs
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.primaryNeon,
                  unselectedLabelColor: AppTheme.textSecondary,
                  indicatorColor: AppTheme.primaryNeon,
                  tabs: const [
                    Tab(text: '手动配置'),
                    Tab(text: '订阅'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 600,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 手动配置
                    Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // 配置名称
                            _buildTextFormField(
                              controller: _nameController,
                              label: '配置名称',
                              hint: '例如: 香港节点',
                              icon: Icons.label_outline,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return '请输入配置名';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            // 协议类型
                            _buildDropdownField(
                              value: _selectedType,
                              label: '协议类型',
                              icon: Icons.vpn_lock,
                              items: const [
                                DropdownMenuItem(
                                  value: 'shadowsocks',
                                  child: Text('Shadowsocks'),
                                ),
                                DropdownMenuItem(
                                  value: 'shadowsocks-2022',
                                  child: Text('Shadowsocks-2022'),
                                ),
                                DropdownMenuItem(
                                  value: 'vmess',
                                  child: Text('VMess'),
                                ),
                                DropdownMenuItem(
                                  value: 'vless',
                                  child: Text('VLESS/REALITY'),
                                ),
                                DropdownMenuItem(
                                  value: 'trojan',
                                  child: Text('Trojan'),
                                ),
                                DropdownMenuItem(
                                  value: 'anytls',
                                  child: Text('AnyTLS'),
                                ),
                                DropdownMenuItem(
                                  value: 'shadowtls',
                                  child: Text('ShadowTLS'),
                                ),
                                DropdownMenuItem(
                                  value: 'hysteria',
                                  child: Text('Hysteria'),
                                ),
                                DropdownMenuItem(
                                  value: 'hysteria2',
                                  child: Text('Hysteria2'),
                                ),
                                DropdownMenuItem(
                                  value: 'tuic',
                                  child: Text('TUIC v5'),
                                ),
                                DropdownMenuItem(
                                  value: 'socks',
                                  child: Text('SOCKS5'),
                                ),
                                DropdownMenuItem(
                                  value: 'http',
                                  child: Text('HTTP'),
                                ),
                                DropdownMenuItem(
                                  value: 'wireguard',
                                  child: Text('WireGuard'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedType = value!;
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                            // 服务器地址和端口
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _buildTextFormField(
                                    controller: _serverController,
                                    label: '服务器地址',
                                    hint: 'example.com',
                                    icon: Icons.dns,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return '请输入服务器地址';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTextFormField(
                                    controller: _portController,
                                    label: '端口',
                                    hint: '443',
                                    icon: Icons.pin,
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return '请输入端口';
                                      }
                                      final port = int.tryParse(value);
                                      if (port == null ||
                                          port < 1 ||
                                          port > 65535) {
                                        return '请输入有效端口 (1-65535)';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            ..._buildProtocolSpecificFields(),
                            const SizedBox(height: 40),
                            // 保存按钮
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: FilledButton(
                                onPressed: _saveConfig,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNeon,
                                  foregroundColor: AppTheme.bgDark,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  widget.config != null ? '更新配置' : '保存配置',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 订阅
                    _buildSubscribeForm(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建文本输入
  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppTheme.primaryNeon),
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          hintStyle: const TextStyle(color: AppTheme.textHint),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  // 构建下拉选择
  Widget _buildDropdownField({
    required String value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        items: items,
        onChanged: onChanged,
        style: const TextStyle(color: AppTheme.textPrimary),
        dropdownColor: AppTheme.bgCard,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppTheme.primaryNeon),
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  // 构建协议特定字段
  List<Widget> _buildProtocolSpecificFields() {
    switch (_selectedType) {
      case 'shadowsocks':
        return [
          _buildTextFormField(
            controller: _passwordController,
            label: '密码',
            hint: '请输入密码',
            icon: Icons.key,
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          _buildDropdownField(
            value: 'aes-256-gcm',
            label: '加密方法',
            icon: Icons.security,
            items: const [
              DropdownMenuItem(
                value: 'aes-256-gcm',
                child: Text('aes-256-gcm'),
              ),
              DropdownMenuItem(
                value: 'aes-128-gcm',
                child: Text('aes-128-gcm'),
              ),
              DropdownMenuItem(
                value: 'chacha20-poly1305',
                child: Text('chacha20-poly1305'),
              ),
            ],
            onChanged: (value) {},
          ),
        ];

      case 'shadowsocks-2022':
        return [
          _buildDropdownField(
            value: _ss2022Method,
            label: '加密方法',
            icon: Icons.security,
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
            onChanged: (v) => setState(() => _ss2022Method = v!),
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _passwordController,
            label: '密码/PSK',
            hint: '请输入密码或 PSK',
            icon: Icons.key,
          ),
        ];

      case 'vmess':
        return [
          _buildTextFormField(
            controller: _uuidController,
            label: 'UUID',
            hint: '请输入UUID',
            icon: Icons.key,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入UUID';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildTextFormField(
                  controller: _alterIdController,
                  label: 'Alter ID',
                  hint: '0',
                  icon: Icons.numbers,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField(
                  value: _selectedSecurity,
                  label: '加密方式',
                  icon: Icons.security,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('auto')),
                    DropdownMenuItem(value: 'none', child: Text('none')),
                    DropdownMenuItem(
                      value: 'aes-128-gcm',
                      child: Text('aes-128-gcm'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSecurity = value!;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildDropdownField(
                  value: _selectedNetwork,
                  label: '传输协议',
                  icon: Icons.language,
                  items: const [
                    DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                    DropdownMenuItem(value: 'ws', child: Text('WebSocket')),
                    DropdownMenuItem(value: 'grpc', child: Text('gRPC')),
                    DropdownMenuItem(value: 'http', child: Text('HTTP')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedNetwork = value!;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextFormField(
                  controller: _pathController,
                  label: '路径',
                  hint: '/path',
                  icon: Icons.route,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _hostController,
            label: 'Host',
            hint: 'example.com',
            icon: Icons.web,
          ),
        ];

      case 'vless':
        return [
          _buildTextFormField(
            controller: _uuidController,
            label: 'UUID (id)',
            hint: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
            icon: Icons.badge,
            validator: (v) => (v == null || v.isEmpty) ? '请输入 UUID' : null,
          ),
          const SizedBox(height: 20),
          _buildDropdownField(
            value: _vlessNetwork,
            label: '传输协议',
            icon: Icons.language,
            items: const [
              DropdownMenuItem(value: 'none', child: Text('None')),
              DropdownMenuItem(value: 'tcp', child: Text('TCP')),
              DropdownMenuItem(value: 'ws', child: Text('WebSocket')),
              DropdownMenuItem(value: 'grpc', child: Text('gRPC')),
              DropdownMenuItem(value: 'http', child: Text('HTTP')),
            ],
            onChanged: (v) => setState(() => _vlessNetwork = v!),
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _pathController,
            label: '路径 (ws/http 可选)',
            hint: '/',
            icon: Icons.route,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _hostController,
            label: 'Host（可选，逗号分隔）',
            hint: 'a.com,b.com',
            icon: Icons.web,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _sniController,
            label: 'SNI（可选）',
            hint: 'example.com',
            icon: Icons.verified_user,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _alpnController,
            label: 'ALPN（逗号分隔，可选）',
            hint: 'h2,h3',
            icon: Icons.api,
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('启用 TLS'),
            value: _vlessTlsEnabled,
            onChanged: (v) => setState(() => _vlessTlsEnabled = v),
            thumbColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => states.contains(WidgetState.selected)
                  ? AppTheme.primaryNeon
                  : null,
            ),
          ),
          SwitchListTile(
            title: const Text('启用 REALITY'),
            value: _vlessRealityEnabled,
            onChanged: (v) => setState(() => _vlessRealityEnabled = v),
            thumbColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => states.contains(WidgetState.selected)
                  ? AppTheme.primaryNeon
                  : null,
            ),
          ),
          if (_vlessRealityEnabled) ...[
            _buildTextFormField(
              controller: _realityPublicKeyController,
              label: 'REALITY 公钥 (pbk)',
              hint: '',
              icon: Icons.key,
            ),
            const SizedBox(height: 20),
            _buildTextFormField(
              controller: _realityShortIdController,
              label: 'REALITY 短 ID (sid)',
              hint: '',
              icon: Icons.numbers,
            ),
            const SizedBox(height: 20),
          ],
          _buildTextFormField(
            controller: _fingerprintController,
            label: 'uTLS 指纹（可选）',
            hint: 'chrome, firefox, safari, iosa, ...',
            icon: Icons.fingerprint,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _flowController,
            label: 'XTLS Flow（可选）',
            hint: 'xtls-rprx-vision 等',
            icon: Icons.waterfall_chart,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _vlessEncryptionController,
            label: '加密（encryption）',
            hint: 'none',
            icon: Icons.lock_open,
          ),
        ];

      case 'trojan':
      case 'hysteria2':
      case 'anytls':
      case 'shadowtls':
      case 'hysteria':
        return [
          _buildTextFormField(
            controller: _passwordController,
            label: '密码',
            hint: '请输入密码',
            icon: Icons.key,
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          if (_selectedType == 'hysteria2') ...[
            _buildTextFormField(
              controller: _alpnController,
              label: 'ALPN',
              hint: 'h3,h2,http/1.1',
              icon: Icons.api,
            ),
            const SizedBox(height: 20),
          ],
          Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
            ),
            child: SwitchListTile(
              title: const Text(
                '允许不安全（跳过证书验证）',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              subtitle: const Text(
                '不安全，仅用于测试',
                style: TextStyle(color: AppTheme.textHint, fontSize: 12),
              ),
              value: _skipCertVerify,
              onChanged: (value) {
                setState(() {
                  _skipCertVerify = value;
                });
              },
              thumbColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.selected)
                    ? AppTheme.primaryNeon
                    : null,
              ),
            ),
          ),
        ];

      case 'tuic':
        return [
          _buildTextFormField(
            controller: _uuidController,
            label: 'UUID（可选）',
            hint: '',
            icon: Icons.badge,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _tuicPasswordController,
            label: '密码（可选）',
            hint: '',
            icon: Icons.key,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _sniController,
            label: 'SNI（可选）',
            hint: 'example.com',
            icon: Icons.verified_user,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _alpnController,
            label: 'ALPN（逗号分隔，可选）',
            hint: 'h3,h2',
            icon: Icons.api,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _tuicVersionController,
            label: '版本（version）',
            hint: '',
            icon: Icons.tag,
          ),
          const SizedBox(height: 20),
          _buildDropdownField(
            value: _tuicUdpRelayMode,
            label: 'UDP Relay Mode',
            icon: Icons.router,
            items: const [
              DropdownMenuItem(value: 'native', child: Text('native')),
              DropdownMenuItem(value: 'quic', child: Text('quic')),
            ],
            onChanged: (v) => setState(() => _tuicUdpRelayMode = v!),
          ),
          const SizedBox(height: 20),
          _buildDropdownField(
            value: _tuicCongestion,
            label: '拥塞控制',
            icon: Icons.speed,
            items: const [
              DropdownMenuItem(value: 'bbr', child: Text('bbr')),
              DropdownMenuItem(value: 'cubic', child: Text('cubic')),
            ],
            onChanged: (v) => setState(() => _tuicCongestion = v!),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
            ),
            child: SwitchListTile(
              title: const Text(
                '跳过证书验证',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              subtitle: const Text(
                '不安全，仅用于测试',
                style: TextStyle(color: AppTheme.textHint, fontSize: 12),
              ),
              value: _skipCertVerify,
              onChanged: (value) {
                setState(() {
                  _skipCertVerify = value;
                });
              },
              thumbColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.selected)
                    ? AppTheme.primaryNeon
                    : null,
              ),
            ),
          ),
        ];

      case 'socks':
      case 'http':
        return [
          _buildTextFormField(
            controller: _usernameController,
            label: '用户名（可选）',
            hint: '',
            icon: Icons.person,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _passwordController,
            label: '密码（可选）',
            hint: '',
            icon: Icons.key,
            obscureText: true,
          ),
        ];

      case 'wireguard':
        return [
          _buildTextFormField(
            controller: _wgPrivateKeyController,
            label: 'Private Key',
            hint: '',
            icon: Icons.vpn_key,
            validator: (v) =>
                (v == null || v.isEmpty) ? '请输入 Private Key' : null,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _wgPeerPublicKeyController,
            label: 'Peer Public Key',
            hint: '',
            icon: Icons.public,
            validator: (v) =>
                (v == null || v.isEmpty) ? '请输入 Peer Public Key' : null,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _wgAddressController,
            label: '本地地址（逗号分隔）',
            hint: '10.0.0.2/32,fdfe:.../128',
            icon: Icons.edit_location_alt,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _wgDnsController,
            label: 'DNS（逗号分隔，可选）',
            hint: '1.1.1.1,8.8.8.8',
            icon: Icons.dns,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _wgReservedController,
            label: 'Reserved（可选）',
            hint: '',
            icon: Icons.data_array,
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _wgMtuController,
            label: 'MTU（可选）',
            hint: '1420',
            icon: Icons.settings_ethernet,
          ),
        ];

      default:
        return [];
    }
  }

  void _saveConfig() {
    if (_formKey.currentState!.validate()) {
      final settings = <String, dynamic>{};

      // 根据协议类型设置参数
      switch (_selectedType) {
        case 'shadowsocks':
          settings['method'] = 'aes-256-gcm';
          settings['password'] = _passwordController.text;
          break;
        case 'shadowsocks-2022':
          settings['method'] = _ss2022Method;
          settings['password'] = _passwordController.text;
          break;
        case 'vmess':
          settings['uuid'] = _uuidController.text;
          settings['alterId'] = int.tryParse(_alterIdController.text) ?? 0;
          settings['security'] = _selectedSecurity;
          settings['network'] = _selectedNetwork;
          if (_pathController.text.isNotEmpty) {
            settings['path'] = _pathController.text;
          }
          if (_hostController.text.isNotEmpty) {
            settings['host'] = _hostController.text;
          }
          // 传输专用键，便于 toSingBoxConfig 正确生成
          switch (_selectedNetwork) {
            case 'ws':
              if (_pathController.text.isNotEmpty)
                settings['wsPath'] = _pathController.text;
              if (_hostController.text.isNotEmpty)
                settings['wsHeaders'] = {'Host': _hostController.text};
              break;
            case 'http':
              if (_hostController.text.isNotEmpty)
                settings['httpHost'] = _hostController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
              if (_pathController.text.isNotEmpty)
                settings['httpPath'] = _pathController.text;
              break;
            case 'grpc':
              if (_pathController.text.isNotEmpty)
                settings['grpcServiceName'] = _pathController.text;
              break;
          }
          break;
        case 'vless':
          settings['uuid'] = _uuidController.text;
          settings['network'] = _vlessNetwork;
          if (_pathController.text.isNotEmpty)
            settings['path'] = _pathController.text;
          if (_hostController.text.isNotEmpty)
            settings['host'] = _hostController.text;
          settings['tlsEnabled'] = _vlessTlsEnabled;
          if (_sniController.text.isNotEmpty)
            settings['sni'] = _sniController.text;
          if (_alpnController.text.isNotEmpty)
            settings['alpn'] = _alpnController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          if (_vlessEncryptionController.text.isNotEmpty)
            settings['encryption'] = _vlessEncryptionController.text.trim();
          if (_flowController.text.isNotEmpty)
            settings['flow'] = _flowController.text.trim();
          if (_fingerprintController.text.isNotEmpty)
            settings['fingerprint'] = _fingerprintController.text.trim();
          settings['realityEnabled'] = _vlessRealityEnabled;
          if (_realityPublicKeyController.text.isNotEmpty)
            settings['realityPublicKey'] = _realityPublicKeyController.text;
          if (_realityShortIdController.text.isNotEmpty)
            settings['realityShortId'] = _realityShortIdController.text;
          // 传输专用键
          switch (_vlessNetwork) {
            case 'ws':
              if (_pathController.text.isNotEmpty)
                settings['wsPath'] = _pathController.text;
              if (_hostController.text.isNotEmpty)
                settings['wsHeaders'] = {'Host': _hostController.text};
              break;
            case 'http':
              if (_hostController.text.isNotEmpty)
                settings['httpHost'] = _hostController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
              if (_pathController.text.isNotEmpty)
                settings['httpPath'] = _pathController.text;
              break;
            case 'grpc':
              if (_pathController.text.isNotEmpty)
                settings['grpcServiceName'] = _pathController.text;
              break;
          }
          break;
        case 'trojan':
        case 'anytls':
        case 'shadowtls':
        case 'hysteria':
          settings['password'] = _passwordController.text;
          settings['skipCertVerify'] = _skipCertVerify;
          if (_alpnController.text.isNotEmpty) {
            settings['alpn'] = _alpnController.text
                .split(',')
                .map((e) => e.trim())
                .toList();
          }
          break;
        case 'hysteria2':
          settings['password'] = _passwordController.text;
          settings['skipCertVerify'] = _skipCertVerify;
          if (_alpnController.text.isNotEmpty) {
            settings['alpn'] = _alpnController.text
                .split(',')
                .map((e) => e.trim())
                .toList();
          }
          break;
        case 'tuic':
          if (_uuidController.text.isNotEmpty)
            settings['uuid'] = _uuidController.text;
          if (_tuicPasswordController.text.isNotEmpty)
            settings['password'] = _tuicPasswordController.text;
          if (_sniController.text.isNotEmpty)
            settings['sni'] = _sniController.text;
          if (_alpnController.text.isNotEmpty)
            settings['alpn'] = _alpnController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          final ver = int.tryParse(_tuicVersionController.text.trim());
          if (ver != null) settings['version'] = ver;
          settings['udpRelayMode'] = _tuicUdpRelayMode;
          settings['congestion'] = _tuicCongestion;
          settings['skipCertVerify'] = _skipCertVerify;
          break;
        case 'socks':
        case 'http':
          if (_usernameController.text.isNotEmpty)
            settings['username'] = _usernameController.text;
          if (_passwordController.text.isNotEmpty)
            settings['password'] = _passwordController.text;
          break;
        case 'wireguard':
          settings['privateKey'] = _wgPrivateKeyController.text;
          settings['peerPublicKey'] = _wgPeerPublicKeyController.text;
          if (_wgAddressController.text.isNotEmpty)
            settings['localAddress'] = _wgAddressController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          if (_wgDnsController.text.isNotEmpty)
            settings['dns'] = _wgDnsController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          if (_wgReservedController.text.isNotEmpty)
            settings['reserved'] = _wgReservedController.text;
          if (_wgMtuController.text.isNotEmpty)
            settings['mtu'] = int.tryParse(_wgMtuController.text);
          break;
      }

      final config = VPNConfig(
        name: _nameController.text,
        type: _selectedType,
        server: _serverController.text,
        port: int.tryParse(_portController.text) ?? 0,
        settings: settings,
      );

      final provider = context.read<VPNProviderV2>();

      if (widget.config != null && widget.configIndex != null) {
        // 编辑模式：更新现有配置
        provider.updateConfig(widget.configIndex!, config);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('配置 "${config.name}" 更新成功'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      } else {
        // 添加模式：添加新配置
        provider.addConfig(config);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('服务 "${config.name}" 添加成功'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    }
  }

  // 简单的订阅表单（占位）
  Widget _buildSubscribeForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextFormField(
          controller: _subscribeUrlController,
          label: '订阅/分享链接',
          hint: 'https://example.com/sub 或 ss:// vmess:// trojan:// ...',
          icon: Icons.rss_feed,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            final link = _subscribeUrlController.text.trim();
            if (link.isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('请输入有效链接')));
              return;
            }
            final provider = context.read<VPNProviderV2>();
            // 支持直接单条分享链接导入
            final ok = await provider.importFromLink(link);
            if (!ok) {
              // 或按订阅内容解析（多条）
              final count = await provider.importFromSubscription(link);
              if (count <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('导入失败，请检查链接内容')),
                );
                return;
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('成功导入 $count 个配置')),
                );
              }
            } else {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('导入成功')));
            }
          },
          child: const Text('从链接导入'),
        ),
        const SizedBox(height: 12),
        // 第一行按钮
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['png', 'jpg', 'jpeg'],
                  );
                  if (result == null || result.files.single.path == null) {
                    return;
                  }
                  final filePath = result.files.single.path!;
                  final text = await QrDecoderService.decodeFromFile(filePath);
                  if (text == null || text.trim().isEmpty) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('未识别到二维码内容')));
                    return;
                  }
                  final provider = context.read<VPNProviderV2>();
                  // 优先尝试单条链接
                  final ok = await provider.importFromLink(text.trim());
                  if (!ok) {
                    final count = await provider.importFromSubscription(text);
                    if (count <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('二维码内容无法导入')),
                      );
                      return;
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('成功导入 $count 个配置')),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('导入成功')));
                  }
                },
                icon: const Icon(Icons.image),
                label: const Text('选择图片文件'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryNeon,
                  side: BorderSide(
                    color: AppTheme.primaryNeon.withOpacity(0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    // 从剪贴板获取文本链接
                    final textLink = await SimpleQRFunctions.getClipboardText();
                    if (textLink != null && textLink.trim().isNotEmpty) {
                      final provider = context.read<VPNProviderV2>();
                      final ok = await provider.importFromLink(textLink.trim());
                      if (!ok) {
                        final count = await provider.importFromSubscription(textLink.trim());
                        if (count <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('剪贴板链接无法导入')),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('成功导入 $count 个配置')),
                          );
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('从剪贴板文本导入成功')),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('剪贴板中没有可用的文本链接')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('剪贴板导入失败: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.content_paste),
                label: const Text('剪贴板文本'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryNeon,
                  side: BorderSide(
                    color: AppTheme.primaryNeon.withOpacity(0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    // 检查截图权限
                    final hasAccess = await OfficialScreenCapture.isAccessAllowed();
                    if (!hasAccess) {
                      await OfficialScreenCapture.requestAccess();
                    }

                    // 使用screen_capturer进行区域截图
                    final qrText = await OfficialScreenCapture.captureRegionAndScanQR();

                    if (qrText == null || qrText.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('未识别到二维码')),
                      );
                      return;
                    }

                    final provider = context.read<VPNProviderV2>();
                    // 优先尝试单条链接
                    final ok = await provider.importFromLink(qrText.trim());
                    if (!ok) {
                      final count = await provider.importFromSubscription(qrText);
                      if (count <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('二维码内容无法导入')),
                        );
                        return;
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('成功导入 $count 个配置')),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('区域截图识别导入成功')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('截图检测失败: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.screenshot_monitor),
                label: const Text('智能截屏'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryNeon,
                  side: BorderSide(
                    color: AppTheme.primaryNeon.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
