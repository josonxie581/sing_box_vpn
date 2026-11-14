import 'package:flutter/material.dart';

import '../services/auto_start_service.dart';
import '../theme/app_theme.dart';

class AutoStartCard extends StatefulWidget {
  const AutoStartCard({super.key, this.service});

  final AutoStartService? service;

  @override
  State<AutoStartCard> createState() => _AutoStartCardState();
}

class _AutoStartCardState extends State<AutoStartCard>
    with WidgetsBindingObserver {
  late final AutoStartService _service = widget.service ?? AutoStartService();
  bool _enabled = false;
  bool _autoConnect = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _refresh();
  }

  Future<void> _refresh() => _update(null);

  Future<void> _update(bool? value) async {
    if (!_service.isSupported) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final enabled = value == null
          ? await _service.isEnabled()
          : await _service.setEnabled(value);
      final autoConnect = await _service.isAutoConnectEnabled();
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _autoConnect = autoConnect;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateAutoConnect(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final actual = await _service.setAutoConnectEnabled(value);
      if (mounted) {
        setState(() {
          _autoConnect = actual;
          // Service 已验证系统任务成功启用，两个开关一起反映实际结果。
          if (actual) _enabled = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isSupported) return const SizedBox.shrink();
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
          _buildSetting(
            icon: Icons.power_settings_new,
            title: '开机自动启动',
            description: _busy ? '正在同步系统启动设置…' : _service.description,
            value: _enabled,
            onChanged: _busy || _error != null ? null : _update,
          ),
          const Divider(height: 24, color: AppTheme.borderColor),
          _buildSetting(
            icon: Icons.play_circle_outline,
            title: '开机后自动开始',
            description: _enabled
                ? '开机启动后自动连接上次选中的节点'
                : '开启后同时启用开机自启，并自动连接上次选中的节点',
            value: _autoConnect,
            onChanged: _busy || _error != null ? null : _updateAutoConnect,
          ),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.warningOrange,
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _refresh,
              child: const Text('重新读取'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSetting({
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) => Row(
    children: [
      Icon(icon, color: AppTheme.primaryNeon),
      const SizedBox(width: 12),
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
  );
}
