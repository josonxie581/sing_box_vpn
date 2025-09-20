import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'qr_decoder.dart';

class WindowsScreenCapture {
  /// 使用 Windows Snipping Tool 截图并识别二维码
  static Future<String?> captureWithSnippingTool() async {
    if (!Platform.isWindows) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final screenshotPath = path.join(tempDir.path, 'screenshot_$timestamp.png');

      // PowerShell 脚本：触发截图，等待完成，从剪贴板获取图片
      final script = '''
# 触发 Windows 截图工具
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

public class ScreenCapture {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const int VK_LWIN = 0x5B;
    public const int VK_SHIFT = 0x10;
    public const int S_KEY = 0x53;
    public const int KEYEVENTF_KEYUP = 0x0002;

    public static void TriggerSnippingTool() {
        // 按下 Win+Shift+S
        keybd_event(VK_LWIN, 0, 0, UIntPtr.Zero);
        Thread.Sleep(50);
        keybd_event(VK_SHIFT, 0, 0, UIntPtr.Zero);
        Thread.Sleep(50);
        keybd_event(S_KEY, 0, 0, UIntPtr.Zero);
        Thread.Sleep(50);

        // 释放按键
        keybd_event(S_KEY, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(50);
        keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(50);
        keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
"@ -ReferencedAssemblies System.Drawing, System.Windows.Forms

# 触发截图
[ScreenCapture]::TriggerSnippingTool()

# 等待用户完成截图（最多30秒）
Add-Type -AssemblyName System.Windows.Forms
\$maxWait = 30
\$waited = 0

while (\$waited -lt \$maxWait) {
    Start-Sleep -Seconds 1
    \$waited++

    # 检查剪贴板是否有图片
    if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
        \$image = [System.Windows.Forms.Clipboard]::GetImage()
        if (\$image -ne \$null) {
            \$image.Save('$screenshotPath', [System.Drawing.Imaging.ImageFormat]::Png)
            \$image.Dispose()
            Write-Output "SUCCESS"
            exit 0
        }
    }
}

Write-Output "TIMEOUT"
''';

      // 执行 PowerShell 脚本
      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: true,
      );

      print('截图脚本输出: ${result.stdout}');
      print('截图脚本错误: ${result.stderr}');

      if (result.stdout.toString().trim() == "SUCCESS") {
        final file = File(screenshotPath);
        if (await file.exists()) {
          // 识别二维码
          final qrText = await QrDecoderService.decodeFromFile(screenshotPath);

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
      print('Windows 截图失败: $e');
      return null;
    }
  }

  /// 从剪贴板获取图片并识别二维码
  static Future<String?> scanFromClipboardImage() async {
    if (!Platform.isWindows) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imagePath = path.join(tempDir.path, 'clipboard_$timestamp.png');

      // PowerShell 脚本：从剪贴板获取图片
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
    \$image = [System.Windows.Forms.Clipboard]::GetImage()
    if (\$image -ne \$null) {
        \$image.Save('$imagePath', [System.Drawing.Imaging.ImageFormat]::Png)
        \$image.Dispose()
        Write-Output "SUCCESS"
    } else {
        Write-Output "NO_IMAGE"
    }
} else {
    Write-Output "NO_IMAGE"
}
''';

      // 执行 PowerShell 脚本
      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: true,
      );

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
      print('剪贴板图片识别失败: $e');
      return null;
    }
  }

  /// 捕获全屏并识别二维码
  static Future<String?> captureFullScreen() async {
    if (!Platform.isWindows) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final screenshotPath = path.join(tempDir.path, 'fullscreen_$timestamp.png');

      // PowerShell 脚本：捕获全屏
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 获取主屏幕边界
\$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

# 创建位图
\$bitmap = New-Object System.Drawing.Bitmap(\$bounds.Width, \$bounds.Height)

# 创建图形对象并截图
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$bounds.Location, [System.Drawing.Point]::Empty, \$bounds.Size)

# 保存图片
\$bitmap.Save('$screenshotPath', [System.Drawing.Imaging.ImageFormat]::Png)

# 清理
\$graphics.Dispose()
\$bitmap.Dispose()

Write-Output "SUCCESS"
''';

      // 执行 PowerShell 脚本
      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: true,
      );

      if (result.stdout.toString().trim() == "SUCCESS") {
        final file = File(screenshotPath);
        if (await file.exists()) {
          // 识别二维码
          final qrText = await QrDecoderService.decodeFromFile(screenshotPath);

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
      print('全屏截图失败: $e');
      return null;
    }
  }
}