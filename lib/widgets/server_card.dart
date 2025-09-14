import 'package:flutter/material.dart';
import '../models/vpn_config.dart';
import '../theme/app_theme.dart';

class ServerCard extends StatefulWidget {
  final VPNConfig config;
  final bool isConnected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ServerCard({
    super.key,
    required this.config,
    required this.isConnected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<ServerCard> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getProtocolColor(String type) {
    switch (type.toLowerCase()) {
      case 'shadowsocks':
        return AppTheme.primaryNeon;
      case 'vmess':
        return AppTheme.accentNeon;
      case 'trojan':
        return AppTheme.warningOrange;
      case 'hysteria2':
        return AppTheme.successGreen;
      default:
        return AppTheme.textSecondary;
    }
  }

  IconData _getProtocolIcon(String type) {
    switch (type.toLowerCase()) {
      case 'shadowsocks':
        return Icons.lock_outline;
      case 'vmess':
        return Icons.vpn_lock;
      case 'trojan':
        return Icons.security;
      case 'hysteria2':
        return Icons.speed;
      default:
        return Icons.lan;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: widget.isConnected
                  ? AppTheme.primaryNeon.withOpacity(0.1)
                  : AppTheme.bgCard.withOpacity(0.5 + 0.3 * _animation.value),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isConnected
                    ? AppTheme.primaryNeon.withOpacity(0.5)
                    : AppTheme.borderColor.withOpacity(0.2 + 0.3 * _animation.value),
                width: widget.isConnected ? 2 : 1,
              ),
              boxShadow: widget.isConnected
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryNeon.withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // 连接状态指示器
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.isConnected
                              ? AppTheme.successGreen.withOpacity(0.2)
                              : AppTheme.bgSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _getProtocolIcon(widget.config.type),
                          color: widget.isConnected
                              ? AppTheme.successGreen
                              : _getProtocolColor(widget.config.type),
                          size: 20,
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // 服务器信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.config.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: widget.isConnected
                                          ? AppTheme.primaryNeon
                                          : AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.isConnected)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.successGreen.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '已连接',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.successGreen,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                // 协议类型标签
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getProtocolColor(widget.config.type).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    widget.config.type.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _getProtocolColor(widget.config.type),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 服务器地址
                                Expanded(
                                  child: Text(
                                    '${widget.config.server}:${widget.config.port}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textHint,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // 操作按钮（悬停时显示）
                      AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: AppTheme.textHint,
                              onPressed: widget.onEdit,
                              tooltip: '编辑',
                              splashRadius: 20,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: AppTheme.errorRed,
                              onPressed: widget.onDelete,
                              tooltip: '删除',
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      ),
                      
                      // 延迟指示器（示例）
                      if (!_isHovered && !widget.isConnected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.signal_cellular_alt,
                                size: 14,
                                color: AppTheme.successGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '23ms',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.successGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}