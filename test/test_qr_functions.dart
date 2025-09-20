import 'dart:io';
import 'lib/services/windows_screen_capture.dart';
import 'lib/services/qr_decoder.dart';

void main() async {
  print('=== QR码功能测试 ===\n');

  // 测试1：剪贴板图片识别
  print('测试1: 剪贴板图片识别');
  print('请复制一个包含二维码的图片到剪贴板，然后按回车继续...');
  stdin.readLineSync();

  final clipboardResult = await WindowsScreenCapture.scanFromClipboardImage();
  if (clipboardResult != null) {
    print('✓ 成功识别剪贴板二维码: $clipboardResult');
  } else {
    print('✗ 剪贴板中没有二维码或识别失败');
  }

  print('\n---\n');

  // 测试2：本地图片文件识别
  print('测试2: 本地图片文件识别');
  print('请输入一个包含二维码的图片文件路径:');
  final imagePath = stdin.readLineSync();

  if (imagePath != null && File(imagePath).existsSync()) {
    final fileResult = await QrDecoderService.decodeFromFile(imagePath);
    if (fileResult != null) {
      print('✓ 成功识别图片二维码: $fileResult');
    } else {
      print('✗ 图片中没有二维码或识别失败');
    }
  } else {
    print('✗ 文件不存在');
  }

  print('\n---\n');

  // 测试3：屏幕截图
  print('测试3: 屏幕截图识别');
  print('准备触发截图工具，请在截图工具中选择包含二维码的区域...');
  print('按回车开始截图:');
  stdin.readLineSync();

  final screenshotResult = await WindowsScreenCapture.captureWithSnippingTool();
  if (screenshotResult != null) {
    print('✓ 成功识别屏幕二维码: $screenshotResult');
  } else {
    print('✗ 屏幕截图失败或没有识别到二维码');
  }

  print('\n测试完成！');
}