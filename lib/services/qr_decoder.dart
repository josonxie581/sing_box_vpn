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

      // 过大的图片先等比缩放，提升解码稳定性与速度（例如 > 2000px）
      img.Image image = decoded;
      const int maxSide = 1800; // 保持清晰度的同时避免过大
      final int w = image.width, h = image.height;
      final int longer = w > h ? w : h;
      if (longer > maxSide) {
        final scale = maxSide / longer;
        image = img.copyResize(image, width: (w * scale).round());
      }

      // 多策略尝试解码
      // 1) 直接尝试
      final direct = _tryDecode(image);
      if (direct != null) return direct;

      // 2) 反色尝试（应对黑白反转二维码）
      final inverted = _tryDecode(image, inverted: true);
      if (inverted != null) return inverted;

      // 3) 旋转尝试（90/180/270）
      for (final angle in const [90, 180, 270]) {
        final rotated = img.copyRotate(image, angle: angle);
        final text = _tryDecode(rotated) ?? _tryDecode(rotated, inverted: true);
        if (text != null) return text;
      }

      return null;
    } catch (_) {
      return null;
    }
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
      // HybridBinarizer 通常比 GlobalHistogramBinarizer 更鲁棒
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final reader = QRCodeReader();
      final result = reader.decode(bitmap);
      return result.text;
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
