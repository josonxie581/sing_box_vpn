import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

/// DNS 配置管理器
class DnsManager {
  static final DnsManager _instance = DnsManager._internal();
  factory DnsManager() => _instance;
  DnsManager._internal();

  // 规则集定义如需变更：Route 中的 rule_set 提供，这里不再单独维护本地路径常量
  // DNS 配置项
  bool _tunHijackDns = true; // 是否在 TUN 下劫持本地系统 DNS 请求
  bool _resolveInboundDomains = false; // 是否反向解析入站连接的远程地址（reverse_mapping）
  String _testDomain = 'gstatic.com'; // 用于测试连通性的默认测试域名
  String _ttl = '1 h'; // 缓存 TTL 字符串表达
  bool _enableDnsRouting = false; // 是否启用基于 DNS 的路由细分
  bool _enableEcs = true; // 是否启用 EDNS Client Subnet（当前未显式使用，可预留）
  String _proxyResolver = 'FakeIP'; // 代理侧解析策略 (FakeIP / Remote 等)
  bool _strictRoute = false; // DNS严格路由，确保DNS查询严格按照路由规则进行
  bool _enableIpv6 = false; // 是否启用IPv6支持（影响TUN接口配置）
  int _localPort = 7890; // 本地混合代理端口

  // 运行时探测结果：实际链路是否可用IPv6（优先与用户开关共同决定最终行为）
  bool _ipv6RuntimeAvailable = false;
  DateTime? _lastIpv6CheckTime;

  // 静态IP映射配置
  List<StaticIpMapping> _staticIpMappings = [];

  // DNS 服务器配置（初始内置）
  List<DnsServer> _dnsServers = [
    // 使用 UDP 避免某些 IP DoH 的证书 / SNI 问题
    DnsServer(
      name: 'Google',
      address: '8.8.8.8',
      type: DnsServerType.udp,
      detour: 'proxy',
      enabled: true,
    ),
    DnsServer(
      name: 'Cloudflare',
      address: '1.1.1.1',
      type: DnsServerType.udp,
      detour: 'proxy',
      enabled: false, // 暂时禁用，避免连接问题
    ),
    DnsServer(
      name: '阿里DNS',
      address: '223.5.5.5',
      type: DnsServerType.udp,
      detour: 'direct',
      enabled: true,
    ),
    DnsServer(
      name: '腾讯DNS',
      address: '119.29.29.29',
      type: DnsServerType.udp,
      detour: 'direct',
      enabled: false, // 禁用备用直连DNS
    ),
  ];

  // Getters
  bool get tunHijackDns => _tunHijackDns;
  bool get resolveInboundDomains => _resolveInboundDomains;
  String get testDomain => _testDomain;
  String get ttl => _ttl;
  bool get enableDnsRouting => _enableDnsRouting;
  bool get enableEcs => _enableEcs;
  String get proxyResolver => _proxyResolver;
  bool get strictRoute => _strictRoute;
  bool get enableIpv6 => _enableIpv6;
  int get localPort => _localPort;
  List<DnsServer> get dnsServers => List.unmodifiable(_dnsServers);
  List<StaticIpMapping> get staticIpMappings =>
      List.unmodifiable(_staticIpMappings);

  // Setters（修改后立即持久化）
  set tunHijackDns(bool value) {
    _tunHijackDns = value;
    _saveSettings();
  }

  set resolveInboundDomains(bool value) {
    _resolveInboundDomains = value;
    _saveSettings();
  }

  set testDomain(String value) {
    _testDomain = value;
    _saveSettings();
  }

  set ttl(String value) {
    _ttl = value;
    _saveSettings();
  }

  set enableDnsRouting(bool value) {
    _enableDnsRouting = value;
    _saveSettings();
  }

  set enableEcs(bool value) {
    _enableEcs = value;
    _saveSettings();
  }

  set proxyResolver(String value) {
    _proxyResolver = value;
    _saveSettings();
  }

  set strictRoute(bool value) {
    _strictRoute = value;
    _saveSettings();
  }

  set enableIpv6(bool value) {
    _enableIpv6 = value;
    _saveSettings();
  }

  set localPort(int value) {
    if (value < 1024 || value > 65535) return; // 端口范围验证
    _localPort = value;
    _saveSettings();
  }

