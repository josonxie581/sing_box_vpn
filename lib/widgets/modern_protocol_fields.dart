import 'dart:convert';
import 'package:flutter/material.dart';

/// Edits protocol-specific values while retaining fields from imported nodes.
class ModernProtocolFields extends StatefulWidget {
  const ModernProtocolFields({
    super.key,
    required this.type,
    required this.values,
  });
  final String type;
  final Map<String, dynamic> values;

  @override
  State<ModernProtocolFields> createState() => _ModernProtocolFieldsState();
}

class _ModernProtocolFieldsState extends State<ModernProtocolFields> {
  Map<String, dynamic> get values => widget.values;

  Widget field(
    String key,
    String label, {
    bool secret = false,
    bool required = false,
    bool integer = false,
    bool list = false,
    bool json = false,
  }) {
    final value = values[key];
    final initial = json && value != null
        ? jsonEncode(value)
        : value is List
        ? value.join(',')
        : value?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('${widget.type}:$key'),
        initialValue: initial,
        obscureText: secret,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (text) {
          final textValue = text?.trim() ?? '';
          if (required && textValue.isEmpty) return '请填写$label';
          if (integer &&
              textValue.isNotEmpty &&
              (int.tryParse(textValue) == null || int.parse(textValue) < 0)) {
            return '请输入非负整数';
          }
          if (json && textValue.isNotEmpty) {
            try {
              if (jsonDecode(textValue) is! Map) return '请输入 JSON 对象';
            } catch (_) {
              return 'JSON 格式不正确';
            }
          }
          return null;
        },
        onSaved: (text) {
          final v = secret ? (text ?? '') : (text ?? '').trim();
          if (v.isEmpty) {
            values.remove(key);
            return;
          }
          values[key] = json
              ? jsonDecode(v)
              : integer
              ? int.parse(v)
              : list
              ? v
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : v;
        },
      ),
    );
  }

  Widget choice(
    String key,
    String label,
    List<String> options,
    String fallback,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      key: ValueKey('${widget.type}:$key'),
      initialValue: options.contains(values[key]?.toString())
          ? values[key].toString()
          : fallback,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: (v) => setState(() => values[key] = v),
      onSaved: (v) => values[key] = v,
    ),
  );

  Widget toggle(String key, String label) => SwitchListTile(
    title: Text(label),
    value: values[key] == true,
    onChanged: (v) => setState(() => values[key] = v),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.type == 'snell') {
      return Column(
        children: [
          field('psk', '预共享密钥 PSK', secret: true, required: true),
          choice('version', '协议版本', ['4', '6'], '6'),
          field('userkey', '用户密钥（可选）', secret: true),
          if ('${values['version'] ?? 6}' == '6')
            choice('mode', '流量整形', [
              'default',
              'unshaped',
              'unsafe-raw',
            ], 'default')
          else ...[
            choice('obfs_mode', '混淆方式', ['none', 'http', 'tls'], 'none'),
            field('obfs_host', '混淆域名（可选）'),
          ],
          toggle('reuse', '复用连接'),
        ],
      );
    }
    if (widget.type == 'naive') {
      return Column(
        children: [
          field('username', '用户名', required: true),
          field('password', '密码', secret: true, required: true),
          field('sni', 'TLS 服务器名称（可选）'),
          toggle('quic', '使用 HTTP/3（QUIC）'),
          toggle('skipCertVerify', '跳过证书验证（仅用于测试）'),
          toggle('udp_over_tcp', 'UDP over TCP（需要服务端支持）'),
          const Text('默认验证服务器证书。HTTP/3 和 UDP 转发需要服务端支持。'),
        ],
      );
    }
    if (widget.type != 'hysteria2') return const SizedBox.shrink();
    return Column(
      children: [
        field('sni', 'TLS 服务器名称（可选）'),
        field('up_mbps', '上传带宽 Mbps（留空使用 BBR）', integer: true),
        field('down_mbps', '下载带宽 Mbps（留空使用 BBR）', integer: true),
        choice('bbr_profile', 'BBR 档位', [
          'standard',
          'conservative',
          'aggressive',
        ], 'standard'),
        field('server_ports', '跳跃端口（逗号分隔，如 443,20000:30000）', list: true),
        field('hop_interval', '最小跳跃间隔（如 30s）'),
        field('hop_interval_max', '最大跳跃间隔（如 60s）'),
        choice(
          '_obfsType',
          '混淆方式',
          ['none', 'salamander', 'gecko'],
          (values['obfs'] as Map?)?['type']?.toString() ?? 'none',
        ),
        if ((values['_obfsType'] ??
                (values['obfs'] as Map?)?['type'] ??
                'none') !=
            'none') ...[
          field('_obfsPassword', '混淆密码', secret: true, required: true),
          if ((values['_obfsType'] ?? (values['obfs'] as Map?)?['type']) ==
              'gecko') ...[
            field('_minPacketSize', 'Gecko 最小包长（可选）', integer: true),
            field('_maxPacketSize', 'Gecko 最大包长（可选）', integer: true),
          ],
        ],
        toggle('disable_chrome_parrot', '关闭 Chrome QUIC 指纹模仿'),
        ExpansionTile(
          maintainState: true,
          title: const Text('NAT 穿透（Realm 高级配置）'),
          children: [
            const Text(
              '填写服务端提供的 Realm JSON，包含 server_url、realm_id、stun_servers；可选 token。',
            ),
            field('realm', 'Realm 配置（JSON，可选）', json: true),
          ],
        ),
      ],
    );
  }
}
