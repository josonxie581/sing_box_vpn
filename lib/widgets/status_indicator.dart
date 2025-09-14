import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/app_theme.dart';

class StatusIndicator extends StatefulWidget {
  final bool isConnected;
  final Animation<double> pulseAnimation;

  const StatusIndicator({
    super.key,
    required this.isConnected,
    required this.pulseAnimation,
  });

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    
    if (widget.isConnected) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected && !oldWidget.isConnected) {
      _rotationController.repeat();
    } else if (!widget.isConnected && oldWidget.isConnected) {
      _rotationController.stop();
      _rotationController.reset();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.isConnected
                ? [
                    BoxShadow(
                      color: AppTheme.successGreen.withOpacity(0.3),
                      blurRadius: 30 * widget.pulseAnimation.value,
                      spreadRadius: 10 * widget.pulseAnimation.value,
                    ),
                  ]
                : [],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 外圈动画
              if (widget.isConnected)
                AnimatedBuilder(
                  animation: _rotationController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _rotationController.value * 2 * math.pi,
                      child: CustomPaint(
                        size: const Size(120, 120),
                        painter: _ArcPainter(
                          color: AppTheme.successGreen.withOpacity(0.3),
                        ),
                      ),
                    );
                  },
                ),
              
              // 中圈
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.isConnected
                          ? AppTheme.successGreen.withOpacity(0.1)
                          : AppTheme.bgSurface.withOpacity(0.5),
                      widget.isConnected
                          ? AppTheme.successGreen.withOpacity(0.05)
                          : AppTheme.bgCard.withOpacity(0.3),
                    ],
                  ),
                  border: Border.all(
                    color: widget.isConnected
                        ? AppTheme.successGreen.withOpacity(0.5)
                        : AppTheme.borderColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
              ),
              
              // 内圈
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.isConnected
                        ? [
                            AppTheme.successGreen,
                            AppTheme.successGreen.withBlue(100),
                          ]
                        : [
                            AppTheme.bgCard,
                            AppTheme.bgSurface,
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.isConnected
                          ? AppTheme.successGreen.withOpacity(0.4)
                          : Colors.transparent,
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  widget.isConnected ? Icons.shield : Icons.shield_outlined,
                  size: 40,
                  color: widget.isConnected
                      ? AppTheme.bgDark
                      : AppTheme.textHint,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;

  _ArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 绘制多个弧形
    for (int i = 0; i < 4; i++) {
      final startAngle = i * math.pi / 2;
      final sweepAngle = math.pi / 3;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}