  /// 初始化 DNS 配置（从 SharedPreferences 读取）
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _tunHijackDns = prefs.getBool('dns_tun_hijack') ?? true;
      _resolveInboundDomains = prefs.getBool('dns_resolve_inbound') ?? false;
      _testDomain = prefs.getString('dns_test_domain') ?? 'gstatic.com';
      _ttl = prefs.getString('dns_ttl') ?? '12 h';
      _enableDnsRouting = prefs.getBool('dns_enable_routing') ?? false;
      _enableEcs = prefs.getBool('dns_enable_ecs') ?? true;
      _proxyResolver = prefs.getString('dns_proxy_resolver') ?? 'FakeIP';
      _strictRoute = prefs.getBool('dns_strict_route') ?? false;
      _enableIpv6 = prefs.getBool('dns_enable_ipv6') ?? false;
      _localPort = prefs.getInt('dns_local_port') ?? 7890;

      // 加载DNS服务器配置
      await _loadDnsServers();

      // 加载静态IP映射配置
      await _loadStaticIpMappings();
    } catch (e) {
      print('DNS 配置初始化失败: $e');
    }
  }

  /// 持久化 DNS 配置到 SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dns_tun_hijack', _tunHijackDns);
      await prefs.setBool('dns_resolve_inbound', _resolveInboundDomains);
      await prefs.setString('dns_test_domain', _testDomain);
      await prefs.setString('dns_ttl', _ttl);
      await prefs.setBool('dns_enable_routing', _enableDnsRouting);
      await prefs.setBool('dns_enable_ecs', _enableEcs);
      await prefs.setString('dns_proxy_resolver', _proxyResolver);
      await prefs.setBool('dns_strict_route', _strictRoute);
      await prefs.setBool('dns_enable_ipv6', _enableIpv6);
      await prefs.setInt('dns_local_port', _localPort);

      // 保存DNS服务器配置
      await _saveDnsServers();

      // 保存静态IP映射配置
      await _saveStaticIpMappings();
    } catch (e) {
      print('DNS 配置保存失败: $e');
    }
  }

  /// 加载DNS服务器配置
  Future<void> _loadDnsServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverJson = prefs.getStringList('dns_servers');

      if (serverJson != null && serverJson.isNotEmpty) {
        _dnsServers = serverJson
            .map((json) => DnsServer.fromJsonString(json))
            .where((server) => server != null)
            .cast<DnsServer>()
            .toList();
      }
    } catch (e) {
      print('DNS 服务器配置加载失败: $e');
    }
  }

  /// 保存DNS服务器配置
  Future<void> _saveDnsServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverJson = _dnsServers
          .map((server) => server.toJsonString())
          .toList();
      await prefs.setStringList('dns_servers', serverJson);
    } catch (e) {
      print('DNS 服务器配置保存失败: $e');
    }
  }

  /// 生成 sing-box DNS 配置
  /// preferRuleRouting: 在 规则 模式下临时启用 DNS 分流（不持久化），确保国内域名走本地/直连解析
  /// useTun: 在 TUN 模式下启用 FakeIP 优化并减少系统 DNS 竞争
  /// forceProxyDns: 强制所有DNS查询通过代理（用于全局模式）
  Map<String, dynamic> generateDnsConfig({
    bool preferRuleRouting = false,
    bool useTun = false,
    bool forceProxyDns = false,
  }) {
    // 运行时判定是否启用 DNS 分流：持久化开关或临时参数任一为 true 即启用
    final enableRoutingNow = _enableDnsRouting || preferRuleRouting;

    final servers = <Map<String, dynamic>>[];

    // 添加启用的 DNS 服务器
    for (final server in _dnsServers.where((s) => s.enabled)) {
      // 全局模式下只使用代理DNS服务器
      if (forceProxyDns && server.detour != 'proxy') {
        continue; // 跳过非代理DNS
      }

      final serverConfig = {
        'tag': server.name.toLowerCase(),
        'address': _buildServerAddress(server),
        'detour': server.detour,
      };

      // 对于代理DNS服务器，添加额外的稳定性配置
      if (server.detour == 'proxy') {
        serverConfig['address_resolver'] = 'local'; // 使用本地解析器解析DNS服务器地址
        serverConfig['strategy'] = 'prefer_ipv4'; // 优先IPv4提高稳定性
      }

      servers.add(serverConfig);
    }

    // 添加拦截（空响应）服务器（用于广告或无效域）
    servers.add({'tag': 'block', 'address': 'rcode://success'});
    // 提供本地系统解析器（某些规则需要引用 'local' 时使用）
    servers.add({'tag': 'local', 'address': 'local'});

    final rules = <Map<String, dynamic>>[];

    // 添加静态IP映射规则
    final enabledMappings = _staticIpMappings.where((m) => m.enabled).toList();
    if (enabledMappings.isNotEmpty) {
      for (final mapping in enabledMappings) {
        rules.add({
          'domain': [mapping.domain],
          'server': 'local',
          'address': mapping.ipAddress,
        });
      }
    }

    // 选取一个可用于境外解析的“代理 DNS”服务器：优先第一个 detour=proxy 的启用服务器
    String? proxyDNSTag;
    for (final s in servers) {
      final detour = (s['detour'] as String?) ?? '';
      final tag = (s['tag'] as String?) ?? '';
      if (detour == 'proxy' && tag.isNotEmpty && tag != 'block') {
        proxyDNSTag = tag;
        break;
      }
    }

    // v1.8.0 兼容：添加基于 rule_set 的 DNS 路由，实现中国域名使用本地DNS
    // 全局模式下不使用DNS分流，所有查询都通过代理DNS
    if (preferRuleRouting && enableRoutingNow && !forceProxyDns) {
      // 找到一个国内DNS服务器（detour=direct的服务器）
      String? directDNSTag;
      for (final s in servers) {
        final detour = (s['detour'] as String?) ?? '';
        final tag = (s['tag'] as String?) ?? '';
        if (detour == 'direct' &&
            tag.isNotEmpty &&
            tag != 'block' &&
            tag != 'local') {
          directDNSTag = tag;
          break;
        }
      }

      // 中国域名使用国内DNS服务器
      if (directDNSTag != null) {
        rules.add({
          'rule_set': ['geosite-cn'],
          'server': directDNSTag,
        });
      }

      // 广告域名拦截
      rules.add({
        'rule_set': ['geosite-ads'],
        'server': 'block',
      });

      // 境外域名使用代理DNS - 这是正确的做法
      if (proxyDNSTag != null) {
        rules.add({
          'rule_set': ['geosite-geolocation-!cn'],
          'server': proxyDNSTag,
        });
      } else {
        // 如果没有启用的代理DNS，查找已禁用的代理DNS作为备选
        String? fallbackProxyDNS;
        for (final server in _dnsServers) {
          if (server.detour == 'proxy' && !server.enabled) {
            fallbackProxyDNS = server.name.toLowerCase();
            // 临时添加这个备选服务器到servers列表
            servers.add({
              'tag': fallbackProxyDNS,
              'address': _buildServerAddress(server),
              'detour': server.detour,
            });
            break;
          }
        }

        if (fallbackProxyDNS != null) {
          rules.add({
            'rule_set': ['geosite-geolocation-!cn'],
            'server': fallbackProxyDNS,
          });
        }
        // 如果连备选都没有，就让境外域名走默认服务器
      }
    }

    // 默认服务器选择逻辑
    // 在开启DNS分流时，优先使用国内DNS作为默认，这样可以确保中国域名解析正常
    // 在未开启DNS分流时，TUN模式优先使用代理侧DNS以避免DNS污染
    // 全局模式下强制使用代理DNS
    String defaultServerTag = 'local';

    if (forceProxyDns) {
      // 全局模式：必须使用代理DNS
      defaultServerTag = proxyDNSTag ?? 'google'; // 优先选择已配置的代理DNS
    } else if (useTun) {
      if (enableRoutingNow) {
        // 开启DNS分流时，优先使用国内DNS作为默认
        String? directDNSTag;
        for (final s in servers) {
          final detour = (s['detour'] as String?) ?? '';
          final tag = (s['tag'] as String?) ?? '';
          if (detour == 'direct' &&
              tag.isNotEmpty &&
              tag != 'block' &&
              tag != 'local') {
            directDNSTag = tag;
            break;
          }
        }
        if (directDNSTag != null) {
          defaultServerTag = directDNSTag;
        } else if (proxyDNSTag != null) {
          defaultServerTag = proxyDNSTag;
        }
      } else {
        // 未开启DNS分流时，使用代理DNS避免污染
        if (proxyDNSTag != null) {
          defaultServerTag = proxyDNSTag;
        } else {
          // 若无代理 DNS，尝试选择任一非本地非 block 且非 direct 的服务器
          for (final s in servers) {
            final tag = (s['tag'] as String?) ?? '';
            final detour = (s['detour'] as String?) ?? '';
            if (tag.isNotEmpty &&
                tag != 'block' &&
                tag != 'local' &&
                detour != 'direct') {
              defaultServerTag = tag;
              break;
            }
          }
        }
      }
    } else {
      // 非 TUN：优先 direct，若没有则选第一个可用的非本地服务器
      for (final s in servers) {
        final tag = (s['tag'] as String?) ?? '';
        final detour = (s['detour'] as String?) ?? '';
        if (tag.isNotEmpty && tag != 'block' && detour == 'direct') {
          defaultServerTag = tag;
          break;
        }
      }
      if (defaultServerTag == 'local') {
        for (final s in servers) {
          final tag = (s['tag'] as String?) ?? '';
          if (tag.isNotEmpty && tag != 'block' && tag != 'local') {
            defaultServerTag = tag;
            break;
          }
        }
      }
    }

    // 当未开启 DNS 分流时，为关键境外域名强制使用代理 DNS，但添加备用策略提高稳定性
    // 全局模式下所有域名都已经使用代理DNS，不需要特殊处理
    if (!enableRoutingNow && proxyDNSTag != null && !forceProxyDns) {
      final alwaysProxyDomains = <String>{
        'google.com',
        'gstatic.com',
        'googleapis.com',
        'ggpht.com',
        'youtube.com',
        'ytimg.com',
        'gvt1.com',
        'gvt2.com',
        'openai.com',
        'anthropic.com',
        'cloudflare.com',
      };

      // 为这些关键域名添加DNS规则
      rules.insert(0, {
        'domain_suffix': alwaysProxyDomains.toList(),
        'server': proxyDNSTag,
      });
    }

    final result = {
      'servers': servers,
      'rules': rules,
      'final': defaultServerTag,
      'independent_cache': true,
      'strategy': (useTun
          ? 'prefer_ipv4'
          : _getResolverStrategy()), // 改为prefer_ipv4提高稳定性
      'disable_cache': false,
      'disable_expire': false,
      'reverse_mapping': _resolveInboundDomains,
      // 保持兼容的配置
      'client_subnet': '0.0.0.0/0',
    };

    // DNS严格路由配置：启用后确保DNS查询严格按照路由规则进行
    if (_strictRoute) {
      result['strategy'] = 'prefer_ipv4';
      result['disable_cache'] = true; // 严格模式下禁用缓存以确保每次查询都按规则路由
    }

    // FakeIP 配置：在 FakeIP 模式或者使用 TUN 时启用，减少 DNS 污染并提升兼容性
    if (_proxyResolver == 'FakeIP' || useTun) {
      result['fakeip'] = {
        'enabled': true,
        'inet4_range': '198.18.0.0/15',
        'inet6_range': 'fc00::/18',
      };
    }

    // 注意：部分 sing-box 版本不支持在 dns 中设置 hijack，已通过路由规则劫持 53 端口

    return result;
  }

  /// 构建服务器地址字符串
  String _buildServerAddress(DnsServer server) {
    switch (server.type) {
      case DnsServerType.udp:
        return server.address;
      case DnsServerType.tcp:
        return 'tcp://${server.address}';
      case DnsServerType.doh:
        return 'https://${server.address}/dns-query';
      case DnsServerType.dot:
        return 'tls://${server.address}';
      case DnsServerType.doq:
        return 'quic://${server.address}';
    }
  }

  /// 获取解析策略
  String _getResolverStrategy() {
    switch (_proxyResolver.toLowerCase()) {
      case 'fakeip':
        return 'prefer_ipv4';
      case 'remote':
        return 'prefer_ipv4';
      default:
        return 'prefer_ipv4';
    }
  }

  /// 添加 DNS 服务器
  void addDnsServer(DnsServer server) {
    _dnsServers.add(server);
    _saveDnsServers(); // 直接保存服务器配置
  }

  /// 删除 DNS 服务器
  void removeDnsServer(int index) {
    if (index >= 0 && index < _dnsServers.length) {
      _dnsServers.removeAt(index);
      _saveDnsServers(); // 直接保存服务器配置
    }
  }

  /// 更新 DNS 服务器
  void updateDnsServer(int index, DnsServer server) {
    if (index >= 0 && index < _dnsServers.length) {
      _dnsServers[index] = server;
      _saveDnsServers(); // 直接保存服务器配置
    }
  }

  /// 启用/禁用 DNS 服务器
  void toggleDnsServer(int index) {
    if (index >= 0 && index < _dnsServers.length) {
      _dnsServers[index] = _dnsServers[index].copyWith(
        enabled: !_dnsServers[index].enabled,
      );
      _saveDnsServers(); // 直接保存服务器配置
    }
  }

  /// 加载静态IP映射配置
  Future<void> _loadStaticIpMappings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingsJson = prefs.getStringList('static_ip_mappings');

      if (mappingsJson != null && mappingsJson.isNotEmpty) {
        _staticIpMappings = mappingsJson
            .map((json) => StaticIpMapping.fromJsonString(json))
            .where((mapping) => mapping != null)
            .cast<StaticIpMapping>()
            .toList();
      }
    } catch (e) {
      print('静态IP映射配置加载失败: $e');
    }
  }

  /// 保存静态IP映射配置
  Future<void> _saveStaticIpMappings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingsJson = _staticIpMappings
          .map((mapping) => mapping.toJsonString())
          .toList();
      await prefs.setStringList('static_ip_mappings', mappingsJson);
    } catch (e) {
      print('静态IP映射配置保存失败: $e');
    }
  }

  /// 添加静态IP映射
  void addStaticIpMapping(StaticIpMapping mapping) {
    _staticIpMappings.add(mapping);
    _saveStaticIpMappings();
  }

  /// 删除静态IP映射
  void removeStaticIpMapping(int index) {
    if (index >= 0 && index < _staticIpMappings.length) {
      _staticIpMappings.removeAt(index);
      _saveStaticIpMappings();
    }
  }

  /// 更新静态IP映射
  void updateStaticIpMapping(int index, StaticIpMapping mapping) {
    if (index >= 0 && index < _staticIpMappings.length) {
      _staticIpMappings[index] = mapping;
      _saveStaticIpMappings();
    }
  }

  /// 域名解析测试
  Future<DnsTestResult> testDomainResolution(String domain) async {
    if (domain.isEmpty) {
      return DnsTestResult(
        domain: domain,
        success: false,
        error: '域名不能为空',
        testTime: DateTime.now(),
      );
    }

    try {
      final startTime = DateTime.now();

      // 使用系统DNS解析域名
      final addresses = await InternetAddress.lookup(domain);

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      if (addresses.isEmpty) {
        return DnsTestResult(
          domain: domain,
          success: false,
          error: '无法解析域名',
          testTime: startTime,
          duration: duration,
        );
      }

      return DnsTestResult(
        domain: domain,
        success: true,
        resolvedAddresses: addresses.map((addr) => addr.address).toList(),
        testTime: startTime,
        duration: duration,
      );
    } catch (e) {
      return DnsTestResult(
        domain: domain,
        success: false,
        error: '解析失败: $e',
        testTime: DateTime.now(),
      );
    }
  }

  /// IPv6 探测：尝试解析并 TCP 连接一个只在 IPv6 上可访问的域名 (可换成公共 v6 测试域)。
  /// 若成功则设置 _ipv6RuntimeAvailable=true。
  /// 使用超时防止阻塞启动；失败不会抛出异常，只记录并返回 false。
  Future<bool> detectIpv6Support({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    // 1 分钟内不重复探测
    if (_lastIpv6CheckTime != null &&
        DateTime.now().difference(_lastIpv6CheckTime!) <
            const Duration(minutes: 1)) {
      return _ipv6RuntimeAvailable;
    }
    _lastIpv6CheckTime = DateTime.now();
    try {
      // 选择一个常见域名（可访问性高），尝试 AAAA 解析
      final addresses = await InternetAddress.lookup(
        'ipv6.google.com',
        type: InternetAddressType.IPv6,
      ).timeout(timeout);
      if (addresses.isNotEmpty) {
        // 可进一步尝试对 80/443 端口建立一个短连接验证链路，但多数情况下解析成功即可判定
        _ipv6RuntimeAvailable = true;
        return true;
      }
    } catch (_) {
      _ipv6RuntimeAvailable = false;
    }
    return _ipv6RuntimeAvailable;
  }
}

