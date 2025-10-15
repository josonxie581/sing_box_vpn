import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Rule Sets 管理器
/// 负责下载、更新和管理 sing-box 规则集数据库
/// 符合 sing-box 1.8+ 规范，使用新的规则集格式替代已废弃的 Geosite
///
/// 重要变更说明：
/// - Geosite 在 sing-box 1.8.0 中废弃，在 1.12.0 中完全移除
/// - 新版本使用 Rule Sets (.srs) 格式，提供相同功能但更高效
/// - 规则集文件格式：geosite-xxx.srs, geoip-xxx.srs
/// - 在路由配置中使用 "rule_set" 字段替代原来的 "geosite/geoip" 字段
///
/// 配置示例：
/// ```json
/// {
///   "rule_set": ["geosite-cn", "geosite-google"],
///   "outbound": "proxy"
/// }
/// ```
class RuleSetsManager {
  // 使用官方推荐的远程规则集URL
  static const String _geositeBaseUrl =
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set';
  static const String _geoipBaseUrl =
      'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set';
  static const String _mirrorUrl =
      'https://mirror.ghproxy.com/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set';

  // 常用的域名规则集（原 geosite 规则，现以规则集形式提供）
  static const List<String> commonRuleSets = [
    'geosite-cn', // 中国大陆网站
    'geosite-geolocation-!cn', // 非中国网站
    'geosite-ads', // 广告
    'geosite-google', // Google
    'geosite-youtube', // YouTube
    'geosite-twitter', // Twitter
    'geosite-facebook', // Facebook
    'geosite-telegram', // Telegram
    'geosite-netflix', // Netflix
    'geosite-spotify', // Spotify
    'geosite-apple', // Apple
    'geosite-microsoft', // Microsoft
    'geosite-github', // GitHub
    'geosite-steam', // Steam
    'geosite-bilibili', // Bilibili
    'geosite-tiktok', // TikTok
    'geosite-disney', // Disney+
    'geosite-openai', // OpenAI
    'geosite-anthropic', // Anthropic
  ];

  // 常用的 IP 地址规则集
  static const List<String> commonGeoIPRuleSets = [
    'geoip-cn', // 中国IP地址
    // 'geoip-private', // 私有IP地址
    'geoip-us', // 美国IP地址
    'geoip-jp', // 日本IP地址
    'geoip-hk', // 香港IP地址
    'geoip-tw', // 台湾IP地址
    'geoip-sg', // 新加坡IP地址
    'geoip-kr', // 韩国IP地址
    'geoip-de', // 德国IP地址
    'geoip-gb', // 英国IP地址
    'geoip-fr', // 法国IP地址
    'geoip-ca', // 加拿大IP地址
    'geoip-au', // 澳大利亚IP地址
    'geoip-ru', // 俄罗斯IP地址
    'geoip-in', // 印度IP地址
    'geoip-br', // 巴西IP地址
    'geoip-cloudflare', // Cloudflare IP地址
    'geoip-telegram', // Telegram IP地址
    'geoip-netflix', // Netflix IP地址
    'geoip-google', // Google IP地址
  ];

  // 域名规则集分类（原 Geosite 类别）
  static const Map<String, List<String>> geositeCategories = {
    '常用': ['geosite-cn', 'geosite-geolocation-!cn', 'geosite-ads'],
    '社交媒体': [
      'geosite-twitter',
      'geosite-facebook',
      'geosite-instagram',
      'geosite-telegram',
      'geosite-tiktok',
      'geosite-whatsapp',
    ],
    '流媒体': [
      'geosite-youtube',
      'geosite-netflix',
      'geosite-spotify',
      'geosite-disney',
      'geosite-hbo',
      'geosite-twitch',
      'geosite-bilibili',
    ],
    '技术服务': [
      'geosite-google',
      'geosite-github',
      'geosite-openai',
      'geosite-anthropic',
      'geosite-cloudflare',
      'geosite-aws',
    ],
    '游戏': [
      'geosite-steam',
      'geosite-epicgames',
      'geosite-xbox',
      'geosite-playstation',
      'geosite-nintendo',
    ],
    '企业服务': [
      'geosite-microsoft',
      'geosite-apple',
      'geosite-amazon',
      'geosite-oracle',
      'geosite-adobe',
    ],
  };

