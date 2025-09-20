import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'qr_decoder.dart';
import 'simple_qr_functions.dart';

class SmartScreenshotService extends StatefulWidget {
  final Function(String?) onQRDetected;
  final Widget child;

  const SmartScreenshotService({
    super.key,
    required this.onQRDetected,
    required this.child,
  });

  @override
  State<SmartScreenshotService> createState() => _SmartScreenshotServiceState();
}

class _SmartScreenshotServiceState extends State<SmartScreenshotService> {
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    setState(() {
      _isListening = true;
    });
  }

  void _stopListening() {
    setState(() {
      _isListening = false;
    });
  }

  Future<void> _handleScreenshotDetected() async {
    print('检测到截图事件');

    // 等待一小段时间确保截图已保存到剪贴板
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // 尝试从剪贴板获取图片
      final qrText = await SimpleQRFunctions.getClipboardImage();

      if (qrText != null && qrText.trim().isNotEmpty) {
        print('从截图中识别到二维码: $qrText');
        widget.onQRDetected(qrText);
      } else {
        print('截图中未识别到二维码');
        widget.onQRDetected(null);
      }
    } catch (e) {
      print('处理截图失败: $e');
      widget.onQRDetected(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 由于capture_detector插件在Windows上不可用，直接返回子组件
    // 可以考虑使用其他方式实现截图检测
    return widget.child;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }
}

// 独立的截图检测服务
class ScreenshotDetectorService {
  static bool _isInitialized = false;
  static Function(String?)? _onQRDetected;

  /// 初始化截图检测服务
  static void initialize({Function(String?)? onQRDetected}) {
    _onQRDetected = onQRDetected;
    _isInitialized = true;
  }

  /// 启动截图检测
  static Future<String?> startCapture() async {
    if (!_isInitialized) {
      throw Exception('ScreenshotDetectorService not initialized');
    }

    try {
      // 等待用户截图
      print('等待用户截图...');

      // 这里可以显示提示信息
      return await _waitForScreenshot();
    } catch (e) {
      print('截图检测失败: $e');
      return null;
    }
  }

  static Future<String?> _waitForScreenshot() async {
    // 创建一个 Completer 来等待截图
    String? result;
    bool completed = false;

    // 监听剪贴板变化（简化实现）
    for (int i = 0; i < 30; i++) { // 最多等待30秒
      await Future.delayed(const Duration(seconds: 1));

      if (completed) break;

      try {
        // 检查剪贴板是否有新图片
        final qrText = await SimpleQRFunctions.getClipboardImage();
        if (qrText != null && qrText.trim().isNotEmpty) {
          result = qrText;
          completed = true;
          break;
        }
      } catch (e) {
        // 继续等待
      }
    }

    return result;
  }

  /// 手动触发截图检测
  static Future<String?> detectFromClipboard() async {
    try {
      // 直接从剪贴板检测
      final qrText = await SimpleQRFunctions.getClipboardImage();
      return qrText;
    } catch (e) {
      print('从剪贴板检测失败: $e');
      return null;
    }
  }
}