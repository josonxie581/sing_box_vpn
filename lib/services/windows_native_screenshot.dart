import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'qr_decoder.dart';

class WindowsNativeScreenshot {
  /// 使用Windows GDI API截取全屏
  static Future<String?> captureFullScreen() async {
    if (!Platform.isWindows) return null;

    try {
      // 获取桌面窗口句柄
      final hWndDesktop = GetDesktopWindow();
      final hDCDesktop = GetDC(hWndDesktop);

      // 获取屏幕尺寸
      final screenWidth = GetSystemMetrics(SM_CXSCREEN);
      final screenHeight = GetSystemMetrics(SM_CYSCREEN);

      print('屏幕尺寸: ${screenWidth}x$screenHeight');

      // 创建兼容的设备上下文
      final hDCMemory = CreateCompatibleDC(hDCDesktop);

      // 创建位图
      final hBitmap = CreateCompatibleBitmap(hDCDesktop, screenWidth, screenHeight);

      // 选择位图到内存设备上下文
      final hOldBitmap = SelectObject(hDCMemory, hBitmap);

      // 复制屏幕内容到内存位图
      final result = BitBlt(
        hDCMemory, 0, 0,
        screenWidth, screenHeight,
        hDCDesktop, 0, 0,
        SRCCOPY
      );

      if (result == 0) {
        print('BitBlt 失败');
        _cleanup(hDCDesktop, hDCMemory, hBitmap, hOldBitmap, hWndDesktop);
        return null;
      }

      // 获取位图数据
      final bitmapData = await _getBitmapData(hBitmap, screenWidth, screenHeight);

      // 清理资源
      _cleanup(hDCDesktop, hDCMemory, hBitmap, hOldBitmap, hWndDesktop);

      if (bitmapData != null) {
        // 保存为PNG文件
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final screenshotPath = path.join(tempDir.path, 'screenshot_$timestamp.png');

        // 转换为PNG格式并保存
        final pngData = await _convertToPNG(bitmapData, screenWidth, screenHeight);
        if (pngData != null) {
          await File(screenshotPath).writeAsBytes(pngData);
          print('截图保存成功: $screenshotPath');
          return screenshotPath;
        }
      }

      return null;
    } catch (e) {
      print('截图失败: $e');
      return null;
    }
  }

  /// 截取指定区域
  static Future<String?> captureRegion(int x, int y, int width, int height) async {
    if (!Platform.isWindows) return null;

    try {
      // 获取桌面窗口句柄
      final hWndDesktop = GetDesktopWindow();
      final hDCDesktop = GetDC(hWndDesktop);

      // 创建兼容的设备上下文
      final hDCMemory = CreateCompatibleDC(hDCDesktop);

      // 创建位图
      final hBitmap = CreateCompatibleBitmap(hDCDesktop, width, height);

      // 选择位图到内存设备上下文
      final hOldBitmap = SelectObject(hDCMemory, hBitmap);

      // 复制指定区域到内存位图
      final result = BitBlt(
        hDCMemory, 0, 0,
        width, height,
        hDCDesktop, x, y,
        SRCCOPY
      );

      if (result == 0) {
        print('区域截图 BitBlt 失败');
        _cleanup(hDCDesktop, hDCMemory, hBitmap, hOldBitmap, hWndDesktop);
        return null;
      }

      // 获取位图数据
      final bitmapData = await _getBitmapData(hBitmap, width, height);

      // 清理资源
      _cleanup(hDCDesktop, hDCMemory, hBitmap, hOldBitmap, hWndDesktop);

      if (bitmapData != null) {
        // 保存为PNG文件
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final screenshotPath = path.join(tempDir.path, 'region_$timestamp.png');

        // 转换为PNG格式并保存
        final pngData = await _convertToPNG(bitmapData, width, height);
        if (pngData != null) {
          await File(screenshotPath).writeAsBytes(pngData);
          print('区域截图保存成功: $screenshotPath');
          return screenshotPath;
        }
      }

      return null;
    } catch (e) {
      print('区域截图失败: $e');
      return null;
    }
  }

  /// 截图并识别二维码
  static Future<String?> captureAndScanQR() async {
    try {
      final screenshotPath = await captureFullScreen();
      if (screenshotPath == null) return null;

      // 识别二维码
      final qrText = await QrDecoderService.decodeFromFile(screenshotPath);

      // 清理临时文件
      try {
        await File(screenshotPath).delete();
      } catch (e) {
        print('清理临时文件失败: $e');
      }

      return qrText;
    } catch (e) {
      print('截图识别失败: $e');
      return null;
    }
  }

