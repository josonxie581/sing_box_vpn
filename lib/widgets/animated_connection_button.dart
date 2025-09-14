import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AnimatedConnectionButton extends StatefulWidget {
  final bool isConnected;
  final bool isConnecting; // 连接中
  final bool isDisconnecting; // 断开中
  final VoidCallback onTap;
  final double size;

  const AnimatedConnectionButton({
    super.key,
    required this.isConnected,
    required this.isConnecting,
    required this.isDisconnecting,
    required this.onTap,
    this.size = 80,
  });

  @override
  State<AnimatedConnectionButton> createState() =>
      _AnimatedConnectionButtonState();
}

class _AnimatedConnectionButtonState extends State<AnimatedConnectionButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _glowController;

  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _glowAnimation;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();

    // 脉冲动画控制器
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // 旋转动画控制器
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // 发光动画控制器
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _updateAnimations();
  }

  void _updateAnimations() {
    final busy = widget.isConnecting || widget.isDisconnecting;
    if (widget.isConnected) {
      _pulseController.repeat(reverse: true);
      _glowController.forward();
    } else if (busy) {
      // 连接或断开中：弱一点的呼吸效果
      _pulseController.repeat(reverse: true);
      _glowController.forward();
    } else {
      _pulseController.stop();
      _pulseController.reset();
      _glowController.reverse();
    }

    if (widget.isConnecting) {
      _rotationController.repeat();
    } else if (widget.isDisconnecting) {
      // 断开时用较慢旋转表示回收中
      _rotationController.duration = const Duration(milliseconds: 2600);
      _rotationController.repeat();
    } else {
      _rotationController.duration = const Duration(milliseconds: 2000);
      _rotationController.stop();
      _rotationController.reset();
    }
  }

  @override
  void didUpdateWidget(AnimatedConnectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isConnected != widget.isConnected ||
        oldWidget.isConnecting != widget.isConnecting ||
        oldWidget.isDisconnecting != widget.isDisconnecting) {
      _updateAnimations();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Color _getButtonColor() {
    if (widget.isConnected) return AppTheme.successGreen;
    if (widget.isConnecting) return AppTheme.warningOrange; // 连接中橙色
    if (widget.isDisconnecting) return Colors.redAccent; // 断开中红色提示
    return const Color(0xFF6B7280);
  }

  Color _getButtonSecondaryColor() {
    if (widget.isConnected) return AppTheme.successGreen.withOpacity(0.7);
    if (widget.isConnecting) return AppTheme.primaryNeon;
    if (widget.isDisconnecting) return Colors.redAccent.withOpacity(0.7);
    return const Color(0xFF4B5563);
  }

  IconData _getIcon() {
    if (widget.isConnected) return Icons.shield_outlined;
    if (widget.isConnecting) return Icons.sync;
    if (widget.isDisconnecting) return Icons.sync_disabled; // 或换成自定义图标
    return Icons.power_settings_new;
  }

  String _getStatusText() {
    if (widget.isConnected) return '已连接';
    if (widget.isConnecting) return '连接中...';
    if (widget.isDisconnecting) return '断开中...';
    return '点击连接';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _pulseAnimation,
        _rotationAnimation,
        _glowAnimation,
      ]),
      builder: (context, child) {
        return GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: Transform.scale(
            scale: _isPressed ? 0.95 : 1.0,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  // 主阴影
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  // 发光效果
                  if (widget.isConnected || widget.isConnecting)
                    BoxShadow(
                      color: _getButtonColor().withOpacity(
                        0.4 * _glowAnimation.value,
                      ),
                      blurRadius: 30 * _glowAnimation.value,
                      spreadRadius: 2 * _glowAnimation.value,
                    ),
                ],
              ),
              child: Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [_getButtonColor(), _getButtonSecondaryColor()],
                      stops: const [0.0, 1.0],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.1),
                          Colors.transparent,
                          Colors.black.withOpacity(0.1),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.rotate(
                          angle: (widget.isConnecting || widget.isDisconnecting)
                              ? _rotationAnimation.value * 2 * 3.14159
                              : 0,
                          child: Icon(
                            _getIcon(),
                            size: widget.size * 0.35,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getStatusText(),
                          style: TextStyle(
                            fontSize: widget.size * 0.12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
