/// Validated configuration for the read-only DMIT SSH runtime monitor.
///
/// The private key stays outside the application bundle. The client invokes
/// Windows OpenSSH directly and never reads, copies or serializes key content.
class DmitSshMonitorConfig {
  const DmitSshMonitorConfig({
    required this.serviceId,
    required this.host,
    required this.port,
    required this.user,
    required this.identityFile,
    required this.knownHostsFile,
  });

  final String serviceId;
  final String host;
  final int port;
  final String user;
  final String identityFile;
  final String knownHostsFile;

  factory DmitSshMonitorConfig.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported SSH monitor configuration');
    }
    final serviceId = _requiredString(json['serviceId']);
    final host = _requiredString(json['host']);
    final user = _requiredString(json['user']);
    final identityFile = _requiredString(json['identityFile']);
    final knownHostsFile = _requiredString(json['knownHostsFile']);
    final port = _integer(json['port']);
    if (!RegExp(r'^\d+$').hasMatch(serviceId) ||
        !RegExp(r'^[A-Za-z0-9.-]{1,253}$').hasMatch(host) ||
        host.startsWith('-') ||
        !RegExp(r'^[a-z_][a-z0-9_-]{0,31}$').hasMatch(user) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        identityFile.length > 4096 ||
        knownHostsFile.length > 4096) {
      throw const FormatException('Invalid SSH monitor configuration');
    }
    return DmitSshMonitorConfig(
      serviceId: serviceId,
      host: host,
      port: port,
      user: user,
      identityFile: identityFile,
      knownHostsFile: knownHostsFile,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'serviceId': serviceId,
    'host': host,
    'port': port,
    'user': user,
    'identityFile': identityFile,
    'knownHostsFile': knownHostsFile,
  };
}

/// One runtime sample emitted by the server-side forced SSH command.
class DmitRuntimeInfo {
  const DmitRuntimeInfo({
    required this.serviceId,
    required this.receivedAt,
    required this.cpuPercent,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    required this.diskUsedBytes,
    required this.diskTotalBytes,
    required this.load1,
    required this.uptimeSeconds,
    required this.rxBytesPerSecond,
    required this.txBytesPerSecond,
    required this.networkInterface,
  });

  final String serviceId;
  final DateTime receivedAt;
  final double cpuPercent;
  final int memoryUsedBytes;
  final int memoryTotalBytes;
  final int diskUsedBytes;
  final int diskTotalBytes;
  final double load1;
  final int uptimeSeconds;
  final double rxBytesPerSecond;
  final double txBytesPerSecond;
  final String networkInterface;

  factory DmitRuntimeInfo.fromMonitorJson(
    Map<String, dynamic> json, {
    required String serviceId,
    required DateTime receivedAt,
  }) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported SSH monitor sample');
    }
    final cpu = _finiteDouble(json['cpuPercent']);
    final memoryTotal = _integer(json['memoryTotalBytes']);
    final memoryAvailable = _integer(json['memoryAvailableBytes']);
    final diskTotal = _integer(json['diskTotalBytes']);
    final diskAvailable = _integer(json['diskAvailableBytes']);
    final load = _finiteDouble(json['load1']);
    final uptime = _integer(json['uptimeSeconds']);
    final rx = _finiteDouble(json['rxBytesPerSecond']);
    final tx = _finiteDouble(json['txBytesPerSecond']);
    final interface = _requiredString(json['networkInterface']);
    if (cpu == null ||
        cpu < 0 ||
        cpu > 100 ||
        memoryTotal == null ||
        memoryTotal <= 0 ||
        memoryAvailable == null ||
        memoryAvailable < 0 ||
        memoryAvailable > memoryTotal ||
        diskTotal == null ||
        diskTotal <= 0 ||
        diskAvailable == null ||
        diskAvailable < 0 ||
        diskAvailable > diskTotal ||
        load == null ||
        load < 0 ||
        uptime == null ||
        uptime < 0 ||
        rx == null ||
        rx < 0 ||
        tx == null ||
        tx < 0 ||
        interface.length > 64 ||
        !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(interface)) {
      throw const FormatException('Invalid SSH monitor sample');
    }
    return DmitRuntimeInfo(
      serviceId: serviceId,
      receivedAt: receivedAt.toUtc(),
      cpuPercent: cpu,
      memoryUsedBytes: memoryTotal - memoryAvailable,
      memoryTotalBytes: memoryTotal,
      diskUsedBytes: diskTotal - diskAvailable,
      diskTotalBytes: diskTotal,
      load1: load,
      uptimeSeconds: uptime,
      rxBytesPerSecond: rx,
      txBytesPerSecond: tx,
      networkInterface: interface,
    );
  }

  double get memoryFraction => memoryUsedBytes / memoryTotalBytes;
  double get diskFraction => diskUsedBytes / diskTotalBytes;

  static String formatBytes(int value) => _formatBytes(value.toDouble());

  static String formatRate(double value) => '${_formatBytes(value)}/s';

  static String formatUptime(int seconds) {
    if (seconds < 0) return '--';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return '$days天 $hours小时';
    if (hours > 0) return '$hours小时 $minutes分钟';
    return '$minutes分钟';
  }
}

String _formatBytes(double value) {
  if (!value.isFinite || value < 0) return '--';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = value;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : (size >= 100 ? 0 : (size >= 10 ? 1 : 2));
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}

String _requiredString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected a non-empty string');
  }
  return value.trim();
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

double? _finiteDouble(Object? value) {
  if (value is! num) return null;
  final result = value.toDouble();
  return result.isFinite ? result : null;
}