/// DNS 服务器类型
enum DnsServerType {
  udp, // UDP
  tcp, // TCP
  doh, // DNS over HTTPS
  dot, // DNS over TLS
  doq, // DNS over QUIC
}

/// DNS 服务器配置结构
class DnsServer {
  final String name;
  final String address;
  final DnsServerType type;
  final String detour;
  final bool enabled;

  const DnsServer({
    required this.name,
    required this.address,
    required this.type,
    required this.detour,
    this.enabled = true,
  });

  DnsServer copyWith({
    String? name,
    String? address,
    DnsServerType? type,
    String? detour,
    bool? enabled,
  }) {
    return DnsServer(
      name: name ?? this.name,
      address: address ?? this.address,
      type: type ?? this.type,
      detour: detour ?? this.detour,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': address,
      'type': type.name,
      'detour': detour,
      'enabled': enabled,
    };
  }

  factory DnsServer.fromJson(Map<String, dynamic> json) {
    return DnsServer(
      name: json['name'] as String,
      address: json['address'] as String,
      type: DnsServerType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DnsServerType.doh,
      ),
      detour: json['detour'] as String,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// 从JSON字符串创建DnsServer
  static DnsServer? fromJsonString(String jsonString) {
    try {
      final json = Map<String, dynamic>.from(
        const JsonDecoder().convert(jsonString),
      );
      return DnsServer.fromJson(json);
    } catch (e) {
      print('DnsServer JSON解析失败: $e');
      return null;
    }
  }

  /// 转换为JSON字符串
  String toJsonString() {
    return const JsonEncoder().convert(toJson());
  }
}

/// 静态IP映射配置结构
class StaticIpMapping {
  final String domain;
  final String ipAddress;
  final bool enabled;
  final String? description;

