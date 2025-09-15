import 'package:flutter/material.dart';
import 'package:gsou/utils/safe_navigator.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider_v2.dart';
import '../models/vpn_config.dart';
import '../theme/app_theme.dart';

class SimpleAddConfigDialog extends StatefulWidget {
  const SimpleAddConfigDialog({super.key});

  @override
  State<SimpleAddConfigDialog> createState() => _SimpleAddConfigDialogState();
}

class _SimpleAddConfigDialogState extends State<SimpleAddConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serverController = TextEditingController();
  final _portController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedType = 'shadowsocks';

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryNeon, AppTheme.accentNeon],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: AppTheme.bgDark,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '添加服务器',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => safePop(context),
                  icon: const Icon(Icons.close),
                  color: AppTheme.textHint,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 表单
            Form(
              key: _formKey,
              child: Column(
                children: [
                  // 配置名称
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '配置名称',
                      hintText: '例如: 香港节点',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入配置名称';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // 协议类型
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    decoration: const InputDecoration(
                      labelText: '协议类型',
                      prefixIcon: Icon(Icons.vpn_lock),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'shadowsocks',
                        child: Text('Shadowsocks'),
                      ),
                      DropdownMenuItem(value: 'vmess', child: Text('VMess')),
                      DropdownMenuItem(value: 'trojan', child: Text('Trojan')),
                      DropdownMenuItem(
                        value: 'hysteria2',
                        child: Text('Hysteria2'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedType = value!;
                      });
                    },
                  ),

                  const SizedBox(height: 16),

                  // 服务器地址
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _serverController,
                          decoration: const InputDecoration(
                            labelText: '服务器地址',
                            hintText: 'example.com',
                            prefixIcon: Icon(Icons.dns),
                          ),
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
                        child: TextFormField(
                          controller: _portController,
                          decoration: const InputDecoration(
                            labelText: '端口',
                            hintText: '443',
                            prefixIcon: Icon(Icons.router),
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

                  const SizedBox(height: 16),

                  // 密码
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.key),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入密码';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 按钮
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => safePop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saveConfig,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNeon,
                      foregroundColor: AppTheme.bgDark,
                    ),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
        case 'vmess':
          settings['uuid'] = _passwordController.text; // 简化处理，用密码字段作为UUID
          settings['alterId'] = 0;
          settings['security'] = 'auto';
          settings['network'] = 'tcp';
          break;
        case 'trojan':
        case 'hysteria2':
          settings['password'] = _passwordController.text;
          settings['skipCertVerify'] = false;
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
      provider.addConfig(config);
      safePop(context);

      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('服务器 "${config.name}" 添加成功'),
          backgroundColor: AppTheme.successGreen,
        ),
      );
    }
  }
}
