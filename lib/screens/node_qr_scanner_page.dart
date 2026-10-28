import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/vpn_config.dart';
import '../providers/vpn_provider_v2.dart';

/// Only import a node URI. Scanning a website never opens or downloads it.
VPNConfig? parseNodeQr(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty ||
      text.length > 16384 ||
      text.contains('\n') ||
      text.contains('\r')) {
    return null;
  }
  // Legacy parsers log exception input; scanned credentials stay out of logs.
  final config = runZoned(
    () => VPNConfig.fromSubscriptionLink(text),
    zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}),
  );
  if (config == null ||
      config.server.trim().isEmpty ||
      config.port < 1 ||
      config.port > 65535) {
    return null;
  }
  return config;
}

Future<bool> scanAndAddNode(BuildContext context) async {
  final provider = context.read<VPNProviderV2>();
  final node = await Navigator.of(context).push<VPNConfig>(
    MaterialPageRoute(builder: (_) => const NodeQrScannerPage()),
  );
  if (!context.mounted || node == null) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('添加扫描到的节点？'),
      content: SingleChildScrollView(
        child: Text(
          '${node.name}\n${node.type.toUpperCase()}\n${node.server}:${node.port}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('添加节点'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await provider.addConfig(node);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('节点已添加')));
    }
    return true;
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存节点失败，请重试')));
    }
    return false;
  }
}

class NodeQrScannerPage extends StatefulWidget {
  const NodeQrScannerPage({super.key});

  @override
  State<NodeQrScannerPage> createState() => _NodeQrScannerPageState();
}

class _NodeQrScannerPageState extends State<NodeQrScannerPage> {
  bool _completed = false;
  String? _message;
  int _cameraAttempt = 0;

  void _onDetect(BarcodeCapture capture) {
    if (_completed || !mounted) return;
    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode) continue;
      final node = parseNodeQr(barcode.rawValue);
      if (node == null) continue;
      _completed = true;
      Navigator.of(context).pop(node);
      return;
    }
    const message = '未识别到有效节点，请扫描节点分享二维码';
    if (_message != message) setState(() => _message = message);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫码添加节点')),
    backgroundColor: Colors.black,
    body: Column(
      children: [
        Expanded(
          // The widget owns its camera controller and handles pause/resume and
          // disposal. No camera is kept alive after this route closes.
          child: MobileScanner(
            key: ValueKey(_cameraAttempt),
            tapToFocus: true,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? '需要相机权限才能扫码。请在系统设置中允许 Gsou 使用相机后重试。'
                          : '无法打开相机，请关闭其他正在使用相机的应用后重试。',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _cameraAttempt++),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _message ?? '将节点二维码放入镜头内，识别后确认添加',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}