  // IP 地址规则集分类
  static const Map<String, List<String>> geoipCategories = {
    '基础': ['geoip-cn'],
    '亚太地区': [
      'geoip-jp',
      'geoip-hk',
      'geoip-tw',
      'geoip-sg',
      'geoip-kr',
      'geoip-au',
      'geoip-in',
    ],
    '欧美地区': [
      'geoip-us',
      'geoip-de',
      'geoip-gb',
      'geoip-fr',
      'geoip-ca',
      'geoip-ru',
      'geoip-br',
    ],
    // '服务商': [
    //   'geoip-cloudflare',
    //   'geoip-telegram',
    //   'geoip-netflix',
    //   'geoip-google',
    // ],
  };

  // 兼容性：保留原有的 ruleCategories
  static Map<String, List<String>> get ruleCategories => geositeCategories;

  static final RuleSetsManager _instance = RuleSetsManager._internal();
  factory RuleSetsManager() => _instance;
  RuleSetsManager._internal();

  /// 判断规则集类型
  static bool isGeoIPRuleset(String rulesetName) {
    return rulesetName.startsWith('geoip-');
  }

  /// 判断规则集类型
  static bool isGeositeRuleset(String rulesetName) {
    return rulesetName.startsWith('geosite-');
  }

  // 获取规则集存储目录
  Future<Directory> _getRulesetDirectory() async {
    Directory rulesetDir;

    if (Platform.isWindows) {
      // Windows生产环境：放到exe文件目录下
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      rulesetDir = Directory(
        path.join(
          exeDir,
          'data',
          'flutter_assets',
          'assets',
          'rulesets',
          'geo',
        ),
      );
    } else {
      // 其他平台使用应用支持目录
      final appDir = await getApplicationSupportDirectory();
      rulesetDir = Directory(path.join(appDir.path, 'rulesets'));
    }

    if (!await rulesetDir.exists()) {
      await rulesetDir.create(recursive: true);
      print('[RuleSetsManager] 创建规则集目录: ${rulesetDir.path}');
    }
    return rulesetDir;
  }

