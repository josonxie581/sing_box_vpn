import 'dart:io';
import 'package:yaml/yaml.dart';
import '../models/vpn_config.dart';

/// YAML 配置解析服务
/// 支持 Clash 配置格式和其他 YAML 格式的代理配置
class YamlParserService {
  /// 从 YAML 文件解析代理配置
  static Future<List<VPNConfig>> parseYamlFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('文件不存在: $filePath');
      }

      final content = await file.readAsString();
      return parseYamlContent(content);
    } catch (e) {
      print('解析 YAML 文件失败: $e');
      return [];
    }
  }

  /// 从 YAML 内容字符串解析代理配置
  static List<VPNConfig> parseYamlContent(String content) {
    try {
      final yamlDoc = loadYaml(content);
      if (yamlDoc is! YamlMap) {
        throw Exception('无效的 YAML 格式');
      }

      // 检查是否为 Clash 配置格式
      if (yamlDoc.containsKey('proxies')) {
        return _parseClashFormat(yamlDoc);
      }

      // 其他 YAML 格式处理可以在这里添加

      return [];
    } catch (e) {
      print('解析 YAML 内容失败: $e');
      return [];
    }
  }

  /// 解析 Clash 配置格式
  static List<VPNConfig> _parseClashFormat(YamlMap yamlDoc) {
    final configs = <VPNConfig>[];

    // 获取代理列表
    final proxies = yamlDoc['proxies'];
    if (proxies is! YamlList) {
      return configs;
    }

    for (final proxy in proxies) {
      if (proxy is! YamlMap) continue;

      try {
        final config = _parseClashProxy(proxy);
        if (config != null) {
          configs.add(config);
        }
      } catch (e) {
        print('解析代理配置失败: $e');
        // 继续处理其他配置，不因单个配置失败而停止
        continue;
      }
    }

    return configs;
  }

  /// 解析单个 Clash 代理配置
  static VPNConfig? _parseClashProxy(YamlMap proxy) {
    final name = proxy['name']?.toString() ?? '';
    final type = proxy['type']?.toString().toLowerCase() ?? '';
    final server = proxy['server']?.toString() ?? '';
    final port = _parseInt(proxy['port']) ?? 0;

    // 调试信息
    print('解析代理配置: name=$name, type=$type, server=$server, port=$port');

    if (name.isEmpty || type.isEmpty || server.isEmpty || port <= 0) {
      print('配置无效: name=$name, type=$type, server=$server, port=$port');
      return null;
    }

    // 根据不同协议类型解析配置
    switch (type) {
      case 'trojan':
        return _parseTrojanConfig(name, server, port, proxy);
      case 'shadowsocks':
      case 'ss':
        return _parseShadowsocksConfig(name, server, port, proxy);
      case 'vmess':
        return _parseVmessConfig(name, server, port, proxy);
      case 'vless':
        return _parseVlessConfig(name, server, port, proxy);
      case 'hysteria2':
      case 'hy2':
        return _parseHysteria2Config(name, server, port, proxy);
      case 'hysteria':
        return _parseHysteriaConfig(name, server, port, proxy);
      case 'tuic':
        return _parseTuicConfig(name, server, port, proxy);
      case 'anytls':
        return _parseAnyTlsConfig(name, server, port, proxy);
      case 'socks5':
      case 'socks':
        return _parseSocksConfig(name, server, port, proxy);
      case 'http':
        return _parseHttpConfig(name, server, port, proxy);
      case 'shadowtls':
        return _parseShadowTlsConfig(name, server, port, proxy);
      default:
        print('不支持的代理类型: $type');
        return null;
    }
  }

  /// 解析 AnyTLS 配置
  static VPNConfig _parseAnyTlsConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final password =
        proxy['password']?.toString() ?? proxy['pwd']?.toString() ?? '';
    final sni =
        proxy['sni']?.toString() ?? proxy['servername']?.toString() ?? server;
    final skipCertVerify = _parseBool(proxy['skip-cert-verify']) ?? false;

    // 解析 ALPN
    List<String>? alpn;
    final alpnData = proxy['alpn'];
    if (alpnData is YamlList) {
      alpn = alpnData.map((e) => e.toString()).toList();
    }

    final settings = <String, dynamic>{
      'password': password,
      'sni': sni,
      'skipCertVerify': skipCertVerify,
      if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
    };

    return VPNConfig(
      name: name,
      type: 'anytls',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 Trojan 配置
  static VPNConfig _parseTrojanConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final password = proxy['password']?.toString() ?? '';
    final sni = proxy['sni']?.toString() ?? server;
    final skipCertVerify = _parseBool(proxy['skip-cert-verify']) ?? false;

    // 解析 ALPN
    List<String>? alpn;
    final alpnData = proxy['alpn'];
    if (alpnData is YamlList) {
      alpn = alpnData.map((e) => e.toString()).toList();
    }

    final settings = <String, dynamic>{
      'password': password,
      'sni': sni,
      'skipCertVerify': skipCertVerify,
    };

    if (alpn != null && alpn.isNotEmpty) {
      settings['alpn'] = alpn;
    }

    return VPNConfig(
      name: name,
      type: 'trojan',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 Shadowsocks 配置
  static VPNConfig _parseShadowsocksConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final password = proxy['password']?.toString() ?? '';
    final cipher =
        proxy['cipher']?.toString() ??
        proxy['method']?.toString() ??
        'aes-256-gcm';

    final settings = <String, dynamic>{'password': password, 'method': cipher};

    return VPNConfig(
      name: name,
      type: 'shadowsocks',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 VMess 配置
  static VPNConfig _parseVmessConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final uuid = proxy['uuid']?.toString() ?? '';
    final alterId = _parseInt(proxy['alterId']) ?? _parseInt(proxy['aid']) ?? 0;
    final security =
        proxy['cipher']?.toString() ?? proxy['security']?.toString() ?? 'auto';
    final network = proxy['network']?.toString() ?? 'tcp';
    final tls = proxy['tls']?.toString() ?? proxy['ws-tls']?.toString() ?? '';

    final settings = <String, dynamic>{
      'uuid': uuid,
      'alterId': alterId,
      'security': security,
      'network': network,
      'tls': tls,
    };

    // WebSocket 配置
    if (network == 'ws') {
      final wsPath =
          proxy['ws-path']?.toString() ?? proxy['path']?.toString() ?? '/';
      final wsHeaders = proxy['ws-headers'] ?? proxy['headers'];

      settings['wsPath'] = wsPath;
      if (wsHeaders is YamlMap) {
        settings['wsHeaders'] = Map<String, String>.from(wsHeaders);
      }
    }

    // gRPC 配置
    if (network == 'grpc') {
      final grpcServiceName =
          proxy['grpc-service-name']?.toString() ??
          proxy['serviceName']?.toString() ??
          '';
      if (grpcServiceName.isNotEmpty) {
        settings['grpcServiceName'] = grpcServiceName;
      }
    }

    return VPNConfig(
      name: name,
      type: 'vmess',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 VLESS 配置
  static VPNConfig _parseVlessConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final uuid = proxy['uuid']?.toString() ?? '';
    final flow = proxy['flow']?.toString() ?? '';
    final network = proxy['network']?.toString() ?? 'tcp';
    final security = proxy['tls']?.toString() ?? '';
    final sni =
        proxy['servername']?.toString() ?? proxy['sni']?.toString() ?? server;

    final settings = <String, dynamic>{
      'uuid': uuid,
      'network': network,
      'tlsEnabled': security.isNotEmpty,
      'sni': sni,
    };

    if (flow.isNotEmpty) {
      settings['flow'] = flow;
    }

    // Reality 配置
    if (proxy.containsKey('reality-opts')) {
      final realityOpts = proxy['reality-opts'];
      if (realityOpts is YamlMap) {
        settings['realityEnabled'] = true;
        settings['realityPublicKey'] =
            realityOpts['public-key']?.toString() ?? '';
        settings['realityShortId'] = realityOpts['short-id']?.toString() ?? '';
      }
    }

    return VPNConfig(
      name: name,
      type: 'vless',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 Hysteria2 配置
  static VPNConfig _parseHysteria2Config(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final password = proxy['password']?.toString() ?? '';
    final sni = proxy['sni']?.toString() ?? server;
    final skipCertVerify = _parseBool(proxy['skip-cert-verify']) ?? false;

    final settings = <String, dynamic>{
      'password': password,
      'sni': sni,
      'skipCertVerify': skipCertVerify,
    };

    return VPNConfig(
      name: name,
      type: 'hysteria2',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 Hysteria v1 配置
  static VPNConfig _parseHysteriaConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final password =
        proxy['auth_str']?.toString() ?? proxy['password']?.toString() ?? '';
    final authB64 = proxy['auth']?.toString() ?? '';
    final sni = proxy['sni']?.toString() ?? server;
    final skipCertVerify = _parseBool(proxy['skip-cert-verify']) ?? false;

    // 带宽：支持 up_mbps/down_mbps 数字，或 up/down 字符串
    final upMbps = _parseInt(proxy['up_mbps']);
    final downMbps = _parseInt(proxy['down_mbps']);
    final up = proxy['up']?.toString() ?? '';
    final down = proxy['down']?.toString() ?? '';

    // ALPN
    List<String>? alpn;
    final alpnData = proxy['alpn'];
    if (alpnData is YamlList) {
      alpn = alpnData.map((e) => e.toString()).toList();
    }

    final settings = <String, dynamic>{
      if (password.isNotEmpty) 'password': password,
      if (authB64.isNotEmpty) 'auth': authB64,
      'sni': sni,
      'skipCertVerify': skipCertVerify,
      if (upMbps != null) 'up_mbps': upMbps,
      if (downMbps != null) 'down_mbps': downMbps,
      if (up.isNotEmpty) 'up': up,
      if (down.isNotEmpty) 'down': down,
      if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
    };

    return VPNConfig(
      name: name,
      type: 'hysteria',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 TUIC 配置
  static VPNConfig _parseTuicConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final uuid = proxy['uuid']?.toString() ?? '';
    final password = proxy['password']?.toString() ?? '';
    final sni = proxy['sni']?.toString() ?? server;
    final skipCertVerify = _parseBool(proxy['skip-cert-verify']) ?? false;

    final settings = <String, dynamic>{
      'uuid': uuid,
      'password': password,
      'sni': sni,
      'skipCertVerify': skipCertVerify,
    };

    return VPNConfig(
      name: name,
      type: 'tuic',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 SOCKS 配置
  static VPNConfig _parseSocksConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final username = proxy['username']?.toString() ?? '';
    final password = proxy['password']?.toString() ?? '';
    final tls = _parseBool(proxy['tls']) ?? false;

    final settings = <String, dynamic>{'tlsEnabled': tls};

    if (username.isNotEmpty) {
      settings['username'] = username;
    }
    if (password.isNotEmpty) {
      settings['password'] = password;
    }

    return VPNConfig(
      name: name,
      type: 'socks',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 HTTP 配置
  static VPNConfig _parseHttpConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final username = proxy['username']?.toString() ?? '';
    final password = proxy['password']?.toString() ?? '';
    final tls = _parseBool(proxy['tls']) ?? false;

    final settings = <String, dynamic>{'tlsEnabled': tls};

    if (username.isNotEmpty) {
      settings['username'] = username;
    }
    if (password.isNotEmpty) {
      settings['password'] = password;
    }

    return VPNConfig(
      name: name,
      type: 'http',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 解析 ShadowTLS 配置
  static VPNConfig _parseShadowTlsConfig(
    String name,
    String server,
    int port,
    YamlMap proxy,
  ) {
    final version = _parseInt(proxy['version']) ?? 1;
    final password = proxy['password']?.toString() ?? '';
    final sni =
        proxy['sni']?.toString() ?? proxy['servername']?.toString() ?? server;
    final skipCertVerify = _parseBool(proxy['skip-cert-verify']) ?? false;

    List<String>? alpn;
    final alpnData = proxy['alpn'];
    if (alpnData is YamlList) {
      alpn = alpnData.map((e) => e.toString()).toList();
    }

    final settings = <String, dynamic>{
      'version': version,
      if (password.isNotEmpty) 'password': password,
      'sni': sni,
      'skipCertVerify': skipCertVerify,
      if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
    };

    return VPNConfig(
      name: name,
      type: 'shadowtls',
      server: server,
      port: port,
      settings: settings,
    );
  }

  /// 安全解析整数
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// 安全解析布尔值
  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == 'yes' || lower == '1';
    }
    if (value is int) return value != 0;
    return null;
  }

  /// 获取支持的协议类型列表
  static List<String> getSupportedProtocols() {
    return [
      'trojan',
      'shadowsocks',
      'ss',
      'vmess',
      'vless',
      'hysteria',
      'hysteria2',
      'hy2',
      'tuic',
      'anytls',
      'socks5',
      'socks',
      'http',
      'shadowtls',
    ];
  }

  /// 验证 YAML 文件是否为有效的代理配置文件
  static Future<bool> isValidProxyConfigFile(String filePath) async {
    try {
      final configs = await parseYamlFile(filePath);
      return configs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