  /// 截取区域并识别二维码
  static Future<String?> captureRegionAndScanQR(int x, int y, int width, int height) async {
    try {
      final screenshotPath = await captureRegion(x, y, width, height);
      if (screenshotPath == null) return null;

      // 识别二维码
      final qrText = await QrDecoderService.decodeFromFile(screenshotPath);

      // 清理临时文件
      try {
        await File(screenshotPath).delete();
      } catch (e) {
        print('清理临时文件失败: $e');
      }

      return qrText;
    } catch (e) {
      print('区域截图识别失败: $e');
      return null;
    }
  }

  /// 获取位图数据
  static Future<Uint8List?> _getBitmapData(int hBitmap, int width, int height) async {
    try {
      // 创建BITMAPINFO结构
      final bitmapInfo = calloc<BITMAPINFO>();
      bitmapInfo.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      bitmapInfo.ref.bmiHeader.biWidth = width;
      bitmapInfo.ref.bmiHeader.biHeight = -height; // 负值表示从上到下
      bitmapInfo.ref.bmiHeader.biPlanes = 1;
      bitmapInfo.ref.bmiHeader.biBitCount = 32; // 32位BGRA
      bitmapInfo.ref.bmiHeader.biCompression = BI_RGB;

      // 获取设备上下文
      final hDC = GetDC(0);

      // 分配内存来存储位图数据
      final dataSize = width * height * 4; // 32位 = 4字节
      final bitmapData = calloc<Uint8>(dataSize);

      // 获取位图数据
      final result = GetDIBits(
        hDC, hBitmap, 0, height,
        bitmapData, bitmapInfo, DIB_RGB_COLORS
      );

      ReleaseDC(0, hDC);
      calloc.free(bitmapInfo);

      if (result != 0) {
        // 转换为Uint8List
        final data = Uint8List.fromList(
          bitmapData.asTypedList(dataSize)
        );
        calloc.free(bitmapData);
        return data;
      } else {
        calloc.free(bitmapData);
        return null;
      }
    } catch (e) {
      print('获取位图数据失败: $e');
      return null;
    }
  }

  /// 转换为PNG格式
  static Future<Uint8List?> _convertToPNG(Uint8List bitmapData, int width, int height) async {
    try {
      // Windows GDI返回的是BGRA格式，需要转换为RGBA
      final rgbaData = Uint8List(bitmapData.length);

      // 将BGRA转换为RGBA
      for (int i = 0; i < bitmapData.length; i += 4) {
        rgbaData[i] = bitmapData[i + 2];     // R = B
        rgbaData[i + 1] = bitmapData[i + 1]; // G = G
        rgbaData[i + 2] = bitmapData[i];     // B = R
        rgbaData[i + 3] = bitmapData[i + 3]; // A = A
      }

      // 创建Image对象
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaData.buffer,
        format: img.Format.uint8,
        numChannels: 4,
      );

      // 编码为PNG
      final pngBytes = img.encodePng(image);
      return Uint8List.fromList(pngBytes);
    } catch (e) {
      print('PNG转换失败: $e');
      return null;
    }
  }

  /// 从BGRA数据创建图像
  static Future<img.Image?> _createImageFromBGRA(Uint8List data, int width, int height) async {
    try {
      // Windows GDI返回的是BGRA格式，需要转换为RGBA
      final rgbaData = Uint8List(data.length);

      // 将BGRA转换为RGBA
      for (int i = 0; i < data.length; i += 4) {
        rgbaData[i] = data[i + 2];     // R = B
        rgbaData[i + 1] = data[i + 1]; // G = G
        rgbaData[i + 2] = data[i];     // B = R
        rgbaData[i + 3] = data[i + 3]; // A = A
      }

      // 创建Image对象
      return img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaData.buffer,
        format: img.Format.uint8,
        numChannels: 4,
      );
    } catch (e) {
      print('创建图像失败: $e');
      return null;
    }
  }

  /// 清理资源
  static void _cleanup(int hDCDesktop, int hDCMemory, int hBitmap, int hOldBitmap, int hWndDesktop) {
    SelectObject(hDCMemory, hOldBitmap);
    DeleteObject(hBitmap);
    DeleteDC(hDCMemory);
    ReleaseDC(hWndDesktop, hDCDesktop);
  }

  /// 获取屏幕尺寸
  static Map<String, int> getScreenSize() {
    final width = GetSystemMetrics(SM_CXSCREEN);
    final height = GetSystemMetrics(SM_CYSCREEN);
    return {'width': width, 'height': height};
  }
}