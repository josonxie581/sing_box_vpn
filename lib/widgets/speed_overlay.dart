import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'dart:io' as io show exit;
import 'package:flutter/services.dart' show SystemNavigator;
import 'dart:ffi' as ffi;
import 'package:win32/win32.dart' as win32;
import 'package:ffi/ffi.dart' as pkg_ffi;
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
  bool _showMenu = false;
  Offset _menuPosition = Offset.zero;
  double _menuWidth = 160;

  void _hideMenu() {
    if (_showMenu) {
      setState(() => _showMenu = false);
    }
  }

  Future<void> _exitApp() async {
    // 统一的退出逻辑：优先优雅关闭窗口，失败则兜底强退
    try {
      _hideMenu();
      // 先断开 VPN（若已连接/正在连接），避免残留系统代理/TUN 等副作用
      try {
        final vpn = context.read<VPNProviderV2>();
        if (vpn.isConnected || vpn.isConnecting) {
          await vpn.disconnect().timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          );
          // 给系统清理代理/网络栈一个极短的缓冲
          await Future.delayed(const Duration(milliseconds: 150));
        }
      } catch (_) {
        // 忽略断开异常，继续执行退出
      }
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // 对桌面平台使用 window_manager 关闭/销毁窗口
        await windowManager.destroy();
      } else {
        // 移动端或其他平台
        await SystemNavigator.pop();
      }
    } catch (_) {
      // 兜底，确保进程退出
      io.exit(0);
    }
  }

  Future<void> _openNativeContextMenuWindows() async {
    if (!Platform.isWindows) return;

    // 同步置顶状态用于菜单文案
    final isTop = await windowManager.isAlwaysOnTop();
    if (!mounted) return;

    // 获取当前鼠标屏幕坐标
    final pt = pkg_ffi.calloc<win32.POINT>();
    try {
      win32.GetCursorPos(pt);

      // 创建弹出菜单
      final hMenu = win32.CreatePopupMenu();
      // 准备菜单字符串（UTF-16）
      final restoreText = win32.TEXT('退出');
      // final topText = win32.TEXT(isTop ? '取消置顶' : '置顶');

      // 添加菜单项，使用返回命令模式
      win32.AppendMenu(hMenu, win32.MF_STRING, 1, restoreText);
      // win32.AppendMenu(hMenu, win32.MF_STRING, 2, topText);

      final hwndOwner = win32.GetForegroundWindow();
      final flags =
          win32.TPM_LEFTALIGN |
          win32.TPM_TOPALIGN |
          win32.TPM_RIGHTBUTTON |
          win32.TPM_RETURNCMD;

      final cmd = win32.TrackPopupMenu(
        hMenu,
        flags,
        pt.ref.x,
        pt.ref.y,
        0,
        hwndOwner,
        ffi.Pointer<win32.RECT>.fromAddress(0),
      );

      // 处理结果
      if (cmd == 1) {
        await _exitApp();
      } else if (cmd == 2) {
        await windowManager.setAlwaysOnTop(!isTop);
      }

      // 释放资源
      win32.DestroyMenu(hMenu);
      pkg_ffi.calloc.free(restoreText);
      // pkg_ffi.calloc.free(topText);
    } finally {
      pkg_ffi.calloc.free(pt);
    }
  }

  Future<void> _openLocalMenu(Offset globalPosition) async {
    // 计算相对于本组件的坐标
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);

    // 动态计算菜单尺寸与位置，确保在小窗口内也可见
    final size = box.size;
    final desiredMin = 100.0;
    final desiredMax = 300.0;
    final padding = 4.0; // 边缘留白
    final widthFit = (size.width - padding * 2).clamp(desiredMin, desiredMax);
    // 估算高度（2 个菜单项，每项约 36 高 + 上下 8 padding）
    final estItemHeight = 36.0;
    final estHeight = 8.0 + estItemHeight * 2;

    // 位置约束在可视范围内
    double x = local.dx;
    double y = local.dy;
    final maxLeft = (size.width - widthFit - padding);
    final maxTop = (size.height - estHeight - padding);
    if (x < padding) x = padding;
    if (y < padding) y = padding;
    if (x > maxLeft) x = maxLeft.clamp(padding, size.width - padding);
    if (y > maxTop) y = maxTop.clamp(padding, size.height - padding);

    setState(() {
      _menuWidth = widthFit;
      _menuPosition = Offset(x, y);
      _showMenu = true;
    });
  }

  Widget _buildContextMenu() {
    return Material(
      color: Colors.transparent,
      child:
          Container
          // 菜单外观
          (
            decoration: BoxDecoration(
              color: const Color(0xFF2B2B2B),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(color: const Color(0xFF3C3C3C)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints.tightFor(width: _menuWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MenuItem(
                  label: '退出',
                  onTap: () {
                    _exitApp();
                  },
                ),
                // _MenuItem(
                //   label: _isTopCache ? '取消置顶' : '置顶',
                //   onTap: () async {
                //     await windowManager.setAlwaysOnTop(!_isTopCache);
                //     if (!mounted) return;
                //     setState(() => _isTopCache = !_isTopCache);
                //     _hideMenu();
                //   },
                // ),
              ],
            ),
          ),
    );
  }

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
            behavior: HitTestBehavior.deferToChild,
            onDoubleTap: widget.onRestore,
            onSecondaryTapDown: (details) async {
              if (Platform.isWindows) {
                await _openNativeContextMenuWindows();
              } else {
                await _openLocalMenu(details.globalPosition);
              }
            },
            onPanStart: (_) {
              if (_showMenu) return; // 菜单打开时不触发拖动
              windowManager.startDragging();
            },
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
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
                                  color: const Color.fromARGB(
                                    0,
                                    57,
                                    57,
                                    57,
                                  ).withOpacity(0.2),
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
                  // 点击空白处关闭菜单
                  if (_showMenu)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _hideMenu,
                        onSecondaryTap: _hideMenu,
                      ),
                    ),
                  if (_showMenu)
                    Positioned(
                      left: _menuPosition.dx,
                      top: _menuPosition.dy,
                      child: _buildContextMenu(),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MenuItem({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
