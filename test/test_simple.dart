import 'dart:convert';
import 'dart:io';

/// 简化的远程订阅测试
void main() async {
  print('[测试] 开始远程订阅功能测试');

  // 测试 Base64 解码
  testBase64Decoding();

  // 测试 URL 验证
  testUrlValidation();

  // 测试 HTTP 请求
  await testHttpRequest();

  print('[测试] 所有测试完成');
}

/// 测试 Base64 解码功能
void testBase64Decoding() {
  print('\n[测试] Base64 解码测试');

  // 测试数据
  const testData = 'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNzd29yZA==@192.168.1.1:8388#TestNode';
  const base64Content = 'c3M6Ly9ZMmhoWTJoaE1qQXRhV1YwWmkxd2IyeDVNVE13TlRwd1lYTnpkMjl5WkE9PUFOREU0T1M0eExqRTZPRE00T0NNVGFhM1UyTmpaQT09DQo=';

  try {
    // 测试直接Base64解码
    final decoded = utf8.decode(base64Decode(base64Content));
    print('✅ Base64解码成功: ${decoded.substring(0, 50)}...');
  } catch (e) {
    print('❌ Base64解码失败: $e');
  }
}

/// 测试 URL 验证
void testUrlValidation() {
  print('\n[测试] URL验证测试');

  final testUrls = [
    'https://example.com/subscription',
    'http://test.local/config',
    'invalid-url',
    'ftp://invalid.com',
  ];

  for (final url in testUrls) {
    final isValid = isValidSubscriptionUrl(url);
    print('${isValid ? '✅' : '❌'} URL: $url');
  }
}

/// 测试HTTP请求
Future<void> testHttpRequest() async {
  print('\n[测试] HTTP请求测试');

  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    // 测试请求到一个公共API
    final request = await client.getUrl(Uri.parse('https://httpbin.org/get'));
    request.headers.add('User-Agent', 'SingBox-VPN/1.0');

    final response = await request.close();

    if (response.statusCode == 200) {
      print('✅ HTTP请求成功，状态码: ${response.statusCode}');

      // 检查响应头
      response.headers.forEach((name, values) {
        if (name.toLowerCase().contains('content')) {
          print('  响应头 $name: ${values.join(', ')}');
        }
      });
    } else {
      print('❌ HTTP请求失败，状态码: ${response.statusCode}');
    }

    client.close();
  } catch (e) {
    print('❌ HTTP请求异常: $e');
  }
}

/// 验证订阅URL格式
bool isValidSubscriptionUrl(String url) {
  try {
    final uri = Uri.parse(url);
    return uri.hasScheme &&
           (uri.scheme == 'http' || uri.scheme == 'https') &&
           uri.hasAuthority;
  } catch (e) {
    return false;
  }
}

/// 提取订阅链接
List<String> extractSubscriptionLinks(String content) {
  final schemes = ['vless://', 'trojan://', 'ss://', 'vmess://',
                  'hysteria://', 'hysteria2://', 'tuic://'];
  final List<String> links = [];

  for (final scheme in schemes) {
    final pattern = RegExp('$scheme[^\\s]+');
    final matches = pattern.allMatches(content);
    for (final match in matches) {
      links.add(match.group(0)!);
    }
  }

  return links;
}