  const StaticIpMapping({
    required this.domain,
    required this.ipAddress,
    this.enabled = true,
    this.description,
  });

  StaticIpMapping copyWith({
    String? domain,
    String? ipAddress,
    bool? enabled,
    String? description,
  }) {
    return StaticIpMapping(
      domain: domain ?? this.domain,
      ipAddress: ipAddress ?? this.ipAddress,
      enabled: enabled ?? this.enabled,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'domain': domain,
      'ipAddress': ipAddress,
      'enabled': enabled,
      'description': description,
    };
  }

  factory StaticIpMapping.fromJson(Map<String, dynamic> json) {
    return StaticIpMapping(
      domain: json['domain'] as String,
      ipAddress: json['ipAddress'] as String,
      enabled: json['enabled'] as bool? ?? true,
      description: json['description'] as String?,
    );
  }

  /// 从JSON字符串创建StaticIpMapping
  static StaticIpMapping? fromJsonString(String jsonString) {
    try {
      final json = Map<String, dynamic>.from(
        const JsonDecoder().convert(jsonString),
      );
      return StaticIpMapping.fromJson(json);
    } catch (e) {
      print('StaticIpMapping JSON解析失败: $e');
      return null;
    }
  }

  /// 转换为JSON字符串
  String toJsonString() {
    return const JsonEncoder().convert(toJson());
  }
}

/// DNS测试结果
class DnsTestResult {
  final String domain;
  final bool success;
  final List<String> resolvedAddresses;
  final String? error;
  final DateTime testTime;
  final Duration? duration;

  const DnsTestResult({
    required this.domain,
    required this.success,
    this.resolvedAddresses = const [],
    this.error,
    required this.testTime,
    this.duration,
  });

  @override
  String toString() {
    if (success) {
      final durationMs = duration?.inMilliseconds ?? 0;
      return '域名: $domain\n解析成功 (${durationMs}ms)\nIP地址: ${resolvedAddresses.join(', ')}';
    } else {
      return '域名: $domain\n解析失败: $error';
    }
  }
}
