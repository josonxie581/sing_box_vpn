import '../models/vpn_config.dart';

/// The same payload is used for clipboard sharing and QR codes.
String hysteria2ShareLink(VPNConfig config) {
  final settings = config.settings;
  final params = <String, String>{};
  for (final key in [
    'sni',
    'up_mbps',
    'down_mbps',
    'up',
    'down',
    'hop_interval',
    'hop_interval_max',
    'bbr_profile',
    'disable_chrome_parrot',
  ]) {
    if (settings[key] != null) params[key] = settings[key].toString();
  }
  if (settings['skipCertVerify'] == true) params['insecure'] = '1';
  if (settings['alpn'] is List) {
    params['alpn'] = (settings['alpn'] as List).join(',');
  }
  if (settings['server_ports'] is List) {
    params['mport'] = (settings['server_ports'] as List).join(',');
  }
  final obfs = settings['obfs'];
  if (obfs is Map) {
    params['obfs'] = obfs['type'].toString();
    params['obfs-password'] = (obfs['password'] ?? '').toString();
    for (final key in ['min_packet_size', 'max_packet_size']) {
      if (obfs[key] != null) params[key] = obfs[key].toString();
    }
  }
  final host = config.server.contains(':') && !config.server.startsWith('[')
      ? '[${config.server}]'
      : config.server;
  final password = Uri.encodeComponent((settings['password'] ?? '').toString());
  final query = params.entries
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');
  return 'hysteria2://$password@$host:${config.port}'
      '${query.isEmpty ? '' : '?$query'}#${Uri.encodeComponent(config.name)}';
}
