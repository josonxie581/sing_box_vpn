import 'dart:io';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'qr_decoder.dart';

class OfficialScreenCapture {
  /// 截取全屏并返回文件路径
  static Future<String?> captureFullScreen() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final screenshotPath = path.join(tempDir.path, 'fullscreen_$timestamp.png');

      print('开始全屏截图...');

      final capturedData = await screenCapturer.capture(
        mode: CaptureMode.screen,
        imagePath: screenshotPath,
        copyToClipboard: false,
      );

      if (capturedData != null && capturedData.imagePath != null) {
        final file = File(capturedData.imagePath!);
        if (await file.exists()) {
          print('截图保存成功: ${capturedData.imagePath}');
          return capturedData.imagePath;
        }
      }

      print('截图失败');
      return null;
    } catch (e) {
      print('全屏截图失败: $e');
      return null;
    }
  }

  /// 截取指定区域
  static Future<String?> captureRegion() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final screenshotPath = path.join(tempDir.path, 'region_$timestamp.png');

      print('开始区域截图...');

      final capturedData = await screenCapturer.capture(
        mode: CaptureMode.region,
        imagePath: screenshotPath,
        copyToClipboard: false,
      );

      if (capturedData != null && capturedData.imagePath != null) {
        final file = File(capturedData.imagePath!);
        if (await file.exists()) {
          print('区域截图保存成功: ${capturedData.imagePath}');
          return capturedData.imagePath;
        }
      }

      print('区域截图失败');
      return null;
    } catch (e) {
      print('区域截图失败: $e');
      return null;
    }
  }

  /// 截取全屏并识别二维码
  static Future<String?> captureAndScanQR() async {
    try {
      final screenshotPath = await captureFullScreen();
      if (screenshotPath == null) {
        return null;
      }

      print('开始识别二维码...');
      final qrText = await QrDecoderService.decodeFromFile(screenshotPath);

      // 清理临时文件
      try {
        await File(screenshotPath).delete();
      } catch (e) {
        print('清理临时文件失败: $e');
      }

      if (qrText != null) {
        print('二维码识别成功: $qrText');
      } else {
        print('未识别到二维码');
      }

      return qrText;
    } catch (e) {
      print('截图识别失败: $e');
      return null;
    }
  }

  /// 截取区域并识别二维码
  static Future<String?> captureRegionAndScanQR() async {
    try {
      final screenshotPath = await captureRegion();
      if (screenshotPath == null) {
        return null;
      }

      print('开始识别区域二维码...');
      final qrText = await QrDecoderService.decodeFromFile(screenshotPath);

      // 清理临时文件
      try {
        await File(screenshotPath).delete();
      } catch (e) {
        print('清理临时文件失败: $e');
      }

      if (qrText != null) {
        print('区域二维码识别成功: $qrText');
      } else {
        print('区域中未识别到二维码');
      }

      return qrText;
    } catch (e) {
      print('区域截图识别失败: $e');
      return null;
    }
  }

  /// 检查是否支持截图
  static Future<bool> isAccessAllowed() async {
    try {
      return await screenCapturer.isAccessAllowed();
    } catch (e) {
      print('检查截图权限失败: $e');
      return false;
    }
  }

  /// 请求截图权限
  static Future<void> requestAccess() async {
    try {
      await screenCapturer.requestAccess();
    } catch (e) {
      print('请求截图权限失败: $e');
    }
  }
}