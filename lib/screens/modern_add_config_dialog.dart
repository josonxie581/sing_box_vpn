import 'package:flutter/material.dart';
import 'package:gsou/utils/safe_navigator.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/vpn_config.dart';
import '../theme/app_theme.dart';

class ModernAddConfigDialog extends StatefulWidget {
  final VPNConfig? initialConfig;
  final int? editIndex;

  const ModernAddConfigDialog({super.key, this.initialConfig, this.editIndex});

  @override
  State<ModernAddConfigDialog> createState() => _ModernAddConfigDialogState();
}

class _ModernAddConfigDialogState extends State<ModernAddConfigDialog>
    with TickerProviderStateMixin {
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

  // VMess 特定
  String _vmessSecurity = 'auto';
  String _vmessNetwork = 'tcp';
  final _wsPathController = TextEditingController(text: '/');
  final _wsHostController = TextEditingController();
  final _grpcServiceNameController = TextEditingController();
  final _httpHostController = TextEditingController();
  final _httpPathController = TextEditingController(text: '/');

  bool _skipCertVerify = false;
  String _selectedType = 'shadowsocks';

  late TabController _tabController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 1, vsync: this);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    // 初始化编辑模式的数据
    final cfg = widget.initialConfig;
    if (cfg != null) {
      _nameController.text = cfg.name;
      _selectedType = cfg.type;
      _serverController.text = cfg.server;
      _portController.text = cfg.port.toString();

      final s = cfg.settings;
      switch (cfg.type.toLowerCase()) {
        case 'shadowsocks':
          _methodController.text = (s['method'] ?? 'aes-256-gcm').toString();
          _passwordController.text = (s['password'] ?? '').toString();
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
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 560,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              _buildHeader(),

              // Tab栏
              _buildTabBar(),

              // 内容区
              Flexible(
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildManualForm()],
                ),
              ),

              // 底部按钮
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  // 构建标题栏
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryNeon.withOpacity(0.1),
            AppTheme.accentNeon.withOpacity(0.05),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryNeon, AppTheme.accentNeon],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              widget.initialConfig == null ? Icons.add : Icons.edit,
              color: AppTheme.bgDark,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialConfig == null ? '添加服务器' : '编辑服务器',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.initialConfig == null ? '配置新的 VPN 服务器连接' : '修改服务器配置信息',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textHint,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            color: AppTheme.textHint,
            onPressed: () => safePop(context),
          ),
        ],
      ),
    );
  }

  // 构建Tab栏
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor.withOpacity(0.2)),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        tabs: const [Tab(icon: Icon(Icons.edit_note, size: 20), text: '手动配置')],
      ),
    );
  }

  // 构建手动配置表单
  Widget _buildManualForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 基本信息
            _buildSectionTitle('基本信息'),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameController,
              decoration: _buildInputDecoration(
                label: '配置名称',
                hint: '例如: 香港节点',
                icon: Icons.label_outline,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入配置名称';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // 协议选择
            _buildProtocolSelector(),

            const SizedBox(height: 24),

            // 服务器信息
            _buildSectionTitle('服务器信息'),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _serverController,
                    decoration: _buildInputDecoration(
                      label: '服务器地址',
                      hint: 'example.com',
                      icon: Icons.dns,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入服务器地址';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _portController,
                    decoration: _buildInputDecoration(
                      label: '端口',
                      hint: '443',
                      icon: Icons.router,
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入端口';
                      }
                      final port = int.tryParse(value);
                      if (port == null || port < 1 || port > 65535) {
                        return '端口无效';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 认证信息
            _buildSectionTitle('认证信息'),
            const SizedBox(height: 16),

            // 根据协议显示不同字段
            ..._buildProtocolSpecificFields(),
          ],
        ),
      ),
    );
  }

  // 构建底部按钮
  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface.withOpacity(0.5),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => safePop(context),
            child: const Text('取消'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _saveManualConfig,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNeon,
              foregroundColor: AppTheme.bgDark,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text(widget.initialConfig == null ? '保存' : '更新'),
          ),
        ],
      ),
    );
  }

  // 构建协议选择器
  Widget _buildProtocolSelector() {
    final protocols = [
      {
        'type': 'shadowsocks',
        'icon': Icons.lock_outline,
        'color': AppTheme.primaryNeon,
      },
      {'type': 'vmess', 'icon': Icons.vpn_lock, 'color': AppTheme.accentNeon},
      {
        'type': 'trojan',
        'icon': Icons.security,
        'color': AppTheme.warningOrange,
      },
      {
        'type': 'hysteria2',
        'icon': Icons.speed,
        'color': AppTheme.successGreen,
      },
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: protocols.map((protocol) {
          final isSelected = _selectedType == protocol['type'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedType = protocol['type'] as String;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (protocol['color'] as Color).withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(
                      protocol['icon'] as IconData,
                      color: isSelected
                          ? protocol['color'] as Color
                          : AppTheme.textHint,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (protocol['type'] as String).toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? protocol['color'] as Color
                            : AppTheme.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 构建协议特定字段
  List<Widget> _buildProtocolSpecificFields() {
    switch (_selectedType) {
      case 'shadowsocks':
        return [
          DropdownButtonFormField<String>(
            value: _methodController.text,
            decoration: _buildInputDecoration(
              label: '加密方法',
              icon: Icons.enhanced_encryption,
            ),
            items: const [
              DropdownMenuItem(
                value: 'aes-256-gcm',
                child: Text('AES-256-GCM'),
              ),
              DropdownMenuItem(
                value: 'aes-128-gcm',
                child: Text('AES-128-GCM'),
              ),
              DropdownMenuItem(
                value: 'chacha20-poly1305',
                child: Text('ChaCha20-Poly1305'),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _methodController.text = value!;
              });
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            decoration: _buildInputDecoration(label: '密码', icon: Icons.key),
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
          TextFormField(
            controller: _uuidController,
            decoration: _buildInputDecoration(
              label: 'UUID',
              hint: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
              icon: Icons.fingerprint,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入 UUID';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _alterIdController,
                  decoration: _buildInputDecoration(
                    label: 'Alter ID',
                    icon: Icons.tag,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _vmessSecurity,
                  decoration: _buildInputDecoration(
                    label: '加密',
                    icon: Icons.lock,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(value: 'none', child: Text('None')),
                    DropdownMenuItem(
                      value: 'aes-128-gcm',
                      child: Text('AES-128-GCM'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _vmessSecurity = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 传输协议部分
          _buildSectionTitle('传输协议'),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _vmessNetwork,
            decoration: _buildInputDecoration(
              label: '传输类型',
              icon: Icons.swap_horiz,
            ),
            items: const [
              DropdownMenuItem(value: 'tcp', child: Text('TCP')),
              DropdownMenuItem(value: 'ws', child: Text('WebSocket')),
              DropdownMenuItem(value: 'grpc', child: Text('gRPC')),
              DropdownMenuItem(value: 'http', child: Text('HTTP')),
            ],
            onChanged: (value) {
              setState(() {
                _vmessNetwork = value!;
              });
            },
          ),

          // 根据传输类型显示相应配置
          ..._buildVmessTransportFields(),
        ];

      case 'trojan':
      case 'hysteria2':
        return [
          TextFormField(
            controller: _passwordController,
            decoration: _buildInputDecoration(label: '密码', icon: Icons.key),
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _sniController,
            decoration: _buildInputDecoration(
              label: 'SNI（可选）',
              hint: 'example.com',
              icon: Icons.public,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _alpnController,
            decoration: _buildInputDecoration(
              label: 'ALPN（可选）',
              hint: '例如: h3,h2,http/1.1',
              icon: Icons.layers,
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('跳过证书验证'),
            subtitle: const Text(
              '仅在自签证书时启用',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
            value: _skipCertVerify,
            onChanged: (v) => setState(() => _skipCertVerify = v!),
            // CheckboxListTile 不支持 thumbColor，但其内部 Checkbox 支持 fillColor
            fillColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => states.contains(WidgetState.selected)
                  ? AppTheme.primaryNeon
                  : null,
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ];

      default:
        return [];
    }
  }

  // 构建输入装饰
  InputDecoration _buildInputDecoration({
    required String label,
    String? hint,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, size: 20, color: AppTheme.textHint)
          : null,
      filled: true,
      fillColor: AppTheme.bgSurface.withOpacity(0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.borderColor.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.borderColor.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryNeon, width: 2),
      ),
    );
  }

  // 构建小节标题
  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryNeon, AppTheme.accentNeon],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  // 构建 VMess 传输层配置字段
  List<Widget> _buildVmessTransportFields() {
    switch (_vmessNetwork) {
      case 'ws':
        return [
          const SizedBox(height: 16),
          TextFormField(
            controller: _wsPathController,
            decoration: _buildInputDecoration(
              label: 'WebSocket 路径',
              hint: '/',
              icon: Icons.route,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _wsHostController,
            decoration: _buildInputDecoration(
              label: 'WebSocket Host（可选）',
              hint: 'example.com',
              icon: Icons.web,
            ),
          ),
        ];

      case 'grpc':
        return [
          const SizedBox(height: 16),
          TextFormField(
            controller: _grpcServiceNameController,
            decoration: _buildInputDecoration(
              label: 'gRPC 服务名',
              hint: 'GunService',
              icon: Icons.settings_ethernet,
            ),
          ),
        ];

      case 'http':
        return [
          const SizedBox(height: 16),
          TextFormField(
            controller: _httpHostController,
            decoration: _buildInputDecoration(
              label: 'HTTP Host（可选）',
              hint: '多个用逗号分隔',
              icon: Icons.web,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _httpPathController,
            decoration: _buildInputDecoration(
              label: 'HTTP 路径',
              hint: '/',
              icon: Icons.route,
            ),
          ),
        ];

      default:
        return [];
    }
  }

  // 保存手动配置
  void _saveManualConfig() {
    if (_formKey.currentState!.validate()) {
      final settings = <String, dynamic>{};

      switch (_selectedType) {
        case 'shadowsocks':
          settings['method'] = _methodController.text;
          settings['password'] = _passwordController.text;
          break;
        case 'vmess':
          settings['uuid'] = _uuidController.text;
          settings['alterId'] = int.parse(_alterIdController.text);
          settings['security'] = _vmessSecurity;
          settings['network'] = _vmessNetwork;

          // 添加传输层配置
          switch (_vmessNetwork) {
            case 'ws':
              settings['wsPath'] = _wsPathController.text;
              if (_wsHostController.text.isNotEmpty) {
                settings['wsHeaders'] = {'Host': _wsHostController.text};
              }
              break;
            case 'grpc':
              settings['grpcServiceName'] = _grpcServiceNameController.text;
              break;
            case 'http':
              if (_httpHostController.text.isNotEmpty) {
                settings['httpHost'] = _httpHostController.text
                    .split(',')
                    .map((e) => e.trim())
                    .toList();
              }
              settings['httpPath'] = _httpPathController.text;
              break;
          }
          break;
        case 'trojan':
        case 'hysteria2':
          settings['password'] = _passwordController.text;
          if (_sniController.text.isNotEmpty) {
            settings['sni'] = _sniController.text;
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
      }

      final config = VPNConfig(
        name: _nameController.text,
        type: _selectedType,
        server: _serverController.text,
        port: int.parse(_portController.text),
        settings: settings,
      );

      final provider = context.read<VPNProvider>();
      if (widget.editIndex != null) {
        provider.updateConfig(widget.editIndex!, config);
      } else {
        provider.addConfig(config);
      }
      safePop(context);
    }
  }
}
