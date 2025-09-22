import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/zxing2.dart';
import 'package:zxing2/qrcode.dart';

class QrDecoderService {
  /// 从文件路径解码二维码文本，失败返回 null
  static Future<String?> decodeFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return decodeFromBytes(bytes);
  }

  /// 从内存字节解码二维码文本，失败返回 null
  static Future<String?> decodeFromBytes(Uint8List data) async {
    try {
      final img.Image? decoded = img.decodeImage(data);
      if (decoded == null) return null;

      img.Image image = decoded;
      final int w = image.width, h = image.height;

      print('原始图片尺寸: ${w}x${h}');

      // 针对不同尺寸的图片采用不同策略
      if (w < 200 || h < 200) {
        // 非常小的图片，先放大
        image = img.copyResize(image, width: w * 3);
        print('图片过小，放大到: ${image.width}x${image.height}');
      } else if (w > 2000 || h > 2000) {
        // 过大的图片，适度缩小但保持清晰度
        const int maxSide = 1500;
        final int longer = w > h ? w : h;
        final scale = maxSide / longer;
        image = img.copyResize(image, width: (w * scale).round());
        print('图片过大，缩小到: ${image.width}x${image.height}');
      }

      // 多策略尝试解码
      // 1) 直接尝试原图
      print('尝试方法1: 直接识别');
      final direct = _tryDecode(image);
      if (direct != null) {
        print('✅ 方法1成功');
        return direct;
      }

      // 2) 二值化处理（针对复杂背景）
      print('尝试方法2: 二值化处理');
      final binarized = _binarizeImage(image);
      final binarizedResult = _tryDecode(binarized) ?? _tryDecode(binarized, inverted: true);
      if (binarizedResult != null) {
        print('✅ 方法2成功');
        return binarizedResult;
      }

      // 3) 锐化处理（针对模糊图像）
      print('尝试方法3: 锐化处理');
      final sharpened = _sharpenImage(image);
      final sharpenedResult = _tryDecode(sharpened) ?? _tryDecode(sharpened, inverted: true);
      if (sharpenedResult != null) {
        print('✅ 方法3成功');
        return sharpenedResult;
      }

      // 4) 反色尝试（应对黑白反转二维码）
      print('尝试方法4: 反色处理');
      final inverted = _tryDecode(image, inverted: true);
      if (inverted != null) {
        print('✅ 方法4成功');
        return inverted;
      }

      // 5) 增强对比度
      print('尝试方法5: 增强对比度');
      final enhanced = img.adjustColor(image, contrast: 2.0);
      final enhancedResult = _tryDecode(enhanced) ?? _tryDecode(enhanced, inverted: true);
      if (enhancedResult != null) {
        print('✅ 方法5成功');
        return enhancedResult;
      }

      // 6) 灰度化处理
      print('尝试方法6: 灰度化');
      final grayscale = img.grayscale(image);
      final grayscaleResult = _tryDecode(grayscale) ?? _tryDecode(grayscale, inverted: true);
      if (grayscaleResult != null) {
        print('✅ 方法6成功');
        return grayscaleResult;
      }

      // 7) 旋转尝试
      print('尝试方法7: 旋转图片');
      for (final angle in const [90, 180, 270]) {
        final rotated = img.copyRotate(image, angle: angle);
        final text = _tryDecode(rotated) ?? _tryDecode(rotated, inverted: true);
        if (text != null) {
          print('✅ 方法7成功 (旋转${angle}度)');
          return text;
        }
      }

      // 8) 高密度二维码特殊处理
      print('尝试方法8: 高密度二维码处理');
      if (w >= 300 && h >= 300) {
        // 尝试不同的缩放级别
        for (final scale in [0.8, 1.2, 1.5]) {
          final resized = img.copyResize(image, width: (w * scale).round());
          final resizedResult = _tryDecode(resized) ?? _tryDecode(resized, inverted: true);
          if (resizedResult != null) {
            print('✅ 方法8成功 (缩放${scale}x)');
            return resizedResult;
          }
        }
      }

      print('❌ 所有方法都失败了');
      return null;
    } catch (e) {
      print('二维码解码错误: $e');
      return null;
    }
  }

  /// 二值化图像
  static img.Image _binarizeImage(img.Image image) {
    final result = img.Image(width: image.width, height: image.height);

    // 计算平均亮度作为阈值
    int totalLuminance = 0;
    int pixelCount = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
        totalLuminance += luminance;
        pixelCount++;
      }
    }

    final threshold = totalLuminance ~/ pixelCount;

    // 应用二值化
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();

        if (luminance > threshold) {
          result.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        } else {
          result.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
    }

    return result;
  }

  /// 锐化图像
  static img.Image _sharpenImage(img.Image image) {
    // 使用拉普拉斯锐化核
    const kernel = [
      0, -1, 0,
      -1, 5, -1,
      0, -1, 0,
    ];

    return img.convolution(image, filter: kernel);
  }

  /// 执行一次解码尝试
  static String? _tryDecode(img.Image image, {bool inverted = false}) {
    try {
      final pixels = _toArgbInt32(image);
      LuminanceSource source = RGBLuminanceSource(
        image.width,
        image.height,
        pixels,
      );
      if (inverted) {
        source = InvertedLuminanceSource(source);
      }

      // 尝试两种不同的二值化器以提高成功率
      // 1. 先尝试 HybridBinarizer（更鲁棒）
      try {
        final bitmap = BinaryBitmap(HybridBinarizer(source));
        final reader = QRCodeReader();
        final result = reader.decode(bitmap);
        return result.text;
      } catch (_) {
        // 2. 如果失败，尝试 GlobalHistogramBinarizer
        try {
          final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
          final reader = QRCodeReader();
          final result = reader.decode(bitmap);
          return result.text;
        } catch (_) {
          return null;
        }
      }
    } catch (_) {
      return null;
    }
  }

  /// 将 image 的像素转换为 ARGB(0xFFRRGGBB) 的 Int32List，符合 ZXing 的期望
  static Int32List _toArgbInt32(img.Image image) {
    final rgba = image.convert(numChannels: 4);
    final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
    final length = bytes.length ~/ 4;
    final out = Int32List(length);
    int j = 0;
    for (int i = 0; i < bytes.length; i += 4) {
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      // 忽略 alpha，统一视为不透明
      out[j++] = 0xFF000000 | (r << 16) | (g << 8) | b;
    }
    return out;
  }
}
