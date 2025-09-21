import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/outbound_binding_service.dart';
import '../services/config_manager.dart';
import '../models/vpn_config.dart';

class OutboundBindingPage extends StatefulWidget {
  const OutboundBindingPage({super.key});

  @override
  State<OutboundBindingPage> createState() => _OutboundBindingPageState();
}

class _OutboundBindingPageState extends State<OutboundBindingPage> {
  final _binding = OutboundBindingService.instance;
  final _cfgMgr = ConfigManager();

  String? _aId;
  String? _bId;
  String _finalTag = 'proxy';
  bool _loading = true;

  List<VPNConfig> _configs = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (_cfgMgr.configs.isEmpty) {
        await _cfgMgr.loadConfigs();
      }
      if (!_binding.isInitialized) {
        await _binding.initialize();
      }
      setState(() {
        _configs = List<VPNConfig>.from(_cfgMgr.configs);
        _aId = _binding.outboundAConfigId;
        _bId = _binding.outboundBConfigId;
        _finalTag = _binding.finalOutboundTag;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '多出站绑定',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      backgroundColor: AppTheme.bgDark,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBindingCard(
                    title: '代理A (proxy-a)',
                    value: _aId,
                    onChanged: (v) => setState(() => _aId = v),
                  ),
                  const SizedBox(height: 12),
                  _buildBindingCard(
                    title: '代理B (proxy-b)',
                    value: _bId,
                    onChanged: (v) => setState(() => _bId = v),
                  ),
                  const SizedBox(height: 16),
                  _buildFinalSelector(),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.borderColor),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            '返回',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _loading ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryNeon,
                            foregroundColor: AppTheme.bgDark,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('保存并生效'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBindingCard({
    required String title,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: value,
            isExpanded: true,
            dropdownColor: AppTheme.bgCard,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.bgDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppTheme.borderColor.withAlpha(100),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppTheme.borderColor.withAlpha(100),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primaryNeon),
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  '未绑定',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              ..._configs.map(
                (c) => DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text(
                    c.name.isNotEmpty
                        ? c.name
                        : '${c.type.toUpperCase()} ${c.server}:${c.port}',
                    style: const TextStyle(color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildFinalSelector() {
    final options = [
      _FinalOption('proxy', '默认代理 (proxy)'),
      _FinalOption('proxy-a', '代理A (proxy-a)'),
      _FinalOption('proxy-b', '代理B (proxy-b)'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '默认出站 (route.final)',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...options.map(
            (o) => RadioListTile<String>(
              value: o.tag,
              groupValue: _finalTag,
              onChanged: (v) => setState(() => _finalTag = v ?? 'proxy'),
              dense: true,
              activeColor: AppTheme.primaryNeon,
              title: Text(
                o.label,
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await _binding.setOutboundBindingA(_aId);
      await _binding.setOutboundBindingB(_bId);
      await _binding.setFinalOutboundTag(_finalTag);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已保存绑定设置（重新连接后生效）'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _FinalOption {
  final String tag;
  final String label;
  const _FinalOption(this.tag, this.label);
}
