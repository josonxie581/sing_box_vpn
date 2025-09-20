import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import '../models/vpn_config.dart';
import '../models/subscription_info.dart';

/// 远程订阅服务
/// 负责从远程URL下载和解析订阅内容
class RemoteSubscriptionService {
  static final RemoteSubscriptionService _instance = RemoteSubscriptionService._internal();
  factory RemoteSubscriptionService() => _instance;
  RemoteSubscriptionService._internal();

  /// 用户代理字符串
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

  /// 下载并解析远程订阅
  /// [url] 订阅链接
  /// [userAgent] 可选的用户代理字符串
  /// [timeout] 请求超时时间（毫秒）
  /// 返回解析后的配置列表和订阅信息
  Future<SubscriptionResult> fetchSubscription(
    String url, {
    String? userAgent,
    int timeout = 30000,
  }) async {
    if (!_isValidUrl(url)) {
      throw ArgumentError('无效的订阅链接: $url');
    }

    try {
      final client = http.Client();
      final headers = {
        'User-Agent': userAgent ?? 'clash-verge-rev/1.7.7',  // 使用clash-verge-rev的User-Agent
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Accept-Encoding': 'identity', // 不使用压缩，避免解析问题
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Connection': 'keep-alive',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'cross-site',
      };

      print('[远程订阅] 开始下载: $url');

      final response = await client
          .get(Uri.parse(url), headers: headers)
          .timeout(Duration(milliseconds: timeout));

      client.close();

      if (response.statusCode != 200) {
        throw HttpException('HTTP错误: ${response.statusCode} ${response.reasonPhrase}');
      }

      print('[远程订阅] 下载完成，状态码: ${response.statusCode}，内容长度: ${response.body.length}');

      // 检查响应体开头（可能是JSON格式包含订阅信息）
      final bodyStart = response.body.length > 500 ? response.body.substring(0, 500) : response.body;
      print('[远程订阅] 响应体开头: $bodyStart');

      // 解析订阅信息（从响应头获取）
      print('[远程订阅] 响应头信息:');
      response.headers.forEach((key, value) {
        print('[远程订阅] $key: $value');
      });
      final subscriptionInfo = _parseSubscriptionInfo(response.headers);
      print('[远程订阅] 从头部解析到的订阅信息: $subscriptionInfo');

      // 如果头部没有信息，尝试从响应体解析
      final bodySubscriptionInfo = subscriptionInfo ?? _parseSubscriptionInfoFromBody(response.body);
      print('[远程订阅] 最终订阅信息: $bodySubscriptionInfo');

      // 解析订阅内容
      final configs = await _parseSubscriptionContent(response.body, url);

      print('[远程订阅] 解析完成，配置数量: ${configs.length}');

      return SubscriptionResult(
        configs: configs,
        subscriptionInfo: bodySubscriptionInfo,
        originalUrl: url,
        rawContent: response.body,
      );

    } on TimeoutException {
      throw TimeoutException('请求超时，请检查网络连接', Duration(milliseconds: timeout));
    } on SocketException {
      throw SocketException('网络连接失败，请检查网络设置');
    } on FormatException catch (e) {
      throw FormatException('订阅内容格式错误: ${e.message}');
    } catch (e) {
      print('[远程订阅] 下载失败: $e');
      rethrow;
    }
  }

  /// 批量获取多个订阅
  Future<List<SubscriptionResult>> fetchMultipleSubscriptions(
    List<String> urls, {
    String? userAgent,
    int timeout = 30000,
  }) async {
    final results = <SubscriptionResult>[];

    for (final url in urls) {
      try {
        final result = await fetchSubscription(url, userAgent: userAgent, timeout: timeout);
        results.add(result);
      } catch (e) {
        print('[远程订阅] 批量获取失败 $url: $e');
        // 继续处理其他订阅，不中断整个流程
      }
    }

    return results;
  }

