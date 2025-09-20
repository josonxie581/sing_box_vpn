import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/windows_native_screenshot.dart';
import '../services/qr_decoder.dart';

class ScreenshotSelector extends StatefulWidget {
  final Function(String?) onQRDetected;

  const ScreenshotSelector({
    super.key,
    required this.onQRDetected,
  });

  @override
  State<ScreenshotSelector> createState() => _ScreenshotSelectorState();
}

class _ScreenshotSelectorState extends State<ScreenshotSelector> {
  bool _isCapturing = false;
  String? _backgroundImagePath;
  Offset? _startPoint;
  Offset? _endPoint;
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    _initializeScreenshot();
  }

  Future<void> _initializeScreenshot() async {
    setState(() {
      _isCapturing = true;
    });

    try {
      // 获取全屏截图作为背景
      final screenshotPath = await WindowsNativeScreenshot.captureFullScreen();
      if (screenshotPath != null) {
        setState(() {
          _backgroundImagePath = screenshotPath;
          _isCapturing = false;
        });
      } else {
        _showError('截图失败');
      }
    } catch (e) {
      _showError('截图失败: $e');
    }
  }

  void _showError(String message) {
    setState(() {
      _isCapturing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    Navigator.of(context).pop();
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _startPoint = details.localPosition;
      _endPoint = details.localPosition;
      _isSelecting = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _endPoint = details.localPosition;
    });
  }

  void _onPanEnd(DragEndDetails details) async {
    if (_startPoint != null && _endPoint != null) {
      await _captureSelectedRegion();
    }
  }

  Future<void> _captureSelectedRegion() async {
    if (_startPoint == null || _endPoint == null) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      // 计算选择区域
      final double left = _startPoint!.dx < _endPoint!.dx ? _startPoint!.dx : _endPoint!.dx;
      final double top = _startPoint!.dy < _endPoint!.dy ? _startPoint!.dy : _endPoint!.dy;
      final double right = _startPoint!.dx > _endPoint!.dx ? _startPoint!.dx : _endPoint!.dx;
      final double bottom = _startPoint!.dy > _endPoint!.dy ? _startPoint!.dy : _endPoint!.dy;

      final int width = (right - left).round();
      final int height = (bottom - top).round();

      if (width < 10 || height < 10) {
        _showError('选择区域太小');
        return;
      }

      // 获取屏幕尺寸以计算实际坐标
      final screenSize = WindowsNativeScreenshot.getScreenSize();
      if (screenSize == null) {
        _showError('无法获取屏幕尺寸');
        return;
      }

      // 获取当前窗口大小
      final Size windowSize = MediaQuery.of(context).size;

      // 计算缩放比例
      final double scaleX = screenSize['width']! / windowSize.width;
      final double scaleY = screenSize['height']! / windowSize.height;

      // 计算实际屏幕坐标
      final int actualX = (left * scaleX).round();
      final int actualY = (top * scaleY).round();
      final int actualWidth = (width * scaleX).round();
      final int actualHeight = (height * scaleY).round();

      print('选择区域: $actualX, $actualY, ${actualWidth}x$actualHeight');

      // 截取选定区域并识别二维码
      final qrText = await WindowsNativeScreenshot.captureRegionAndScanQR(
        actualX,
        actualY,
        actualWidth,
        actualHeight,
      );

      // 关闭界面并返回结果
      Navigator.of(context).pop();
      widget.onQRDetected(qrText);

    } catch (e) {
      _showError('处理截图失败: $e');
    }
  }

  Widget _buildSelectionOverlay() {
    if (!_isSelecting || _startPoint == null || _endPoint == null) {
      return const SizedBox.shrink();
    }

    final double left = _startPoint!.dx < _endPoint!.dx ? _startPoint!.dx : _endPoint!.dx;
    final double top = _startPoint!.dy < _endPoint!.dy ? _startPoint!.dy : _endPoint!.dy;
    final double width = (_startPoint!.dx - _endPoint!.dx).abs();
    final double height = (_startPoint!.dy - _endPoint!.dy).abs();

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red, width: 2),
          color: Colors.red.withOpacity(0.1),
        ),
        child: Center(
          child: Text(
            '${width.round()}x${height.round()}',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('选择二维码区域'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: _isCapturing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    '正在截图...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : _backgroundImagePath != null
              ? Stack(
                  children: [
                    // 背景截图
                    Positioned.fill(
                      child: GestureDetector(
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
                        onPanEnd: _onPanEnd,
                        child: Image.file(
                          File(_backgroundImagePath!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    // 选择覆盖层
                    _buildSelectionOverlay(),
                    // 说明文字
                    if (!_isSelecting)
                      Positioned(
                        bottom: 50,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '拖动鼠标选择包含二维码的区域',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              : const Center(
                  child: Text(
                    '截图失败',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
    );
  }

  @override
  void dispose() {
    // 清理临时截图文件
    if (_backgroundImagePath != null) {
      try {
        File(_backgroundImagePath!).delete();
      } catch (e) {
        print('清理背景图片失败: $e');
      }
    }
    super.dispose();
  }
}