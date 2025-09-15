import 'dart:convert';
import 'proxy_mode.dart';
import '../services/ruleset_manager.dart';

/// VPN 配置模型
class VPNConfig {
  static int _idSeq = 0; // 用于避免同一微秒内大量创建导致的重复
  final String id;
  final String name;
  final String type; // shadowsocks, vmess, trojan, etc.
  final String server;
  final int port;
  final Map<String, dynamic> settings;
  final bool enabled;

  // 便利访问器
  String get password => settings['password'] ?? '';
  String get uuid => settings['uuid'] ?? '';
  int? get alterId => settings['alterId'];
  String get security => settings['security'] ?? '';
  String get network => settings['network'] ?? '';
  String get transport => settings['transport'] ?? '';
  String get path => settings['path'] ?? '';
  String get host => settings['host'] ?? '';
  String get alpn => settings['alpn'] is List
      ? (settings['alpn'] as List).join(',')
      : settings['alpn']?.toString() ?? '';
  bool get skipCertVerify => settings['skipCertVerify'] ?? false;
  String get remarks => settings['remarks'] ?? '';

  VPNConfig({
    String? id,
    required this.name,
    required this.type,
    required this.server,
    required this.port,
    required this.settings,
    this.enabled = true,
  }) : id = id ?? _generateId();

