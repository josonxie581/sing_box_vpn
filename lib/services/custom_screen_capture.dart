import 'dart:io';
import 'windows_native_screenshot.dart';
import 'qr_decoder.dart';

class CustomScreenCapture {
  /// 截取全屏并返回文件路径
  static Future<String?> captureFullScreen() async {
    if (!Platform.isWindows) {
      print('当前平台不支持原生截图');
      return null;
    }

    try {
      return await WindowsNativeScreenshot.captureFullScreen();
    } catch (e) {
      print('全屏截图失败: $e');
      return null;
    }
  }

  /// 截取屏幕并识别二维码
  static Future<String?> captureAndScanQR() async {
    if (!Platform.isWindows) {
      print('当前平台不支持原生截图');
      return null;
    }

    try {
      return await WindowsNativeScreenshot.captureAndScanQR();
    } catch (e) {
      print('截图识别失败: $e');
      return null;
    }
  }

  /// 截取指定区域并识别二维码
  static Future<String?> captureRegion(int x, int y, int width, int height) async {
    if (!Platform.isWindows) {
      print('当前平台不支持原生截图');
      return null;
    }

    try {
      return await WindowsNativeScreenshot.captureRegionAndScanQR(x, y, width, height);
    } catch (e) {
      print('区域截图失败: $e');
      return null;
    }
  }

  /// 获取屏幕尺寸
  static Future<Map<String, int>?> getScreenSize() async {
    if (!Platform.isWindows) {
      return null;
    }

    try {
      return WindowsNativeScreenshot.getScreenSize();
    } catch (e) {
      print('获取屏幕尺寸失败: $e');
      return null;
    }
  }
}