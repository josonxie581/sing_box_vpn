import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/proxy_mode.dart';

/// PAC 文件管理器
class PacFileManager {
  static const int _pacServerPort = 7891;
  HttpServer? _server;
  // 缓存已生成的 PAC 内容，key = "<mode>@<port>"
  static final Map<String, String> _pacCache = {};
  // 请求统计（用于限频日志）
  int _requestCount = 0;
  DateTime _lastStatLog = DateTime.now();
  // 最近一次生成时间（用于 Last-Modified）
  final Map<String, DateTime> _generatedAt = {};

  // 外部 PAC 文件路径
  static String get _externalPacDir =>
      p.join(Directory.current.path, 'pac_files');
  static String get _rulePacFile => p.join(_externalPacDir, 'rule_mode.pac');
  static String get _globalPacFile =>
      p.join(_externalPacDir, 'global_mode.pac');

  /// 启动 PAC 文件服务器
  Future<bool> startPacServer({
    required int proxyPort,
    required ProxyMode mode,
  }) async {
    try {
      await stopPacServer(); // 先停止现有服务器

      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _pacServerPort,
      );

      _server!.listen((HttpRequest request) {
        _handleRequest(request, proxyPort, mode);
      });

      print('PAC 文件服务器启动: http://127.0.0.1:$_pacServerPort/proxy.pac');
      return true;
    } catch (e) {
      print('启动 PAC 服务器失败: $e');
      return false;
    }
  }

  /// 停止 PAC 文件服务器
  Future<void> stopPacServer() async {
    await _server?.close();
    _server = null;
  }

  /// 处理 HTTP 请求
  void _handleRequest(HttpRequest request, int proxyPort, ProxyMode mode) {
    final response = request.response;

    // 设置 CORS 头
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Content-Type', 'application/x-ns-proxy-autoconfig');

    if (request.uri.path == '/proxy.pac') {
      final key = '${mode.value}@$proxyPort';
      String? pacContent = _pacCache[key];
      if (pacContent == null) {
        pacContent = _generatePacContent(proxyPort, mode);
        _pacCache[key] = pacContent;
        _generatedAt[key] = DateTime.now();
      }

      // 简单 ETag / Last-Modified 支持，便于系统缓存，减少重复请求命中 CPU
      final etag = '"${pacContent.hashCode.toRadixString(16)}"';
      response.headers.set('Cache-Control', 'max-age=3600');
      response.headers.set('ETag', etag);
      final lm = _generatedAt[key] ?? DateTime.now();
      response.headers.set('Last-Modified', HttpDate.format(lm.toUtc()));

      final ifNoneMatch = request.headers.value('if-none-match');
      final ifModifiedSince = request.headers.value('if-modified-since');
      bool notModified = false;
      if (ifNoneMatch != null && ifNoneMatch == etag) {
        notModified = true;
      } else if (ifModifiedSince != null) {
        try {
          final since = HttpDate.parse(ifModifiedSince);
          if (!lm.isAfter(since)) {
            notModified = true;
          }
        } catch (_) {}
      }
      if (notModified) {
        response.statusCode = HttpStatus.notModified;
      } else {
        response.statusCode = HttpStatus.ok;
        response.write(pacContent);
      }

      // 限频输出日志：每 200 次或 30 秒打印一次概要
      _requestCount++;
      final now = DateTime.now();
      if (_requestCount <= 5) {
        // 前几次详细输出，便于调试
        print(
          'PAC 请求(#$_requestCount) 来自 ${request.connectionInfo?.remoteAddress} path=${request.uri.path} mode=$mode port=$proxyPort cacheHit=${_pacCache.containsKey(key)}',
        );
      } else if (_requestCount % 200 == 0 ||
          now.difference(_lastStatLog).inSeconds >= 30) {
        print(
          'PAC 统计: totalRequests=$_requestCount uniqueKeys=${_pacCache.length} lastMode=$mode lastPort=$proxyPort',
        );
        _lastStatLog = now;
      }
    } else {
      // 返回 404
      print('PAC 服务器收到未知请求: ${request.uri.path}');
      response.statusCode = HttpStatus.notFound;
      response.write('404 Not Found');
    }

    response.close();
  }

  /// 生成 PAC 文件内容
  String _generatePacContent(int proxyPort, ProxyMode mode) {
    // 首先尝试从外部文件加载
    final externalContent = _loadExternalPacFile(proxyPort, mode);
    if (externalContent != null) {
      // 不再每次请求都打印，避免高频 I/O；保留首次构建时输出即可
      print(
        'PAC: 使用外部文件 -> ${mode == ProxyMode.rule ? _rulePacFile : _globalPacFile}',
      );
      return externalContent;
    }

    // 回退到内置模板
    // 仅首次生成时打印（缓存后不再生成）
    print('PAC: 使用内置模板 mode=$mode port=$proxyPort');
    switch (mode) {
      case ProxyMode.rule:
        return _generateRuleModePac(proxyPort);
      case ProxyMode.global:
        return _generateGlobalModePac(proxyPort);
    }
  }

  /// 从外部文件加载 PAC 内容
  String? _loadExternalPacFile(int proxyPort, ProxyMode mode) {
    try {
      final pacFile = mode == ProxyMode.rule ? _rulePacFile : _globalPacFile;
      final file = File(pacFile);

      if (!file.existsSync()) {
        return null;
      }

      String content = file.readAsStringSync();

      // 替换端口占位符 - 支持模板变量格式
      content = content.replaceAll('{{PROXY_PORT}}', proxyPort.toString());
      content = content.replaceAll('{{PROXY_HOST}}', '127.0.0.1');

      // 支持GFWList格式的PAC文件 - 动态替换代理设置
      // 检测是否为GFWList格式（包含 'var proxy =' 的PAC文件）
      if (content.contains('var proxy =') &&
          content.contains('SOCKS5 127.0.0.1:1080')) {
        // 替换为当前端口的代理设置
        final newProxyString =
            'SOCKS5 127.0.0.1:$proxyPort; SOCKS 127.0.0.1:$proxyPort; PROXY 127.0.0.1:$proxyPort; DIRECT';
        content = content.replaceAll(
          RegExp(r"var proxy = '[^']*';"),
          "var proxy = '$newProxyString';",
        );
        print('检测到GFWList格式PAC文件，已更新代理端口为: $proxyPort');
      }

      return content;
    } catch (e) {
      print('加载外部PAC文件失败: $e');
      return null;
    }
  }

  /// 生成规则模式的 PAC 文件
  String _generateRuleModePac(int proxyPort) {
    return '''
function FindProxyForURL(url, host) {
    // Debug log (viewable in browser console)
    // console.log("PAC: " + url + " -> " + host);
    
    // Local addresses direct
    if (isPlainHostName(host) ||
        isInNet(host, "127.0.0.0", "255.0.0.0") ||
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "172.16.0.0", "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0") ||
        isInNet(host, "169.254.0.0", "255.255.0.0")) {
        return "DIRECT";
    }
    
    // Foreign websites requiring proxy (priority match)
    var proxyDomains = [
        ".google.com", ".google.com.hk", ".googleapis.com", 
        ".googlevideo.com", ".googleusercontent.com", ".gstatic.com",
        ".youtube.com", ".ytimg.com", ".facebook.com", ".twitter.com", 
        ".instagram.com", ".github.com", ".openai.com", ".anthropic.com", 
        ".cloudflare.com", ".wikipedia.org", ".reddit.com"
    ];
    
    for (var i = 0; i < proxyDomains.length; i++) {
        if (dnsDomainIs(host, proxyDomains[i])) {
            return "PROXY 127.0.0.1:$proxyPort; SOCKS5 127.0.0.1:$proxyPort; DIRECT";
        }
    }
    
    // Domestic domains and websites direct
    var directDomains = [
        ".cn", ".com.cn", ".net.cn", ".org.cn", ".edu.cn", ".gov.cn",
        ".baidu.com", ".qq.com", ".taobao.com", ".tmall.com", ".jd.com",
        ".weibo.com", ".sina.com.cn", ".163.com", ".126.com", ".sohu.com",
        ".youku.com", ".bilibili.com", ".zhihu.com", ".douban.com",
        ".alipay.com", ".aliyun.com", ".tencent.com", ".wechat.com", ".weixin.qq.com"
    ];
    
    for (var i = 0; i < directDomains.length; i++) {
        if (dnsDomainIs(host, directDomains[i])) {
            return "DIRECT";
        }
    }
    
    // All other websites via proxy (default rule)
    return "PROXY 127.0.0.1:$proxyPort; SOCKS5 127.0.0.1:$proxyPort; DIRECT";
}
''';
  }

  /// 生成全局模式的 PAC 文件
  String _generateGlobalModePac(int proxyPort) {
    return '''
function FindProxyForURL(url, host) {
    // Debug log (viewable in browser console)
    // console.log("PAC Global: " + url + " -> " + host);
    
    // Local addresses direct
    if (isPlainHostName(host) ||
        isInNet(host, "127.0.0.0", "255.0.0.0") ||
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "172.16.0.0", "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0") ||
        isInNet(host, "169.254.0.0", "255.255.0.0")) {
        return "DIRECT";
    }
    
    // Global mode: all external traffic via proxy
    return "PROXY 127.0.0.1:$proxyPort; SOCKS5 127.0.0.1:$proxyPort; DIRECT";
}
''';
  }

  /// 获取 PAC 文件 URL
  String get pacUrl => 'http://127.0.0.1:$_pacServerPort/proxy.pac';

  /// 生成本地 PAC 文件
  Future<String?> generateLocalPacFile({
    required int proxyPort,
    required ProxyMode mode,
    String? filePath,
  }) async {
    try {
      final content = _generatePacContent(proxyPort, mode);
      final file = File(
        filePath ?? '${Directory.systemTemp.path}/gsou_proxy.pac',
      );
      await file.writeAsString(content);
      print('PAC文件已生成到: ${file.path}');
      print('PAC文件内容预览:\n$content');
      return file.path;
    } catch (e) {
      print('生成 PAC 文件失败: $e');
      return null;
    }
  }

  /// 获取当前PAC文件内容（用于调试）
  String getCurrentPacContent(int proxyPort, ProxyMode mode) {
    final key = '${mode.value}@$proxyPort';
    return _pacCache[key] ?? _generatePacContent(proxyPort, mode);
  }

  /// 加载指定路径的PAC文件并处理端口替换
  String? loadCustomPacFile(String filePath, int proxyPort) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        print('PAC文件不存在: $filePath');
        return null;
      }

      String content = file.readAsStringSync();

      // 替换端口占位符 - 支持模板变量格式
      content = content.replaceAll('{{PROXY_PORT}}', proxyPort.toString());
      content = content.replaceAll('{{PROXY_HOST}}', '127.0.0.1');

      // 支持GFWList格式的PAC文件 - 动态替换代理设置
      if (content.contains('var proxy =') &&
          content.contains('SOCKS5 127.0.0.1:1080')) {
        final newProxyString =
            'SOCKS5 127.0.0.1:$proxyPort; SOCKS 127.0.0.1:$proxyPort; PROXY 127.0.0.1:$proxyPort; DIRECT';
        content = content.replaceAll(
          RegExp(r"var proxy = '[^']*';"),
          "var proxy = '$newProxyString';",
        );
        print('检测到GFWList格式PAC文件，已更新代理端口为: $proxyPort');
      }

      // 支持其他常见的代理端口模式
      content = content.replaceAll(
        RegExp(r'127\.0\.0\.1:1080'),
        '127.0.0.1:$proxyPort',
      );
      content = content.replaceAll(
        RegExp(r'127\.0\.0\.1:7890'),
        '127.0.0.1:$proxyPort',
      );
      content = content.replaceAll(
        RegExp(r'127\.0\.0\.1:8080'),
        '127.0.0.1:$proxyPort',
      );

      print('已加载自定义PAC文件: $filePath，代理端口: $proxyPort');
      // 自定义文件加载后需失效当前缓存
      _pacCache.removeWhere((k, v) => k.endsWith('@$proxyPort'));
      return content;
    } catch (e) {
      print('加载自定义PAC文件失败: $e');
      return null;
    }
  }

  /// 主动失效指定端口的缓存（例如外部 PAC 文件被替换）
  void invalidateCache({int? proxyPort, ProxyMode? mode}) {
    if (proxyPort == null && mode == null) {
      _pacCache.clear();
      return;
    }
    final toRemove = <String>[];
    _pacCache.forEach((k, v) {
      final parts = k.split('@');
      if (parts.length == 2) {
        final m = parts[0];
        final p = int.tryParse(parts[1]);
        final modeMatch = mode == null || mode.value == m;
        final portMatch = proxyPort == null || proxyPort == p;
        if (modeMatch && portMatch) toRemove.add(k);
      }
    });
    for (final k in toRemove) {
      _pacCache.remove(k);
      _generatedAt.remove(k);
    }
  }

  /// 创建示例 PAC 文件
  Future<bool> createSamplePacFiles() async {
    try {
      final pacDir = Directory(_externalPacDir);
      if (!pacDir.existsSync()) {
        await pacDir.create(recursive: true);
      }

      // 创建规则模式示例文件
      final ruleSample = '''
// 规则模式 PAC 文件 - 可自定义修改
// 使用 {{PROXY_PORT}} 作为端口占位符，系统会自动替换
function FindProxyForURL(url, host) {
    // 本地地址直连
    if (isPlainHostName(host) ||
        isInNet(host, "127.0.0.0", "255.0.0.0") ||
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "172.16.0.0", "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0") ||
        isInNet(host, "169.254.0.0", "255.255.0.0")) {
        return "DIRECT";
    }
    
    // 国外重要网站走代理
    var proxyDomains = [
        ".google.com", ".youtube.com", ".facebook.com", ".twitter.com", 
        ".github.com", ".openai.com", ".anthropic.com", ".wikipedia.org"
    ];
    
    for (var i = 0; i < proxyDomains.length; i++) {
        if (dnsDomainIs(host, proxyDomains[i])) {
            return "PROXY {{PROXY_HOST}}:{{PROXY_PORT}}; SOCKS5 {{PROXY_HOST}}:{{PROXY_PORT}}; DIRECT";
        }
    }
    
    // 国内网站直连
    var directDomains = [
        ".cn", ".baidu.com", ".qq.com", ".taobao.com", ".bilibili.com"
    ];
    
    for (var i = 0; i < directDomains.length; i++) {
        if (dnsDomainIs(host, directDomains[i])) {
            return "DIRECT";
        }
    }
    
    // 其他网站走代理
    return "PROXY {{PROXY_HOST}}:{{PROXY_PORT}}; SOCKS5 {{PROXY_HOST}}:{{PROXY_PORT}}; DIRECT";
}
''';

      // 创建全局模式示例文件
      final globalSample = '''
// 全局模式 PAC 文件 - 可自定义修改
// 使用 {{PROXY_PORT}} 作为端口占位符，系统会自动替换
function FindProxyForURL(url, host) {
    // 本地地址直连
    if (isPlainHostName(host) ||
        isInNet(host, "127.0.0.0", "255.0.0.0") ||
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "172.16.0.0", "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0") ||
        isInNet(host, "169.254.0.0", "255.255.0.0")) {
        return "DIRECT";
    }
    
    // 全局模式：所有外网流量走代理
    return "PROXY {{PROXY_HOST}}:{{PROXY_PORT}}; SOCKS5 {{PROXY_HOST}}:{{PROXY_PORT}}; DIRECT";
}
''';

      // 写入文件
      await File(_rulePacFile).writeAsString(ruleSample);
      await File(_globalPacFile).writeAsString(globalSample);

      print('已创建示例PAC文件:');
      print('规则模式: $_rulePacFile');
      print('全局模式: $_globalPacFile');
      return true;
    } catch (e) {
      print('创建示例PAC文件失败: $e');
      return false;
    }
  }
}
