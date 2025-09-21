import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/vpn_provider_v2.dart';
import '../services/improved_traffic_stats_service.dart';

class SpeedOverlay extends StatefulWidget {
  final VoidCallback onRestore;
  const SpeedOverlay({super.key, required this.onRestore});

  @override
  State<SpeedOverlay> createState() => _SpeedOverlayState();
}

class _SpeedOverlayState extends State<SpeedOverlay> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<VPNProviderV2>(
      builder: (context, vpn, child) {
        final up = ImprovedTrafficStatsService.formatSpeed(vpn.uploadSpeed);
        final down = ImprovedTrafficStatsService.formatSpeed(vpn.downloadSpeed);

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onDoubleTap: widget.onRestore,
            onPanStart: (_) {
              windowManager.startDragging();
            },
            child: Material(
              type: MaterialType.transparency,
              child: Align(
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  // padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    // color: _isHovered
                    //     ? const Color.fromARGB(0, 86, 85, 85) // 更深的黑色背景
                    //     : const Color.fromARGB(135, 70, 69, 69), // 半透明黑色背景
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _isHovered
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withOpacity(0.2),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 上传速度
                      Icon(
                        Icons.arrow_upward_rounded,
                        size: 14,
                        color: const Color(
                          0xFF00D4FF,
                        ).withOpacity(_isHovered ? 1.0 : 0.8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        up,
                        style: TextStyle(
                          fontSize: 16,
                          color: const Color(
                            0xFF00D4FF,
                          ).withOpacity(_isHovered ? 1.0 : 0.9),
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Consolas',
                          decoration: TextDecoration.none, // 去掉下划线
                          height: 1.2, // 调整行高使文字垂直居中
                        ),
                      ),

                      const SizedBox(width: 12),

                      // 下载速度
                      Icon(
                        Icons.arrow_downward_rounded,
                        size: 14,
                        color: const Color(
                          0xFF00FF88,
                        ).withOpacity(_isHovered ? 1.0 : 0.8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        down,
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(
                            0xFF00FF88,
                          ).withOpacity(_isHovered ? 1.0 : 0.9),
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Consolas',
                          decoration: TextDecoration.none, // 去掉下划线
                          height: 1.2, // 调整行高使文字垂直居中
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
