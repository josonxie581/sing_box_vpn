import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'qr_decoder.dart';

class SimpleQRFunctions {
  /// 从剪贴板读取文本（如果是链接则直接返回）
  static Future<String?> getClipboardText() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        final text = clipboardData.text!.trim();
        if (text.isNotEmpty && _isValidProxyLink(text)) {
          return text;
        }
      }
      return null;
    } catch (e) {
      print('读取剪贴板失败: $e');
      return null;
    }
  }

  /// 使用PowerShell从剪贴板获取图片
  static Future<String?> getClipboardImage() async {
    if (!Platform.isWindows) return null;

    try {
      // 创建临时文件
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imagePath = '${tempDir.path}\\clipboard_$timestamp.png';

      // 改进的PowerShell 脚本，增强兼容性
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try {
    # 确保剪贴板包含图片
    if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
        \$image = [System.Windows.Forms.Clipboard]::GetImage()
        if (\$image -ne \$null) {
            # 确保保存为PNG格式以保持质量
            \$image.Save('$imagePath', [System.Drawing.Imaging.ImageFormat]::Png)
            \$image.Dispose()
            Write-Output "SUCCESS"
        } else {
            Write-Output "NO_IMAGE_OBJECT"
        }
    } elseif ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
        # 如果剪贴板包含文件，检查是否为图片文件
        \$files = [System.Windows.Forms.Clipboard]::GetFileDropList()
        foreach (\$file in \$files) {
            if (\$file -match '\\.(png|jpg|jpeg|bmp|gif)\$') {
                \$image = [System.Drawing.Image]::FromFile(\$file)
                \$image.Save('$imagePath', [System.Drawing.Imaging.ImageFormat]::Png)
                \$image.Dispose()
                Write-Output "SUCCESS"
                break
            }
        }
        if (-not (Test-Path '$imagePath')) {
            Write-Output "NO_IMAGE_FILE"
        }
    } else {
        Write-Output "NO_IMAGE_IN_CLIPBOARD"
    }
} catch {
    Write-Output "ERROR: \$_"
}
''';

      // 执行PowerShell
      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: true,
      );

      print('剪贴板脚本输出: ${result.stdout}');
      if (result.stderr.toString().isNotEmpty) {
        print('剪贴板脚本错误: ${result.stderr}');
      }

      if (result.stdout.toString().trim() == "SUCCESS") {
        final file = File(imagePath);
        if (await file.exists()) {
          // 识别二维码
          final qrText = await QrDecoderService.decodeFromFile(imagePath);

          // 清理临时文件
          try {
            await file.delete();
          } catch (e) {
            print('清理临时文件失败: $e');
          }

          return qrText;
        }
      }

      return null;
    } catch (e) {
      print('剪贴板图片获取失败: $e');
      return null;
    }
  }

  /// 简单截图：让用户手动截图到剪贴板，然后读取
  static Future<String?> captureFromClipboard() async {
    if (!Platform.isWindows) return null;

    try {
      // 使用简单的方法：直接从剪贴板读取
      return await getClipboardImage();
    } catch (e) {
      print('截图功能失败: $e');
      return null;
    }
  }

  /// 检查是否是有效的代理链接
  static bool _isValidProxyLink(String text) {
    final validPrefixes = [
      'ss://',
      'ssr://',
      'vmess://',
      'vless://',
      'trojan://',
      'tuic://',
      'hysteria://',
      'hysteria2://',
      'wireguard://',
      'http://',
      'https://',
    ];

    return validPrefixes.any((prefix) => text.toLowerCase().startsWith(prefix));
  }
}