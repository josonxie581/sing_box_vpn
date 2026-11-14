import 'dart:convert';

/// Shared validation and sing-box fields for the newer proxy protocols.
class ModernProtocolOptions {
  static Map<String, dynamic> hysteria2(Map<String, dynamic> settings) {
    final result = <String, dynamic>{};
    for (final key in [
      'server_ports',
      'hop_interval',
      'hop_interval_max',
      'bbr_profile',
      'disable_chrome_parrot',
      'realm',
    ]) {
      final value = settings[key];
      if (value != null && value != '') result[key] = value;
    }
    final obfs = settings['obfs'];
    if (obfs is Map && obfs.isNotEmpty) {
      if (!['salamander', 'gecko'].contains(obfs['type'])) {
        throw const FormatException('不支持的 Hysteria 2 混淆类型');
      }
      if ((obfs['password'] ?? '').toString().isEmpty) {
        throw const FormatException('混淆密码不能为空');
      }
      result['obfs'] = Map<String, dynamic>.from(obfs);
    }
    if (result['realm'] != null && result['server_ports'] != null) {
      throw const FormatException('Realm 穿透与端口跳跃不能同时启用');
    }
    if (result['realm'] != null) {
      final realm = result['realm'];
      if (realm is! Map ||
          (realm['server_url'] ?? '').toString().isEmpty ||
          (realm['realm_id'] ?? '').toString().isEmpty ||
          realm['stun_servers'] == null) {
        throw const FormatException(
          'Realm 需要 server_url、realm_id 和 stun_servers',
        );
      }
    }
    if (result['bbr_profile'] != null &&
        ![
          'standard',
          'conservative',
          'aggressive',
        ].contains(result['bbr_profile'])) {
      throw const FormatException('无效的 BBR 档位');
    }
    return result;
  }

  static Map<String, dynamic> outbound(
    String type,
    String tag,
    String server,
    int port,
    Map<String, dynamic> settings,
  ) {
    final result = <String, dynamic>{
      'type': type,
      'tag': tag,
      'server': server,
      'server_port': port,
    };
    if (type == 'snell') {
      final version = int.tryParse('${settings['version'] ?? 6}');
      if (version != 4 && version != 6) {
        throw const FormatException('Snell 出站仅支持 v4 或 v6');
      }
      final psk = (settings['psk'] ?? settings['password'] ?? '').toString();
      if (psk.isEmpty) throw const FormatException('Snell PSK 不能为空');
      if (version == 6 &&
          (utf8.encode(psk).length < 12 || utf8.encode(psk).length > 255)) {
        throw const FormatException('Snell v6 PSK 必须为 12–255 字节');
      }
      result.addAll({'version': version, 'psk': psk});
      for (final key in ['userkey', 'reuse']) {
        if (settings[key] != null && settings[key] != '') {
          result[key] = settings[key];
        }
      }
      if (version == 6) {
        final mode = settings['mode'] ?? 'default';
        if (!['default', 'unshaped', 'unsafe-raw'].contains(mode)) {
          throw const FormatException('无效的 Snell v6 流量整形模式');
        }
        result['mode'] = mode;
      } else {
        for (final key in ['obfs_mode', 'obfs_host']) {
          if (settings[key] != null && settings[key] != '') {
            result[key] = settings[key];
          }
        }
      }
    } else if (type == 'naive') {
      result.addAll({
        'username': settings['username'] ?? '',
        'password': settings['password'] ?? '',
        'quic': settings['quic'] == true,
        'tls': {
          'enabled': true,
          'server_name': (settings['sni'] ?? '').toString().isEmpty
              ? server
              : settings['sni'],
          if (settings['skipCertVerify'] == true) 'insecure': true,
        },
      });
      for (final key in [
        'udp_over_tcp',
        'extra_headers',
        'quic_congestion_control',
      ]) {
        if (settings[key] != null && settings[key] != '') {
          result[key] = settings[key];
        }
      }
    } else {
      throw FormatException('Unsupported protocol: $type');
    }
    return result;
  }

  /// Naive uses naive+https / naive+quic. snell:// is this client's URI format.
  static Map<String, dynamic> parseSettings(Uri uri, String type) {
    final q = uri.queryParameters;
    final userInfo = uri.userInfo.split(':');
    if (type == 'naive') {
      return {
        'username': Uri.decodeComponent(userInfo.first),
        'password': Uri.decodeComponent(userInfo.skip(1).join(':')),
        'quic': uri.scheme == 'naive+quic',
        if (q['sni'] != null) 'sni': q['sni'],
      };
    }
    return {
      'psk': Uri.decodeComponent(uri.userInfo),
      'version': int.parse(q['version'] ?? '6'),
      'mode': q['mode'] ?? 'default',
      if (q['userkey'] != null) 'userkey': q['userkey'],
      if (q['obfs_mode'] != null) 'obfs_mode': q['obfs_mode'],
      if (q['obfs_host'] != null) 'obfs_host': q['obfs_host'],
      'reuse': q['reuse'] == '1' || q['reuse'] == 'true',
    };
  }
}