  static String _generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch; // 更高精度
    final seq = _idSeq = (_idSeq + 1) & 0xFFFF; // 16bit 循环
    return '${ts.toRadixString(36)}-${seq.toRadixString(36)}';
  }

  /// 从 JSON 创建
  factory VPNConfig.fromJson(Map<String, dynamic> json) {
    return VPNConfig(
      id: json['id'],
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      server: json['server'] ?? '',
      port: json['port'] ?? 0,
      settings: json['settings'] ?? {},
      enabled: json['enabled'] ?? true,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'server': server,
      'port': port,
      'settings': settings,
      'enabled': enabled,
    };
  }

  /// 生成 sing-box 配置
  Map<String, dynamic> toSingBoxConfig({
    ProxyMode mode = ProxyMode.rule,
    int? localPort,
    bool useTun = false,
    bool tunStrictRoute = false,
    String? preferredTunStack,
    bool enableClashApi = false,
    int clashApiPort = 9090,
    String clashApiSecret = '',
    int? tunMtu,
    bool enableIpv6 = false,
  }) {
    // 使用规则集管理器生成完整配置
    return RulesetManager.generateSingBoxConfig(
      proxyConfig: _generateOutbound(),
      mode: mode,
      localPort: localPort,
      useTun: useTun,
      tunStrictRoute: tunStrictRoute,
      preferredTunStack: preferredTunStack,
      enableClashApi: enableClashApi,
      clashApiPort: clashApiPort,
      clashApiSecret: clashApiSecret,
      tunMtu: tunMtu,
      enableIpv6: enableIpv6,
    );
  }

  /// 生成出站配置
  Map<String, dynamic> _generateOutbound() {
    switch (type.toLowerCase()) {
      case 'shadowsocks':
        return {
          "type": "shadowsocks",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          "method": settings['method'] ?? "aes-256-gcm",
          "password": settings['password'] ?? "",
        };

      case 'shadowsocks-2022':
        return {
          "type": "shadowsocks",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          "method": settings['method'] ?? "2022-blake3-aes-128-gcm",
          "password": settings['password'] ?? "",
        };

      case 'vmess':
        final useTls = (settings['tls']?.toString().toLowerCase() == 'tls');
        final outbound = <String, dynamic>{
          "type": "vmess",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          "uuid": settings['uuid'] ?? "",
          "security": settings['security'] ?? "auto",
          "alter_id": settings['alterId'] ?? 0,
        };
        final transport = _generateTransport();
        if (transport != null) outbound["transport"] = transport;
        if (useTls) {
          outbound["tls"] = {
            "enabled": true,
            if ((settings['host'] ?? '').toString().isNotEmpty)
              "server_name": settings['host'],
          };
        }
        return outbound;

      case 'vless':
        return {
          "type": "vless",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          "uuid": settings['uuid'] ?? "",
          // 注意：sing-box 的 vless 出站不需要也不支持 "encryption" 字段（xray 才需要），
          // 这里不要写入，否则会报错：json: unknown field "encryption"。
          if ((settings['flow'] ?? '').toString().isNotEmpty)
            "flow": settings['flow'],
          if (_generateTransport() != null) "transport": _generateTransport(),
          if (settings['tlsEnabled'] == true)
            "tls": {
              "enabled": true,
              // 若未提供 sni，兜底使用服务器域名
              "server_name": (settings['sni'] ?? server),
              if (settings['alpn'] is List) "alpn": settings['alpn'],
              // 若提供了指纹则开启 uTLS 并设置 fingerprint（需要 with_utls 构建）
              if ((settings['fingerprint'] ?? '').toString().isNotEmpty)
                "utls": {
                  "enabled": true,
                  "fingerprint": settings['fingerprint'],
                },
              if (settings['realityEnabled'] == true)
                "reality": {
                  "enabled": true,
                  if ((settings['realityPublicKey'] ?? '')
                      .toString()
                      .isNotEmpty)
                    "public_key": settings['realityPublicKey'],
                  if ((settings['realityShortId'] ?? '').toString().isNotEmpty)
                    "short_id": settings['realityShortId'],
                },
            },
        };

      case 'trojan':
        return {
          "type": "trojan",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          "password": settings['password'] ?? "",
          "tls": {
            "enabled": true,
            "server_name": settings['sni'] ?? server,
            "insecure": settings['skipCertVerify'] ?? false,
            if (settings['alpn'] is List) "alpn": settings['alpn'],
          },
        };

      case 'hysteria2':
        return {
          "type": "hysteria2",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          "password": settings['password'] ?? "",
          "tls": {
            "enabled": true,
            "server_name": settings['sni'] ?? server,
            "insecure": settings['skipCertVerify'] ?? false,
            if (settings['alpn'] is List) "alpn": settings['alpn'],
          },
        };

      case 'tuic':
        return {
          "type": "tuic",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          if ((settings['uuid'] ?? '').toString().isNotEmpty)
            "uuid": settings['uuid'],
          if ((settings['password'] ?? '').toString().isNotEmpty)
            "password": settings['password'],
          if ((settings['udpRelayMode'] ?? '').toString().isNotEmpty)
            "udp_relay_mode": settings['udpRelayMode'],
          if ((settings['congestion'] ?? '').toString().isNotEmpty)
            "congestion_control": settings['congestion'],
          "tls": {
            "enabled": true,
            // 若未提供 sni，兜底使用服务器域名
            "server_name": (settings['sni'] ?? server),
            // 是否跳过证书校验
            if (settings['skipCertVerify'] == true) "insecure": true,
            if (settings['alpn'] is List) "alpn": settings['alpn'],
          },
        };

      case 'socks':
        return {
          "type": "socks",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          if ((settings['username'] ?? '').toString().isNotEmpty)
            "username": settings['username'],
          if ((settings['password'] ?? '').toString().isNotEmpty)
            "password": settings['password'],
          if (settings['tlsEnabled'] == true)
            "tls": {
              "enabled": true,
              if ((settings['sni'] ?? '').toString().isNotEmpty)
                "server_name": settings['sni'],
            },
        };

      case 'http':
        return {
          "type": "http",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          if ((settings['username'] ?? '').toString().isNotEmpty)
            "username": settings['username'],
          if ((settings['password'] ?? '').toString().isNotEmpty)
            "password": settings['password'],
          if (settings['tlsEnabled'] == true)
            "tls": {
              "enabled": true,
              if ((settings['sni'] ?? '').toString().isNotEmpty)
                "server_name": settings['sni'],
            },
        };

      case 'wireguard':
        return {
          "type": "wireguard",
          "tag": "proxy",
          "server": server,
          "server_port": port,
          "private_key": settings['privateKey'] ?? "",
          "peer_public_key": settings['peerPublicKey'] ?? "",
          if (settings['localAddress'] is List)
            "local_address": settings['localAddress'],
          if (settings['dns'] is List) "dns": settings['dns'],
          if ((settings['reserved'] ?? '').toString().isNotEmpty)
            "reserved": settings['reserved'],
          if (settings['mtu'] != null) "mtu": settings['mtu'],
        };

      default:
        return {"type": "direct", "tag": "proxy"};
    }
  }

  /// 生成传输层配置
  Map<String, dynamic>? _generateTransport() {
    final network = settings['network'] ?? 'tcp';

    switch (network) {
      case 'ws':
        return {
          "type": "ws",
          "path": settings['wsPath'] ?? "/",
          "headers": settings['wsHeaders'] ?? {},
        };

      case 'grpc':
        return {
          "type": "grpc",
          "service_name": settings['grpcServiceName'] ?? "",
        };

      case 'http':
        return {
          "type": "http",
          "host": settings['httpHost'] ?? [],
          "path": settings['httpPath'] ?? "/",
        };

      default:
        return null;
    }
  }

  /// 从订阅链接解析
  static VPNConfig? fromSubscriptionLink(String link) {
    try {
      final s = link.trim();
      final lower = s.toLowerCase();
      // 解析不同类型的订阅链接（大小写不敏感）
      if (lower.startsWith('ss://')) {
        return _parseShadowsocks(s);
      } else if (lower.startsWith('vmess://')) {
        return _parseVmess(s);
      } else if (lower.startsWith('vless://')) {
        return _parseVless(s);
      } else if (lower.startsWith('trojan://')) {
        return _parseTrojan(link);
      } else if (lower.startsWith('tuic://')) {
        return _parseTuic(s);
      } else if (lower.startsWith('hysteria2://') ||
          lower.startsWith('hy2://')) {
        return _parseHysteria2(s);
      }

      return null;
    } catch (e) {
      print('解析订阅链接失败: $e');
      return null;
    }
  }

  /// 解析 TUIC v5 链接
  static VPNConfig? _parseTuic(String link) {
    try {
      final uri = Uri.parse(link);
      final qp = uri.queryParameters;

      // userInfo 可能为 "uuid:password" 或 "password"
      String uuid = '';
      String password = '';
      if (uri.userInfo.contains(':')) {
        final parts = uri.userInfo.split(':');
        if (parts.length >= 2) {
          uuid = parts[0];
          password = parts[1];
        }
      } else if (uri.userInfo.isNotEmpty) {
        password = uri.userInfo;
      }
      // query 中的补充/覆盖
      uuid = (qp['uuid'] ?? uuid).trim();
      password = (qp['password'] ?? qp['pwd'] ?? password).trim();

      final server = uri.host;
      final port = uri.hasPort ? uri.port : 443;
      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'TUIC';

      // 可选项
      List<String>? alpn;
      final alpnStr = (qp['alpn'] ?? '').trim();
      if (alpnStr.isNotEmpty) {
        alpn = alpnStr
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      final relay = (qp['udp-relay-mode'] ?? qp['udpRelayMode'] ?? 'native')
          .toString();
      final cong =
          (qp['congestion'] ?? qp['congestion_control'] ?? qp['cc'] ?? 'bbr')
              .toString();
      final sni = (qp['sni'] ?? '').toString().trim();
      final versionStr = (qp['version'] ?? '').toString().trim();
      final version = int.tryParse(versionStr.isEmpty ? '5' : versionStr) ?? 5;

      // 证书校验（allowInsecure / insecure）
      final insecureStr = (qp['insecure'] ?? qp['allowInsecure'] ?? '0')
          .toString()
          .trim();
      final skipCertVerify =
          insecureStr == '1' ||
          insecureStr.toLowerCase() == 'true' ||
          insecureStr.toLowerCase() == 'yes';

      final settings = <String, dynamic>{
        if (uuid.isNotEmpty) 'uuid': uuid,
        if (password.isNotEmpty) 'password': password,
        'version': version,
        if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
        'udpRelayMode': relay,
        'congestion': cong,
        if (sni.isNotEmpty) 'sni': sni,
        'skipCertVerify': skipCertVerify,
      };

      return VPNConfig(
        name: name,
        type: 'tuic',
        server: server,
        port: port,
        settings: settings,
      );
    } catch (e) {
      return null;
    }
  }

  /// 解析 Hysteria2 / hy2 链接
  static VPNConfig? _parseHysteria2(String link) {
    try {
      final uri = Uri.parse(link);
      final qp = uri.queryParameters;

      final server = uri.host;
      final port = uri.hasPort ? uri.port : 443;
      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'Hysteria2';

      String password = '';
      if (uri.userInfo.isNotEmpty) password = uri.userInfo;
      password = (qp['password'] ?? qp['pwd'] ?? password).trim();

      // TLS 相关
      final sni = (qp['sni'] ?? qp['serverName'] ?? '').trim();
      final insecure = (qp['insecure'] ?? qp['allowInsecure'] ?? '0').trim();
      final skipCertVerify =
          insecure == '1' ||
          insecure.toLowerCase() == 'true' ||
          insecure.toLowerCase() == 'yes';

      // ALPN
      List<String>? alpn;
      final alpnStr = (qp['alpn'] ?? '').trim();
      if (alpnStr.isNotEmpty) {
        alpn = alpnStr
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      final settings = <String, dynamic>{
        'password': password,
        'skipCertVerify': skipCertVerify,
        if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
        if (sni.isNotEmpty) 'sni': sni,
      };

      return VPNConfig(
        name: name,
        type: 'hysteria2',
        server: server,
        port: port,
        settings: settings,
      );
    } catch (e) {
      return null;
    }
  }

  /// 解析 VLESS / VLESS-REALITY 链接
  static VPNConfig? _parseVless(String link) {
    try {
      final uri = Uri.parse(link);
      final qp = uri.queryParameters;

      // UUID 在 userInfo 或 id 参数中
      final uuid = uri.userInfo.isNotEmpty ? uri.userInfo : (qp['id'] ?? '');

      // 名称在 fragment
      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'VLESS';

      // 服务器与端口（缺省端口按 443 兜底）
      final server = uri.host;
      final port = uri.hasPort ? uri.port : 443;

      // 传输类型（tcp/ws/grpc/http...）
      final network = (qp['type'] ?? 'tcp').toLowerCase();

      // TLS/REALITY/XTLS
      final security = (qp['security'] ?? '').toLowerCase();
      final tlsEnabled =
          security == 'tls' || security == 'reality' || security == 'xtls';
      final realityEnabled = security == 'reality';

      // SNI 与相关 REALITY 参数
      final sni = (qp['sni'] ?? qp['host'] ?? qp['serverName'] ?? '').trim();
      final fingerprint = (qp['fp'] ?? qp['fingerprint'] ?? '').trim();
      final publicKey = (qp['pbk'] ?? qp['publicKey'] ?? qp['public_key'] ?? '')
          .trim();
      final shortId = (qp['sid'] ?? qp['shortId'] ?? qp['short_id'] ?? '')
          .trim();

      // 传输细节（path/host/grpc service name 等）
      final path = (qp['path'] ?? qp['spx'] ?? '/').toString();
      final hostHeader = (qp['host'] ?? qp['authority'] ?? '').toString();
      final grpcServiceName = (qp['serviceName'] ?? qp['service_name'] ?? '')
          .toString();

      // ALPN（可选）
      List<String>? alpn;
      if ((qp['alpn'] ?? '').isNotEmpty) {
        alpn = qp['alpn']!
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      // XTLS flow / 加密方式（vless 一般为 none）
      final flow = (qp['flow'] ?? '').toString().trim();
      final encryption = (qp['encryption'] ?? '').toString().trim();

      final settings = <String, dynamic>{
        'uuid': uuid,
        'network': network,
        'tlsEnabled': tlsEnabled,
        if (flow.isNotEmpty) 'flow': flow,
        if (encryption.isNotEmpty) 'encryption': encryption,
        if (sni.isNotEmpty) 'sni': sni,
        'realityEnabled': realityEnabled,
        if (realityEnabled && publicKey.isNotEmpty)
          'realityPublicKey': publicKey,
        if (realityEnabled && shortId.isNotEmpty) 'realityShortId': shortId,
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
        if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
      };

      switch (network) {
        case 'ws':
          settings['wsPath'] = path.isEmpty ? '/' : path;
          if (hostHeader.isNotEmpty) {
            settings['wsHeaders'] = {'Host': hostHeader};
          }
          break;
        case 'grpc':
          if (grpcServiceName.isNotEmpty) {
            settings['grpcServiceName'] = grpcServiceName;
          }
          break;
        case 'http':
          final hosts = hostHeader
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (hosts.isNotEmpty) settings['httpHost'] = hosts;
          settings['httpPath'] = path.isEmpty ? '/' : path;
          break;
        default:
          // tcp: 无额外设置
          break;
      }

      return VPNConfig(
        name: name,
        type: 'vless',
        server: server,
        port: port,
        settings: settings,
      );
    } catch (e) {
      return null;
    }
  }

  /// 解析 Shadowsocks 链接
  static VPNConfig? _parseShadowsocks(String link) {
    try {
      final uri = Uri.parse(link);
      // 形态 A：ss://BASE64(method:password@server:port)#name
      // 形态 B：ss://method:password@server:port#name
      try {
        final encoded = uri.host;
        final decoded = utf8.decode(base64.decode(encoded));
        final parts = decoded.split('@');
        if (parts.length == 2) {
          final authParts = parts[0].split(':');
          final serverParts = parts[1].split(':');
          if (authParts.length == 2 && serverParts.length == 2) {
            return VPNConfig(
              name: uri.fragment.isNotEmpty
                  ? Uri.decodeComponent(uri.fragment)
                  : 'Shadowsocks',
              type: 'shadowsocks',
              server: serverParts[0],
              port: int.parse(serverParts[1]),
              settings: {'method': authParts[0], 'password': authParts[1]},
            );
          }
        }
      } catch (_) {
        // 忽略，尝试未编码形态
      }

      // 未编码形态（B）
      if (uri.userInfo.isNotEmpty && uri.host.isNotEmpty && uri.port > 0) {
        final auth = uri.userInfo.split(':');
        if (auth.length == 2) {
          return VPNConfig(
            name: uri.fragment.isNotEmpty
                ? Uri.decodeComponent(uri.fragment)
                : 'Shadowsocks',
            type: 'shadowsocks',
            server: uri.host,
            port: uri.port,
            settings: {'method': auth[0], 'password': auth[1]},
          );
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 解析 VMess 链接
  static VPNConfig? _parseVmess(String link) {
    try {
      final encoded = link.substring(8).trim(); // 移除 vmess://

      // 兼容多种 Base64 变体（含 URL-safe / 缺失填充 / 含换行）
      String? _decodeBase64Flexible(String s) {
        String cleaned = s.replaceAll('\r', '').replaceAll('\n', '').trim();
        String tryDecode(String content, {bool urlSafe = false}) {
          final bytes = (urlSafe ? base64Url : base64).decode(content);
          return utf8.decode(bytes);
        }

        // 1) 直接解码
        try {
          return tryDecode(cleaned);
        } catch (_) {}

        // 2) URL-safe 替换并补齐 padding
        String normalized = cleaned.replaceAll('-', '+').replaceAll('_', '/');
        final mod = normalized.length % 4;
        if (mod != 0)
          normalized = normalized.padRight(normalized.length + (4 - mod), '=');
        try {
          return tryDecode(normalized);
        } catch (_) {}

        // 3) 直接用 base64Url 尝试
        try {
          final mod2 = cleaned.length % 4;
          final padded = mod2 == 0
              ? cleaned
              : cleaned.padRight(cleaned.length + (4 - mod2), '=');
          return tryDecode(padded, urlSafe: true);
        } catch (_) {}

        return null;
      }

      final decoded = _decodeBase64Flexible(encoded);
      if (decoded == null) return null;

      // 若解码后不是 JSON，可能是「订阅内容」或再次封装的 vmess 列表
      final trimmed = decoded.trim();
      if (!trimmed.startsWith('{')) {
        // 尝试从文本中提取第一个 vmess:// 链接并递归解析
        final vmessLinks = RegExp(
          r"vmess://[A-Za-z0-9_\-=/+\r\n]+",
        ).allMatches(trimmed).map((m) => m.group(0)!).toList();
        for (final l in vmessLinks) {
          final cfg = fromSubscriptionLink(l.trim());
          if (cfg != null) return cfg;
        }
        // 不是 JSON 也找不到 vmess:// 链接
        return null;
      }

      final json = jsonDecode(trimmed);

      // 兼容字段：aid/scy/net/path/host/tls/ps/add/port/id
      final name = (json['ps'] ?? '').toString().trim();
      final server = (json['add'] ?? '').toString().trim();
      final portRaw = json['port'];
      final id = (json['id'] ?? '').toString();
      final aidRaw = json['aid'];
      final security = (json['scy'] ?? 'auto').toString();
      final network = (json['net'] ?? 'tcp').toString();
      final path = (json['path'] ?? '/').toString();
      final host = (json['host'] ?? '').toString();
      final tls = (json['tls'] ?? '').toString();

      // 端口可能包含非数字字符，尽量提取数字
      int _parsePort(dynamic raw) {
        final s = raw?.toString() ?? '';
        final m = RegExp(r"\d+").firstMatch(s);
        if (m != null) {
          final n = int.tryParse(m.group(0)!);
          if (n != null && n > 0 && n <= 65535) return n;
        }
        return 0;
      }

      final port = _parsePort(portRaw);
      final alterId = int.tryParse(aidRaw?.toString() ?? '') ?? 0;

      return VPNConfig(
        name: name.isNotEmpty ? name : 'VMess',
        type: 'vmess',
        server: server,
        port: port,
        settings: {
          'uuid': id,
          'alterId': alterId,
          'security': security,
          'network': network,
          // 为 UI 与传输/证书共同使用，存两份
          'path': path,
          'wsPath': path,
          if (host.isNotEmpty) 'host': host,
          if (host.isNotEmpty) 'wsHeaders': {'Host': host},
          'tls': tls,
        },
      );
    } catch (e) {
      return null;
    }
  }

  /// 解析 Trojan 链接
  static VPNConfig? _parseTrojan(String link) {
    try {
      final uri = Uri.parse(link);

      return VPNConfig(
        name: uri.fragment.isNotEmpty
            ? Uri.decodeComponent(uri.fragment)
            : 'Trojan',
        type: 'trojan',
        server: uri.host,
        port: uri.port,
        settings: {
          'password': uri.userInfo,
          'sni': uri.queryParameters['sni'] ?? uri.host,
          'skipCertVerify': uri.queryParameters['allowInsecure'] == '1',
        },
      );
    } catch (e) {
      return null;
    }
  }
}