  /// 获取规则集文件路径
  Future<String> getRulesetPath(String rulesetName) async {
    final baseDir = await _getRulesetDirectory();

    // 根据规则集类型决定子目录
    String subDir;
    if (isGeoIPRuleset(rulesetName)) {
      subDir = 'geoip';
    } else if (isGeositeRuleset(rulesetName)) {
      subDir = 'geosite';
    } else {
      subDir = 'other';
    }

    // 优先检查外部存储的应用专属目录，便于用户手动拷贝（Android 无需额外权限）
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final candidateDir = Directory(
          path.join(extDir.path, 'rulesets', subDir),
        );
        final candidateFile = path.join(
          candidateDir.path,
          rulesetName.endsWith('.srs') ? rulesetName : '$rulesetName.srs',
        );
        if (File(candidateFile).existsSync()) {
          return candidateFile;
        }
      }
    } catch (_) {
      // 忽略外部存储异常，回退内部路径
    }

    final dir = Directory(path.join(baseDir.path, subDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      print('[RuleSetsManager] 创建子目录: ${dir.path}');
    }

    // 确保文件名格式正确
    final fileName = rulesetName.endsWith('.srs')
        ? rulesetName
        : '$rulesetName.srs';
    return path.join(dir.path, fileName);
  }

  /// 检查规则集是否已下载
  Future<bool> isRulesetDownloaded(String rulesetName) async {
    final filePath = await getRulesetPath(rulesetName);
    return File(filePath).exists();
  }

  /// 下载单个规则集
  Future<bool> downloadRuleset(
    String rulesetName, {
    bool useMirror = false,
    bool forceUpdate = false,
    void Function(double)? onProgress,
  }) async {
    try {
      print('[RuleSetsManager] 开始下载规则集: $rulesetName');

      // 如果不是强制更新，检查文件是否已存在
      if (!forceUpdate && await isRulesetDownloaded(rulesetName)) {
        print('[RuleSetsManager] 规则集 $rulesetName 已存在，跳过下载');
        return true;
      }

      // 确保文件名格式正确
      final fileName = rulesetName.endsWith('.srs')
          ? rulesetName
          : '$rulesetName.srs';

      // 构建下载URL，根据规则集类型选择基础URL
      String baseUrl;
      if (useMirror) {
        baseUrl = _mirrorUrl;
      } else {
        // 根据规则集类型选择URL
        baseUrl = rulesetName.startsWith('geoip-')
            ? _geoipBaseUrl
            : _geositeBaseUrl;
      }
      final url = '$baseUrl/$fileName';

      print('[RuleSetsManager] 下载URL: $url');

      // 发起下载请求
      final request = http.Request('GET', Uri.parse(url));
      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        print('[RuleSetsManager] 下载失败，状态码: ${streamedResponse.statusCode}');
        // 如果使用主URL失败，尝试镜像
        if (!useMirror) {
          print('[RuleSetsManager] 尝试使用镜像下载...');
          return downloadRuleset(
            rulesetName,
            useMirror: true,
            forceUpdate: forceUpdate,
            onProgress: onProgress,
          );
        }
        return false;
      }

      // 获取文件大小
      final contentLength = streamedResponse.contentLength ?? 0;
      final bytes = <int>[];
      var downloadedBytes = 0;

      // 下载并报告进度
      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;

        if (contentLength > 0 && onProgress != null) {
          onProgress(downloadedBytes / contentLength);
        }
      }

      // 保存到文件
      final filePath = await getRulesetPath(rulesetName);
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      print('[RuleSetsManager] 规则集下载成功: $rulesetName (${bytes.length} bytes)');
      return true;
    } catch (e) {
      print('[RuleSetsManager] 下载规则集失败: $e');
      // 如果是网络错误且未使用镜像，尝试镜像
      if (!useMirror && e.toString().contains('Connection')) {
        print('[RuleSetsManager] 尝试使用镜像下载...');
        return downloadRuleset(
          rulesetName,
          useMirror: true,
          onProgress: onProgress,
        );
      }
      return false;
    }
  }

  /// 批量下载规则集
  Future<Map<String, bool>> downloadRulesets(
    List<String> rulesetNames, {
    bool useMirror = false,
    void Function(String ruleset, double progress)? onProgress,
  }) async {
    final results = <String, bool>{};

    for (final ruleset in rulesetNames) {
      final success = await downloadRuleset(
        ruleset,
        useMirror: useMirror,
        onProgress: onProgress != null
            ? (progress) => onProgress(ruleset, progress)
            : null,
      );
      results[ruleset] = success;
    }

    return results;
  }

  /// 下载基础规则集（中国、广告等）
  Future<bool> downloadBasicRulesets({
    bool useMirror = false,
    void Function(String status)? onStatus,
  }) async {
    final basicRulesets = [
      'geosite-cn',
      'geosite-geolocation-!cn',
      'geosite-ads',
      'geoip-cn',
      'geoip-private',
    ];

    onStatus?.call('正在下载基础规则集...');

    for (final ruleset in basicRulesets) {
      onStatus?.call('正在下载: $ruleset');

      final success = await downloadRuleset(ruleset, useMirror: useMirror);
      if (!success) {
        onStatus?.call('下载失败: $ruleset');
        return false;
      }
    }

    onStatus?.call('基础规则集下载完成');
    return true;
  }

  /// 下载所有常用规则集（一键下载）
  Future<Map<String, bool>> downloadAllCommonRulesets({
    bool useMirror = false,
    bool forceUpdate = false,
    void Function(String status)? onStatus,
    void Function(String ruleset, double progress)? onProgress,
    void Function()? onCancel,
  }) async {
    final allRulesets = <String>[];

    // 添加所有 geosite 规则集
    for (final category in geositeCategories.values) {
      allRulesets.addAll(category);
    }

    // 添加所有 geoip 规则集
    for (final category in geoipCategories.values) {
      allRulesets.addAll(category);
    }

    // 去重
    final uniqueRulesets = allRulesets.toSet().toList();

    onStatus?.call('准备下载 ${uniqueRulesets.length} 个规则集...');

    final results = <String, bool>{};
    var completed = 0;

    for (final ruleset in uniqueRulesets) {
      // 检查是否被取消
      if (onCancel != null) {
        // 这里可以添加取消机制的检查
      }

      onStatus?.call(
        '正在下载: $ruleset (${completed + 1}/${uniqueRulesets.length})',
      );

      final success = await downloadRuleset(
        ruleset,
        useMirror: useMirror,
        forceUpdate: forceUpdate,
        onProgress: onProgress != null
            ? (progress) => onProgress(ruleset, progress)
            : null,
      );

      results[ruleset] = success;
      completed++;

      if (!success) {
        print('[RuleSetsManager] 下载失败: $ruleset');
      }

      // 小延迟避免过于频繁的请求
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final successCount = results.values.where((v) => v).length;
    onStatus?.call('下载完成: $successCount/${uniqueRulesets.length} 个规则集成功');

    return results;
  }

  /// 下载分类规则集
  Future<Map<String, bool>> downloadCategoryRulesets(
    String categoryName, {
    bool useMirror = false,
    void Function(String status)? onStatus,
    void Function(String ruleset, double progress)? onProgress,
  }) async {
    List<String> rulesets = [];

    // 检查是否是 geosite 分类
    if (geositeCategories.containsKey(categoryName)) {
      rulesets = geositeCategories[categoryName]!;
    }
    // 检查是否是 geoip 分类
    else if (geoipCategories.containsKey(categoryName)) {
      rulesets = geoipCategories[categoryName]!;
    }

    if (rulesets.isEmpty) {
      onStatus?.call('未找到分类: $categoryName');
      return {};
    }

    onStatus?.call('准备下载 $categoryName 分类 (${rulesets.length} 个规则集)...');

    final results = <String, bool>{};
    var completed = 0;

    for (final ruleset in rulesets) {
      onStatus?.call('正在下载: $ruleset (${completed + 1}/${rulesets.length})');

      final success = await downloadRuleset(
        ruleset,
        useMirror: useMirror,
        onProgress: onProgress != null
            ? (progress) => onProgress(ruleset, progress)
            : null,
      );

      results[ruleset] = success;
      completed++;

      // 小延迟
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final successCount = results.values.where((v) => v).length;
    onStatus?.call(
      '$categoryName 分类下载完成: $successCount/${rulesets.length} 个规则集成功',
    );

    return results;
  }

  /// 获取常用规则集统计信息
  Future<Map<String, dynamic>> getCommonRulesetsStats() async {
    final allRulesets = <String>[];

    // 添加所有常用规则集
    for (final category in geositeCategories.values) {
      allRulesets.addAll(category);
    }
    for (final category in geoipCategories.values) {
      allRulesets.addAll(category);
    }

    final uniqueRulesets = allRulesets.toSet().toList();
    final downloadedRulesets = await getDownloadedRulesets();

    final geositeCount = uniqueRulesets
        .where((r) => r.startsWith('geosite-'))
        .length;
    final geoipCount = uniqueRulesets
        .where((r) => r.startsWith('geoip-'))
        .length;
    final downloadedCount = uniqueRulesets
        .where((r) => downloadedRulesets.contains(r))
        .length;

    return {
      'total': uniqueRulesets.length,
      'geosite': geositeCount,
      'geoip': geoipCount,
      'downloaded': downloadedCount,
      'missing': uniqueRulesets.length - downloadedCount,
    };
  }

  /// 获取已下载的规则集列表
  Future<List<String>> getDownloadedRulesets() async {
    // 确保部分基础规则集（随包提供）已落盘，避免首次进入页面列表为空
    await _ensureBundledBaseline();

    final baseDir = await _getRulesetDirectory();
    if (!await baseDir.exists()) {
      return [];
    }

    final rulesets = <String>[];

    // 扫描 geosite 子目录
    final geositeDir = Directory(path.join(baseDir.path, 'geosite'));
    if (await geositeDir.exists()) {
      final files = await geositeDir.list().toList();
      for (final file in files) {
        if (file is File && file.path.endsWith('.srs')) {
          final fileName = path.basename(file.path);
          // 移除 .srs 扩展名
          final rulesetName = fileName.substring(0, fileName.length - 4);
          rulesets.add(rulesetName);
        }
      }
    }

    // 扫描 geoip 子目录
    final geoipDir = Directory(path.join(baseDir.path, 'geoip'));
    if (await geoipDir.exists()) {
      final files = await geoipDir.list().toList();
      for (final file in files) {
        if (file is File && file.path.endsWith('.srs')) {
          final fileName = path.basename(file.path);
          // 移除 .srs 扩展名
          final rulesetName = fileName.substring(0, fileName.length - 4);
          rulesets.add(rulesetName);
        }
      }
    }

    // 扫描 other 子目录（如果有的话）
    final otherDir = Directory(path.join(baseDir.path, 'other'));
    if (await otherDir.exists()) {
      final files = await otherDir.list().toList();
      for (final file in files) {
        if (file is File && file.path.endsWith('.srs')) {
          final fileName = path.basename(file.path);
          // 移除 .srs 扩展名
          final rulesetName = fileName.substring(0, fileName.length - 4);
          rulesets.add(rulesetName);
        }
      }
    }

    print('[RuleSetsManager] 找到已下载规则集: ${rulesets.length} 个');
    return rulesets;
  }

  /// 将随包内置的一小部分基础规则集复制到应用目录（若不存在）
  Future<void> _ensureBundledBaseline() async {
    final candidates = <String>[
      'geosite-ads',
      'geosite-cn',
      'geosite-geolocation-!cn',
      'geoip-cn',
    ];

    for (final name in candidates) {
      try {
        final isGeoip = name.startsWith('geoip-');
        final assetPath = isGeoip
            ? 'assets/rulesets/geo/geoip/$name.srs'
            : 'assets/rulesets/geo/geosite/$name.srs';

        final destPath = await getRulesetPath(name);
        final destFile = File(destPath);
        if (!await destFile.exists()) {
          // 若资产中不存在相应文件，load 会抛异常，直接忽略即可
          final data = await rootBundle.load(assetPath);
          await destFile.create(recursive: true);
          await destFile.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
          print('[RuleSetsManager] 初次导入随包规则集: $name -> $destPath');
        }
      } catch (e) {
        // 资产可能未包含该文件或 IO 失败，这里静默忽略，不阻断其它条目
      }
    }
  }

  /// 删除规则集
  Future<bool> deleteRuleset(String rulesetName) async {
    try {
      final filePath = await getRulesetPath(rulesetName);
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        print('[RuleSetsManager] 删除规则集: $rulesetName');
        return true;
      }
      return false;
    } catch (e) {
      print('[RuleSetsManager] 删除规则集失败: $e');
      return false;
    }
  }

  /// 清理所有规则集
  Future<void> clearAllRulesets() async {
    final dir = await _getRulesetDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      print('[RuleSetsManager] 清理所有规则集');
    }
  }

  /// 获取规则集文件大小
  Future<int> getRulesetSize(String rulesetName) async {
    final filePath = await getRulesetPath(rulesetName);
    final file = File(filePath);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  /// 获取规则集最后修改时间
  Future<DateTime?> getRulesetLastModified(String rulesetName) async {
    final filePath = await getRulesetPath(rulesetName);
    final file = File(filePath);
    if (await file.exists()) {
      return await file.lastModified();
    }
    return null;
  }

  /// 检查规则集更新
  Future<bool> checkForUpdates(String rulesetName) async {
    // 这里可以通过比较 GitHub API 获取的最新版本信息
    // 暂时简化处理，返回 false
    return false;
  }
}

// 向后兼容：保持原有的类名作为别名
typedef GeositeManager = RuleSetsManager;