  /// 验证URL是否有效
  bool _isValidUrl(String url) {
    if (url.isEmpty) return false;

    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// 解析订阅信息（从HTTP头部）
  SubscriptionInfo? _parseSubscriptionInfo(Map<String, String> headers) {
    try {
      // 查找订阅信息头
      String? subscriptionUserinfo;

      // 尝试不同的头部字段名（参考clash-verge-rev的实现）
      for (final key in headers.keys) {
        final lowerKey = key.toLowerCase();
        if (lowerKey == 'subscription-userinfo' ||
            lowerKey == 'subscription-userInfo' ||
            lowerKey == 'x-subscription-userinfo' ||
            key == 'Subscription-Userinfo') {  // clash-verge-rev使用的确切格式
          subscriptionUserinfo = headers[key];
          print('[远程订阅] 找到订阅信息头: $key = $subscriptionUserinfo');
          break;
        }
      }

      if (subscriptionUserinfo == null) {
        return null;
      }

      // 解析订阅用户信息
      final parts = subscriptionUserinfo.split(';');
      int? upload, download, total, expire;

      for (final part in parts) {
        final kv = part.trim().split('=');
        if (kv.length == 2) {
          final key = kv[0].trim().toLowerCase();
          final value = int.tryParse(kv[1].trim());

          switch (key) {
            case 'upload':
              upload = value;
              break;
            case 'download':
              download = value;
              break;
            case 'total':
              total = value;
              break;
            case 'expire':
              expire = value;
              break;
          }
        }
      }

      return SubscriptionInfo(
        upload: upload ?? 0,
        download: download ?? 0,
        total: total ?? 0,
        expire: expire,
      );
    } catch (e) {
      print('[远程订阅] 解析订阅信息失败: $e');
      return null;
    }
  }

  /// 解析订阅内容
  Future<List<VPNConfig>> _parseSubscriptionContent(String content, String sourceUrl) async {
    final configs = <VPNConfig>[];

    try {
      // 尝试base64解码
      String decodedContent = content;
      if (_isBase64(content)) {
        try {
          decodedContent = utf8.decode(base64.decode(content));
          print('[远程订阅] Base64解码成功');
        } catch (e) {
          print('[远程订阅] Base64解码失败，使用原始内容: $e');
          decodedContent = content;
        }
      }

      int processed = 0;

      // 检测内容格式
      bool isClashYaml = _isClashYamlFormat(decodedContent);
      print('[远程订阅] 内容格式检测: ${isClashYaml ? 'Clash YAML' : '代理链接列表'}');

      if (isClashYaml) {
        // 解析 Clash YAML 格式
        processed = await _parseClashYaml(decodedContent, configs, sourceUrl);
      } else {
        // 解析代理链接列表格式
        final lines = decodedContent.split('\n');
        print('[远程订阅] 调试：内容总行数: ${lines.length}');
        print('[远程订阅] 调试：前5行内容:');
        for (int i = 0; i < lines.length && i < 5; i++) {
          final line = lines[i].trim();
          if (line.isNotEmpty) {
            print('[远程订阅] 行${i + 1}: ${line.length > 100 ? line.substring(0, 100) + '...' : line}');
          }
        }

        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty) continue;

          try {
            // 尝试解析单个配置链接
            final config = VPNConfig.fromSubscriptionLink(trimmedLine);
            if (config != null) {
              // 添加订阅来源信息
              config.subscriptionUrl = sourceUrl;
              configs.add(config);
              processed++;
            }
          } catch (e) {
            print('[远程订阅] 解析配置失败: $trimmedLine, 错误: $e');
            // 继续解析其他配置
          }
        }
      }

      if (isClashYaml) {
        print('[远程订阅] Clash YAML 处理完成，成功解析: $processed');
      } else {
        final lines = decodedContent.split('\n');
        print('[远程订阅] 处理完成，总行数: ${lines.length}，成功解析: $processed');
      }

    } catch (e) {
      print('[远程订阅] 解析订阅内容失败: $e');
      throw FormatException('订阅内容解析失败: $e');
    }

