import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dmit_billing_info.dart';
import '../models/dmit_ssh_monitor.dart';
import '../services/dmit_billing_service.dart';
import '../services/dmit_ssh_monitor_service.dart';
import '../theme/app_theme.dart';

/// 当前 DMIT 节点的只读 SSH 实时运行卡片。
///
/// 已载入配置时必须精确匹配服务器主机，避免把一台服务器的数据展示到
/// 另一台节点。配置载入前仅用节点名中的 DMIT 标识显示初始化状态。
class DmitStatusCard extends StatefulWidget {
  const DmitStatusCard({
    super.key,
    required this.nodeName,
    required this.serverHost,
  });

  final String? nodeName;
  final String? serverHost;

  @override
  State<DmitStatusCard> createState() => _DmitStatusCardState();
}

class _DmitStatusCardState extends State<DmitStatusCard> {
  static final RegExp _dmitToken = RegExp(
    r'(^|[^a-z0-9])dmit([^a-z0-9]|$)',
    caseSensitive: false,
  );

  final DmitSshMonitorService _service = DmitSshMonitorService.instance;
  final DmitBillingService _billingService = DmitBillingService.instance;
  late final Listenable _listenables;

  @override
  void initState() {
    super.initState();
    _listenables = Listenable.merge([_service, _billingService]);
    if (!_service.initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_service.initialized) {
          unawaited(_service.initialize());
        }
      });
    }
    if (!_billingService.initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_billingService.initialized) {
          unawaited(_billingService.initialize());
        }
      });
    }
  }

  bool get _isCurrentServer {
    final host = widget.serverHost?.trim() ?? '';
    if (_service.monitoredHost != null && host.isNotEmpty) {
      return _service.monitorsHost(host);
    }
    return _dmitToken.hasMatch(widget.nodeName ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenables,
      builder: (context, _) {
        if (!_isCurrentServer) return const SizedBox.shrink();
        final runtime = _service.currentInfo;
        final billing = _billingService.infoFor(_service.serviceId);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor.withAlpha(80)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 8),
              if (runtime == null)
                _buildUnavailable()
              else
                _buildRuntime(runtime),
              const SizedBox(height: 10),
              Divider(height: 1, color: AppTheme.borderColor.withAlpha(80)),
              const SizedBox(height: 9),
              _buildBilling(billing),
              const SizedBox(height: 7),
              _buildFooter(runtime, billing),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final name = widget.nodeName?.trim();
    final title = name == null || name.isEmpty ? 'DMIT 实时监控' : 'DMIT · $name';
    return Row(
      children: [
        const Icon(
          Icons.shield_outlined,
          size: 17,
          color: AppTheme.primaryNeon,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            _service.connected
                ? Icons.monitor_heart
                : Icons.monitor_heart_outlined,
            size: 17,
          ),
          tooltip: _service.connected ? 'SSH 实时监控已连接' : '重新连接 SSH 实时监控',
          color: _service.connected
              ? AppTheme.successGreen
              : AppTheme.textSecondary,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          onPressed: () => unawaited(_service.reconnect()),
        ),
      ],
    );
  }

  Widget _buildUnavailable() {
    final message = !_service.initialized
        ? '正在启动 SSH 实时监控…'
        : (_service.error ?? '正在等待服务器实时数据…');
    return _notice(
      message,
      _service.configured ? AppTheme.warningOrange : AppTheme.textSecondary,
    );
  }

  Widget _buildRuntime(DmitRuntimeInfo runtime) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '实时运行状态',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.circle, size: 7, color: AppTheme.successGreen),
            const SizedBox(width: 4),
            Text(
              _hms(runtime.receivedAt.toLocal()),
              style: const TextStyle(color: AppTheme.textHint, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _kv('CPU', '${runtime.cpuPercent.toStringAsFixed(1)}%'),
            _kv('Load', runtime.load1.toStringAsFixed(2)),
            _kv('运行', DmitRuntimeInfo.formatUptime(runtime.uptimeSeconds)),
          ],
        ),
        const SizedBox(height: 7),
        _runtimeUsage(
          '内存',
          runtime.memoryUsedBytes,
          runtime.memoryTotalBytes,
          runtime.memoryFraction,
        ),
        const SizedBox(height: 6),
        _runtimeUsage(
          '磁盘',
          runtime.diskUsedBytes,
          runtime.diskTotalBytes,
          runtime.diskFraction,
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _kv('实时下载', DmitRuntimeInfo.formatRate(runtime.rxBytesPerSecond)),
            _kv('实时上传', DmitRuntimeInfo.formatRate(runtime.txBytesPerSecond)),
            _kv('网卡', runtime.networkInterface),
          ],
        ),
      ],
    );
  }

  Widget _runtimeUsage(String label, int used, int total, double fraction) {
    final value = fraction.clamp(0.0, 1.0);
    final color = value >= 0.9
        ? AppTheme.errorRed
        : (value >= 0.75 ? AppTheme.warningOrange : AppTheme.successGreen);
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textHint, fontSize: 11),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: AppTheme.borderColor.withAlpha(80),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${DmitRuntimeInfo.formatBytes(used)} / '
          '${DmitRuntimeInfo.formatBytes(total)}',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildBilling(DmitBillingInfo? billing) {
    if (billing == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Monthly Transfer',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          _notice(
            _billingService.error ?? '等待 DMIT 后台计费同步…',
            AppTheme.warningOrange,
          ),
        ],
      );
    }
    final usage = billing.usageFraction;
    final reset = billing.nextResetAt(DateTime.now());
    final resetDays = billing.resetDaysAt(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Monthly Transfer',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _transferMethodLabel(billing.transferMethod),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              billing.suspendWhenExceeded ? Icons.block : Icons.speed,
              size: 13,
              color: billing.suspendWhenExceeded
                  ? AppTheme.errorRed
                  : AppTheme.warningOrange,
            ),
            const SizedBox(width: 5),
            Text(
              billing.suspendWhenExceeded
                  ? 'Suspend when Exceeded'
                  : 'Provider overage policy',
              style: TextStyle(
                color: billing.suspendWhenExceeded
                    ? AppTheme.errorRed
                    : AppTheme.warningOrange,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          billing.isUnmetered
              ? '${DmitBillingInfo.formatMb(billing.usedMb)} / Unlimited'
              : '${DmitBillingInfo.formatMb(billing.usedMb)} / '
                    '${DmitBillingInfo.formatMb(billing.limitMb)}',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (usage != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usage,
              minHeight: 6,
              backgroundColor: AppTheme.borderColor.withAlpha(80),
              valueColor: AlwaysStoppedAnimation<Color>(
                usage >= 0.95
                    ? AppTheme.errorRed
                    : (usage >= 0.8
                          ? AppTheme.warningOrange
                          : AppTheme.successGreen),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          billing.isUnmetered
              ? 'Free Unlimited'
              : 'Free ${DmitBillingInfo.formatMb(billing.remainingMb)}',
          style: const TextStyle(
            color: AppTheme.successGreen,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (reset != null) ...[
          const SizedBox(height: 2),
          Text(
            'Next reset ${_ymd(reset)}'
            '${resetDays == null ? '' : ' · in $resetDays days'}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter(DmitRuntimeInfo? runtime, DmitBillingInfo? billing) {
    final sshText = runtime != null
        ? 'SSH 已连接 · 每 5 秒更新 · ${runtime.networkInterface}'
        : (_service.configured ? 'SSH 正在重连' : 'SSH 尚未配置');
    final billingUpdated = _billingService.updatedAt;
    final billingText = billing != null && billingUpdated != null
        ? 'DMIT 计费 ${_hms(billingUpdated.toLocal())}'
        : 'DMIT 计费等待同步';
    return Text(
      '$sshText · $billingText',
      style: TextStyle(
        color: runtime != null && billing != null
            ? AppTheme.textHint
            : AppTheme.warningOrange,
        fontSize: 10,
      ),
    );
  }

  Widget _kv(String key, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 11),
        children: [
          TextSpan(
            text: '$key ',
            style: const TextStyle(color: AppTheme.textHint),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 14, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 11)),
        ),
      ],
    );
  }

  static String _hms(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';

  static String _ymd(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _transferMethodLabel(String method) => switch (method) {
    'both' => 'Bidirection',
    'max' => 'Max(IN, OUT)',
    _ => method,
  };
}
