/// 订阅信息模型
/// 包含流量使用情况和到期时间等信息
class SubscriptionInfo {
  /// 上传流量（字节）
  final int upload;

  /// 下载流量（字节）
  final int download;

  /// 总流量限制（字节）
  final int total;

  /// 到期时间（Unix时间戳，秒）
  final int? expire;

  SubscriptionInfo({
    required this.upload,
    required this.download,
    required this.total,
    this.expire,
  });

  /// 已使用流量（字节）
  int get used => upload + download;

  /// 剩余流量（字节）
  int get remaining => total > used ? total - used : 0;

  /// 流量使用百分比（0-100）
  double get usagePercentage {
    if (total <= 0) return 0;
    return (used / total * 100).clamp(0, 100);
  }

  /// 是否已过期
  bool get isExpired {
    if (expire == null) return false;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 > expire!;
  }

  /// 剩余天数
  int? get remainingDays {
    if (expire == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = expire! - now;
    return diff > 0 ? (diff / 86400).ceil() : 0;
  }

  /// 格式化流量显示
  String formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  /// 格式化已用流量
  String get formattedUsed => formatBytes(used);

  /// 格式化总流量
  String get formattedTotal => formatBytes(total);

  /// 格式化剩余流量
  String get formattedRemaining => formatBytes(remaining);

  /// 格式化到期时间
  String? get formattedExpireDate {
    if (expire == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(expire! * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 流量状态文本
  String get statusText {
    if (isExpired) return '已过期';
    if (usagePercentage >= 95) return '流量即将用完';
    if (usagePercentage >= 80) return '流量使用较多';
    if (remainingDays != null && remainingDays! <= 7) return '即将到期';
    return '正常';
  }

  /// 状态颜色（用于UI显示）
  String get statusColor {
    if (isExpired || usagePercentage >= 95) return '#FF4444';
    if (usagePercentage >= 80 || (remainingDays != null && remainingDays! <= 7)) return '#FF8800';
    return '#00AA00';
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'upload': upload,
      'download': download,
      'total': total,
      'expire': expire,
    };
  }

  /// 从JSON创建
  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      upload: json['upload'] ?? 0,
      download: json['download'] ?? 0,
      total: json['total'] ?? 0,
      expire: json['expire'],
    );
  }

  @override
  String toString() {
    return 'SubscriptionInfo(upload: $upload, download: $download, total: $total, expire: $expire)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubscriptionInfo &&
        other.upload == upload &&
        other.download == download &&
        other.total == total &&
        other.expire == expire;
  }

  @override
  int get hashCode {
    return upload.hashCode ^ download.hashCode ^ total.hashCode ^ expire.hashCode;
  }
}