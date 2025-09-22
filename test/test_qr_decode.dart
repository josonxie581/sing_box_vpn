import 'dart:io';
import '../lib/services/qr_decoder.dart';
import '../lib/services/simple_qr_functions.dart';

void main() async {
  print('开始测试二维码识别功能...\n');

  // 测试1: 测试剪贴板文本读取
  print('测试1: 剪贴板文本读取');
  print('请将代理链接复制到剪贴板，然后按Enter继续...');
  stdin.readLineSync();

  final text = await SimpleQRFunctions.getClipboardText();
  if (text != null) {
    print('✅ 成功从剪贴板读取文本: ${text.substring(0, 50)}...');
  } else {
    print('❌ 未能从剪贴板读取文本');
  }

  print('\n' + '='*50 + '\n');

  // 测试2: 测试剪贴板图片读取
  print('测试2: 剪贴板图片二维码识别');
  print('请截图一个二维码图片到剪贴板，然后按Enter继续...');
  stdin.readLineSync();

  final qrText = await SimpleQRFunctions.getClipboardImage();
  if (qrText != null) {
    print('✅ 成功从剪贴板图片识别二维码:');
    print('内容: ${qrText.substring(0, 100.clamp(0, qrText.length))}...');
  } else {
    print('❌ 未能从剪贴板图片识别二维码');
  }

  print('\n' + '='*50 + '\n');

  // 测试3: 测试文件二维码识别
  print('测试3: 文件二维码识别');
  print('请输入二维码图片文件路径（或按Enter跳过）:');
  final filePath = stdin.readLineSync();

  if (filePath != null && filePath.isNotEmpty) {
    final file = File(filePath);
    if (await file.exists()) {
      final fileQrText = await QrDecoderService.decodeFromFile(filePath);
      if (fileQrText != null) {
        print('✅ 成功从文件识别二维码:');
        print('内容: ${fileQrText.substring(0, 100.clamp(0, fileQrText.length))}...');
      } else {
        print('❌ 未能从文件识别二维码');
      }
    } else {
      print('文件不存在: $filePath');
    }
  }

  print('\n测试完成！');
}