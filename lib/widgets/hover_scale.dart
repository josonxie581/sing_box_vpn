import 'package:flutter/material.dart';

/// 一个简单的悬停缩放 + 轻微提升阴影效果的封装
/// 用于桌面端鼠标经过交互式卡片时的反馈。
class HoverScale extends StatefulWidget {
  const HoverScale({
    super.key,
    required this.child,
    this.scale = 1.03,
    this.duration = const Duration(milliseconds: 160),
    this.curve = Curves.easeOut,
    this.enabled = true,
    this.highlight = true,
    this.borderRadius = 16,
    this.neonStart = const Color(0xFF00D4FF),
    this.neonEnd = const Color(0xFFFF00FF),
    this.highlightBlur = 18,
  });

  final Widget child;
  final double scale;
  final Duration duration;
  final Curve curve;
  final bool enabled;
  final bool highlight; // 是否展示渐变描边 + 光晕
  final double borderRadius;
  final Color neonStart;
  final Color neonEnd;
  final double highlightBlur;

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hovering = false;

  void _setHover(bool v) {
    if (!widget.enabled) return;
    if (_hovering != v) {
      setState(() => _hovering = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaleChild = AnimatedContainer(
      duration: widget.duration,
      curve: widget.curve,
      transform: Matrix4.identity()..scale(_hovering ? widget.scale : 1.0),
      transformAlignment: Alignment.center,
      child: widget.child,
    );

    Widget wrapped = Stack(
      clipBehavior: Clip.none,
      children: [
        // 渐变高亮边框（通过一个 Positioned 填充 + Opacity 实现淡入，不改变原始布局大小）
        AnimatedOpacity(
          duration: widget.duration,
          curve: widget.curve,
          opacity: widget.highlight && _hovering ? 1.0 : 0.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              gradient: LinearGradient(
                colors: [widget.neonStart, widget.neonEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            // 利用内边距 + 裁剪形成类似描边效果（底层是渐变，上层再放实际内容卡）
            padding: const EdgeInsets.all(1.2),
            child: AnimatedContainer(
              duration: widget.duration,
              curve: widget.curve,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(widget.borderRadius - 1.2),
                boxShadow: widget.highlight && _hovering
                    ? [
                        BoxShadow(
                          color: widget.neonStart.withOpacity(0.35),
                          blurRadius: widget.highlightBlur,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: widget.neonEnd.withOpacity(0.2),
                          blurRadius: widget.highlightBlur * 1.6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius - 2),
                child: scaleChild,
              ),
            ),
          ),
        ),
        // 非 hover 状态下直接显示子内容（避免由于渐变容器包裹导致的布局尺寸变化）
        if (!(widget.highlight && _hovering)) scaleChild,
      ],
    );

    wrapped = MouseRegion(
      cursor: widget.enabled && _hovering
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: wrapped,
    );

    return wrapped;
  }
}