    return configs;
  }

  /// 检查是否为base64编码
  bool _isBase64(String content) {
    // 简单检查：base64字符串通常只包含字母数字和+/=字符
    final base64Pattern = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');

    // 检查是否符合base64模式且长度合理
    if (!base64Pattern.hasMatch(content.replaceAll(RegExp(r'\s'), ''))) {
      return false;
    }

    // 尝试解码一小部分来验证
    try {
      final sample = content.replaceAll(RegExp(r'\s'), '');
      if (sample.length < 4) return false;

      base64.decode(sample.substring(0, (sample.length ~/ 4) * 4));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 更新订阅（重新下载并替换配置）
  Future<SubscriptionUpdateResult> updateSubscription(
    String url,
    List<VPNConfig> oldConfigs, {
    String? userAgent,
    int timeout = 30000,
  }) async {
    try {
      // 下载新的订阅内容
      final result = await fetchSubscription(url, userAgent: userAgent, timeout: timeout);

      // 比较新旧配置
      final addedConfigs = <VPNConfig>[];
      final updatedConfigs = <VPNConfig>[];
      final removedConfigs = <VPNConfig>[];

      // 找出新增和更新的配置
      for (final newConfig in result.configs) {
        final existingConfig = oldConfigs.firstWhere(
          (old) => old.name == newConfig.name && old.server == newConfig.server,
          orElse: () => VPNConfig.placeholder(),
        );

        if (existingConfig.name == 'placeholder') {
          addedConfigs.add(newConfig);
        } else if (!_configsEqual(existingConfig, newConfig)) {
          updatedConfigs.add(newConfig);
        }
      }

      // 找出被移除的配置
      for (final oldConfig in oldConfigs) {
        if (oldConfig.subscriptionUrl == url) {
          final stillExists = result.configs.any(
            (newConfig) => newConfig.name == oldConfig.name && newConfig.server == oldConfig.server,
          );
          if (!stillExists) {
            removedConfigs.add(oldConfig);
          }
        }
      }

      return SubscriptionUpdateResult(
        subscriptionResult: result,
        addedConfigs: addedConfigs,
        updatedConfigs: updatedConfigs,
        removedConfigs: removedConfigs,
      );

    } catch (e) {
      print('[远程订阅] 更新订阅失败: $e');
      rethrow;
    }
  }

  /// 比较两个配置是否相等
  bool _configsEqual(VPNConfig config1, VPNConfig config2) {
    return config1.name == config2.name &&
        config1.type == config2.type &&
        config1.server == config2.server &&
        config1.port == config2.port &&
        _mapsEqual(config1.settings, config2.settings);
  }

  /// 比较两个Map是否相等
  bool _mapsEqual(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) return false;

    for (final key in map1.keys) {
      if (!map2.containsKey(key) || map1[key] != map2[key]) {
        return false;
      }
    }

    return true;
  }

  /// 从响应体解析订阅信息（某些服务商可能在body中提供JSON格式的订阅信息）
  SubscriptionInfo? _parseSubscriptionInfoFromBody(String body) {
    try {
      // 尝试解析JSON格式的响应体
      if (body.trim().startsWith('{')) {
        final jsonData = json.decode(body);

        // 检查常见的订阅信息字段
        if (jsonData is Map<String, dynamic>) {
          int? upload, download, total, expire;

          // 尝试不同的字段名称组合
          upload = _extractNumericValue(jsonData, ['upload', 'uploadBytes', 'used_upload']);
          download = _extractNumericValue(jsonData, ['download', 'downloadBytes', 'used_download']);
          total = _extractNumericValue(jsonData, ['total', 'totalBytes', 'total_bandwidth']);
          expire = _extractNumericValue(jsonData, ['expire', 'expiry', 'expire_time', 'expired_at']);

          if (upload != null || download != null || total != null || expire != null) {
            print('[远程订阅] 从响应体解析订阅信息: upload=$upload, download=$download, total=$total, expire=$expire');
            return SubscriptionInfo(
              upload: upload ?? 0,
              download: download ?? 0,
              total: total ?? 0,
              expire: expire,
            );
          }
        }
      }

      return null;
    } catch (e) {
      print('[远程订阅] 从响应体解析订阅信息失败: $e');
      return null;
    }
  }

  /// 从JSON对象中提取数值（尝试多个可能的字段名）
  int? _extractNumericValue(Map<String, dynamic> json, List<String> possibleKeys) {
    for (final key in possibleKeys) {
      final value = json[key];
      if (value != null) {
        if (value is int) return value;
        if (value is double) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }

  /// 检测是否为 Clash YAML 格式
  bool _isClashYamlFormat(String content) {
    // 检查典型的 Clash 配置字段
    return content.contains('mixed-port:') ||
           content.contains('allow-lan:') ||
           content.contains('mode:') ||
           content.contains('proxies:') ||
           content.contains('proxy-groups:') ||
           content.contains('rules:');
  }

  /// 解析 Clash YAML 格式订阅
  Future<int> _parseClashYaml(String yamlContent, List<VPNConfig> configs, String sourceUrl) async {
    int processed = 0;

    try {
      print('[远程订阅] 开始解析 Clash YAML 格式');

      // 解析 YAML
      final dynamic yamlDoc = loadYaml(yamlContent);
      if (yamlDoc is! Map) {
        print('[远程订阅] YAML 格式错误：根对象不是 Map');
        return 0;
      }

      final Map<String, dynamic> yamlMap = Map<String, dynamic>.from(yamlDoc);

      // 获取 proxies 数组
      final dynamic proxiesData = yamlMap['proxies'];
      if (proxiesData == null) {
        print('[远程订阅] 未找到 proxies 字段');
        return 0;
      }

      if (proxiesData is! List) {
        print('[远程订阅] proxies 字段不是数组格式');
        return 0;
      }

      final List<dynamic> proxies = proxiesData;
      print('[远程订阅] 找到 ${proxies.length} 个代理配置');

      // 转换每个代理配置
      for (int i = 0; i < proxies.length; i++) {
        try {
          final dynamic proxyData = proxies[i];
          if (proxyData is! Map) {
            print('[远程订阅] 代理配置 $i 不是 Map 格式，跳过');
            continue;
          }

          final Map<String, dynamic> proxy = Map<String, dynamic>.from(proxyData);
          final VPNConfig? config = _convertClashProxyToVPNConfig(proxy, sourceUrl);

          if (config != null) {
            configs.add(config);
            processed++;
          }
        } catch (e) {
          print('[远程订阅] 解析代理配置 $i 失败: $e');
        }
      }

      print('[远程订阅] Clash YAML 解析完成，成功解析: $processed/${proxies.length}');

    } catch (e) {
      print('[远程订阅] 解析 Clash YAML 失败: $e');
    }

    return processed;
  }

  /// 将 Clash 代理配置转换为 VPNConfig
  VPNConfig? _convertClashProxyToVPNConfig(Map<String, dynamic> proxy, String sourceUrl) {
    try {
      final String? type = proxy['type']?.toString().toLowerCase();
      final String? name = proxy['name']?.toString();
      final String? server = proxy['server']?.toString();
      final dynamic portValue = proxy['port'];

      if (type == null || name == null || server == null || portValue == null) {
        print('[远程订阅] 代理配置缺少必要字段: type=$type, name=$name, server=$server, port=$portValue');
        return null;
      }

      final int port = portValue is int ? portValue : int.tryParse(portValue.toString()) ?? 0;
      if (port <= 0) {
        print('[远程订阅] 无效端口: $portValue');
        return null;
      }

      // 根据不同类型转换
      switch (type) {
        case 'ss':
          return _convertShadowsocks(proxy, name, server, port, sourceUrl);
        case 'vmess':
          return _convertVmess(proxy, name, server, port, sourceUrl);
        case 'vless':
          return _convertVless(proxy, name, server, port, sourceUrl);
        case 'trojan':
          return _convertTrojan(proxy, name, server, port, sourceUrl);
        case 'hysteria':
          return _convertHysteria(proxy, name, server, port, sourceUrl);
        case 'hysteria2':
          return _convertHysteria2(proxy, name, server, port, sourceUrl);
        default:
          print('[远程订阅] 不支持的代理类型: $type');
          return null;
      }
    } catch (e) {
      print('[远程订阅] 转换代理配置失败: $e');
      return null;
    }
  }

  /// 转换 Shadowsocks 配置
  VPNConfig? _convertShadowsocks(Map<String, dynamic> proxy, String name, String server, int port, String sourceUrl) {
    final String? password = proxy['password']?.toString();
    final String? cipher = proxy['cipher']?.toString();

    if (password == null || cipher == null) {
      print('[远程订阅] SS 配置缺少必要字段');
      return null;
    }

    return VPNConfig(
      name: name,
      type: 'shadowsocks',
      server: server,
      port: port,
      settings: {
        'password': password,
        'method': cipher,
      },
      subscriptionUrl: sourceUrl,
      lastUpdated: DateTime.now(),
    );
  }

  /// 转换 VMess 配置
  VPNConfig? _convertVmess(Map<String, dynamic> proxy, String name, String server, int port, String sourceUrl) {
    final String? uuid = proxy['uuid']?.toString();
    final int? alterId = proxy['alterId'] ?? proxy['aid'];
    final String? cipher = proxy['cipher']?.toString() ?? 'auto';

    if (uuid == null) {
      print('[远程订阅] VMess 配置缺少 UUID');
      return null;
    }

    final settings = <String, dynamic>{
      'uuid': uuid,
      'alterId': alterId ?? 0,
      'security': cipher,
    };

    // 传输协议设置
    final String? network = proxy['network']?.toString();
    if (network != null) {
      settings['network'] = network;

      // WebSocket 设置
      if (network == 'ws') {
        final Map<String, dynamic>? wsOpts = proxy['ws-opts'] is Map ? Map<String, dynamic>.from(proxy['ws-opts']) : null;
        if (wsOpts != null) {
          if (wsOpts['path'] != null) settings['path'] = wsOpts['path'];
          if (wsOpts['headers'] != null) settings['headers'] = wsOpts['headers'];
        }
      }

      // gRPC 设置
      if (network == 'grpc') {
        final Map<String, dynamic>? grpcOpts = proxy['grpc-opts'] is Map ? Map<String, dynamic>.from(proxy['grpc-opts']) : null;
        if (grpcOpts != null && grpcOpts['grpc-service-name'] != null) {
          settings['serviceName'] = grpcOpts['grpc-service-name'];
        }
      }
    }

    // TLS 设置
    final bool? tls = proxy['tls'];
    if (tls == true) {
      settings['tls'] = true;
      final String? sni = proxy['sni']?.toString();
      if (sni != null) settings['sni'] = sni;
    }

    return VPNConfig(
      name: name,
      type: 'vmess',
      server: server,
      port: port,
      settings: settings,
      subscriptionUrl: sourceUrl,
      lastUpdated: DateTime.now(),
    );
  }

  /// 转换 VLESS 配置
  VPNConfig? _convertVless(Map<String, dynamic> proxy, String name, String server, int port, String sourceUrl) {
    final String? uuid = proxy['uuid']?.toString();

    if (uuid == null) {
      print('[远程订阅] VLESS 配置缺少 UUID');
      return null;
    }

    final settings = <String, dynamic>{
      'uuid': uuid,
      'flow': proxy['flow']?.toString() ?? '',
    };

    // 传输协议设置
    final String? network = proxy['network']?.toString();
    if (network != null) {
      settings['network'] = network;

      if (network == 'ws') {
        final Map<String, dynamic>? wsOpts = proxy['ws-opts'] is Map ? Map<String, dynamic>.from(proxy['ws-opts']) : null;
        if (wsOpts != null) {
          if (wsOpts['path'] != null) settings['path'] = wsOpts['path'];
          if (wsOpts['headers'] != null) settings['headers'] = wsOpts['headers'];
        }
      }
    }

    // TLS 设置
    final bool? tls = proxy['tls'];
    if (tls == true) {
      settings['tls'] = true;
      final String? sni = proxy['sni']?.toString();
      if (sni != null) settings['sni'] = sni;
    }

    return VPNConfig(
      name: name,
      type: 'vless',
      server: server,
      port: port,
      settings: settings,
      subscriptionUrl: sourceUrl,
      lastUpdated: DateTime.now(),
    );
  }

  /// 转换 Trojan 配置
  VPNConfig? _convertTrojan(Map<String, dynamic> proxy, String name, String server, int port, String sourceUrl) {
    final String? password = proxy['password']?.toString();

    if (password == null) {
      print('[远程订阅] Trojan 配置缺少密码');
      return null;
    }

    final settings = <String, dynamic>{
      'password': password,
    };

    // SNI 设置
    final String? sni = proxy['sni']?.toString();
    if (sni != null) settings['sni'] = sni;

    // 跳过证书验证
    final bool? skipCertVerify = proxy['skip-cert-verify'];
    if (skipCertVerify != null) settings['skip-cert-verify'] = skipCertVerify;

    return VPNConfig(
      name: name,
      type: 'trojan',
      server: server,
      port: port,
      settings: settings,
      subscriptionUrl: sourceUrl,
      lastUpdated: DateTime.now(),
    );
  }

  /// 转换 Hysteria 配置
  VPNConfig? _convertHysteria(Map<String, dynamic> proxy, String name, String server, int port, String sourceUrl) {
    final String? auth = proxy['auth_str']?.toString() ?? proxy['auth']?.toString();

    if (auth == null) {
      print('[远程订阅] Hysteria 配置缺少认证信息');
      return null;
    }

    final settings = <String, dynamic>{
      'auth': auth,
      'up_mbps': proxy['up']?.toString() ?? '10',
      'down_mbps': proxy['down']?.toString() ?? '50',
    };

    // SNI 设置
    final String? sni = proxy['sni']?.toString();
    if (sni != null) settings['sni'] = sni;

    // ALPN 设置
    final dynamic alpn = proxy['alpn'];
    if (alpn != null) {
      if (alpn is List) {
        settings['alpn'] = alpn.join(',');
      } else {
        settings['alpn'] = alpn.toString();
      }
    }

    return VPNConfig(
      name: name,
      type: 'hysteria',
      server: server,
      port: port,
      settings: settings,
      subscriptionUrl: sourceUrl,
      lastUpdated: DateTime.now(),
    );
  }

  /// 转换 Hysteria2 配置
  VPNConfig? _convertHysteria2(Map<String, dynamic> proxy, String name, String server, int port, String sourceUrl) {
    final String? password = proxy['password']?.toString();

    if (password == null) {
      print('[远程订阅] Hysteria2 配置缺少密码');
      return null;
    }

    final settings = <String, dynamic>{
      'password': password,
      'up_mbps': proxy['up']?.toString() ?? '10',
      'down_mbps': proxy['down']?.toString() ?? '50',
    };

    // SNI 设置
    final String? sni = proxy['sni']?.toString();
    if (sni != null) settings['sni'] = sni;

    return VPNConfig(
      name: name,
      type: 'hysteria2',
      server: server,
      port: port,
      settings: settings,
      subscriptionUrl: sourceUrl,
      lastUpdated: DateTime.now(),
    );
  }
}

/// 订阅下载结果
class SubscriptionResult {
  final List<VPNConfig> configs;
  final SubscriptionInfo? subscriptionInfo;
  final String originalUrl;
  final String? rawContent; // 添加原始内容字段

  SubscriptionResult({
    required this.configs,
    this.subscriptionInfo,
    required this.originalUrl,
    this.rawContent,
  });
}

/// 订阅更新结果
class SubscriptionUpdateResult {
  final SubscriptionResult subscriptionResult;
  final List<VPNConfig> addedConfigs;
  final List<VPNConfig> updatedConfigs;
  final List<VPNConfig> removedConfigs;

  SubscriptionUpdateResult({
    required this.subscriptionResult,
    required this.addedConfigs,
    required this.updatedConfigs,
    required this.removedConfigs,
  });

  bool get hasChanges => addedConfigs.isNotEmpty || updatedConfigs.isNotEmpty || removedConfigs.isNotEmpty;
}