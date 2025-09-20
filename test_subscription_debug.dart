import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// 测试订阅下载和解析
void main() async {
  // 测试URL（替换为你实际使用的订阅URL）
  const testUrl = 'https://example.com/subscription'; // 请替换为实际URL

  print('开始测试订阅下载...');

  try {
    final client = http.Client();
    final headers = {
      'User-Agent': 'clash-verge-rev/1.7.7',
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'identity',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Connection': 'keep-alive',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'cross-site',
    };

    print('正在下载订阅: $testUrl');

    final response = await client
        .get(Uri.parse(testUrl), headers: headers)
        .timeout(Duration(seconds: 30));

    client.close();

    if (response.statusCode != 200) {
      print('HTTP错误: ${response.statusCode} ${response.reasonPhrase}');
      return;
    }

    print('下载完成，状态码: ${response.statusCode}，内容长度: ${response.body.length}');

    // 输出响应头
    print('\n响应头信息:');
    response.headers.forEach((key, value) {
      print('$key: $value');
    });

    // 检查订阅信息
    print('\n解析订阅信息...');
    for (final key in response.headers.keys) {
      final lowerKey = key.toLowerCase();
      if (lowerKey.contains('subscription') || lowerKey.contains('userinfo')) {
        print('找到订阅相关头部: $key = ${response.headers[key]}');
      }
    }

    // 分析内容
    print('\n分析内容...');
    String content = response.body;

    // 检查是否是base64
    bool isBase64 = _isBase64(content);
    print('内容是Base64编码: $isBase64');

    if (isBase64) {
      try {
        content = utf8.decode(base64.decode(content));
        print('Base64解码成功');
      } catch (e) {
        print('Base64解码失败: $e');
      }
    }

    // 输出前10行内容
    final lines = content.split('\n');
    print('总行数: ${lines.length}');
    print('前10行内容:');
    for (int i = 0; i < lines.length && i < 10; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        print('行${i + 1}: ${line.length > 150 ? line.substring(0, 150) + '...' : line}');
      }
    }

    // 检查协议类型分布
    final protocolCounts = <String, int>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        final schemes = ['ss://', 'vmess://', 'vless://', 'trojan://', 'tuic://', 'hysteria://', 'hysteria2://', 'hy2://'];
        for (final scheme in schemes) {
          if (trimmed.toLowerCase().startsWith(scheme)) {
            protocolCounts[scheme] = (protocolCounts[scheme] ?? 0) + 1;
            break;
          }
        }
      }
    }

    print('\n协议类型统计:');
    protocolCounts.forEach((protocol, count) {
      print('$protocol: $count');
    });

  } catch (e) {
    print('测试失败: $e');
  }
}

/// 检查是否为base64编码
bool _isBase64(String content) {
  final base64Pattern = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');

  if (!base64Pattern.hasMatch(content.replaceAll(RegExp(r'\s'), ''))) {
    return false;
  }

  try {
    final sample = content.replaceAll(RegExp(r'\s'), '');
    if (sample.length < 4) return false;

    base64.decode(sample.substring(0, (sample.length ~/ 4) * 4));
    return true;
  } catch (e) {
    return false;
  }
}