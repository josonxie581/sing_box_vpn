import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/dmit_ssh_monitor.dart';

/// Maintains one read-only OpenSSH stream for live operating-system metrics.
///
/// Authentication remains in Windows OpenSSH. This service never reads key
/// bytes and accepts only the strict JSON schema in [DmitRuntimeInfo].
class DmitSshMonitorService extends ChangeNotifier {
  DmitSshMonitorService._();
  static final DmitSshMonitorService instance = DmitSshMonitorService._();

  static const Duration _sampleTimeout = Duration(seconds: 20);
  static const Duration _reconnectDelay = Duration(seconds: 10);
  static const int _maxLineLength = 16 * 1024;

  bool initialized = false;
  bool configured = false;
  String? error;
  DmitRuntimeInfo? info;

  DmitSshMonitorConfig? _config;
  Future<void>? _initializing;
  Process? _process;
  Timer? _reconnectTimer;
  Timer? _staleTimer;
  int _generation = 0;
  bool _disposed = false;

  bool get connected {
    final sample = info;
    if (_process == null || sample == null) return false;
    final age = DateTime.now().toUtc().difference(sample.receivedAt);
    return age >= const Duration(seconds: -5) && age < _sampleTimeout;
  }

  DateTime? get lastUpdated => info?.receivedAt;

  String? get monitoredHost => _config?.host;

  String? get serviceId => _config?.serviceId;

  DmitRuntimeInfo? get currentInfo => connected ? info : null;

  bool monitorsHost(String? host) {
    final configuredHost = _config?.host;
    if (configuredHost == null || host == null) return false;
    return _normalizeHost(host) == _normalizeHost(configuredHost);
  }

  DmitRuntimeInfo? infoFor(String serviceId) {
    final sample = info;
    return connected && sample?.serviceId == serviceId ? sample : null;
  }

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (!Platform.isWindows) {
      initialized = true;
      error = 'SSH 实时监控目前仅支持 Windows。';
      notifyListeners();
      return;
    }
    try {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local == null || local.isEmpty) {
        throw const FormatException('Missing LOCALAPPDATA');
      }
      final file = File('$local/Gsou/dmit/ssh-monitor.json');
      if (!await file.exists()) {
        initialized = true;
        configured = false;
        error = 'SSH 实时监控尚未配置。';
        notifyListeners();
        return;
      }
      if (await file.length() > 64 * 1024) {
        throw const FormatException('Oversized SSH configuration');
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) {
        throw const FormatException('Invalid SSH configuration');
      }
      final config = DmitSshMonitorConfig.fromJson(
        Map<String, dynamic>.from(value),
      );
      if (!await File(config.identityFile).exists() ||
          !await File(config.knownHostsFile).exists()) {
        throw const FormatException('Missing SSH files');
      }
      _config = config;
      configured = true;
      initialized = true;
      error = '正在连接 SSH 实时监控。';
      _staleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_disposed) notifyListeners();
      });
      notifyListeners();
      await _connect();
    } on Object {
      initialized = true;
      configured = false;
      error = 'SSH 实时监控配置无效，请重新配置。';
      notifyListeners();
    }
  }

  Future<void> reconnect() async {
    await initialize();
    if (!configured || _disposed) return;
    _reconnectTimer?.cancel();
    _generation++;
    _process?.kill();
    _process = null;
    info = null;
    error = '正在重新连接 SSH 实时监控。';
    notifyListeners();
    await _connect();
  }

  Future<void> _connect() async {
    final config = _config;
    if (_disposed || config == null || _process != null) return;
    final generation = ++_generation;
    try {
      final process = await Process.start('ssh.exe', [
        '-T',
        '-o',
        'BatchMode=yes',
        '-o',
        'IdentitiesOnly=yes',
        '-o',
        'StrictHostKeyChecking=yes',
        '-o',
        'UserKnownHostsFile=${config.knownHostsFile}',
        '-o',
        'ConnectTimeout=8',
        '-o',
        'ServerAliveInterval=10',
        '-o',
        'ServerAliveCountMax=2',
        '-i',
        config.identityFile,
        '-p',
        config.port.toString(),
        '${config.user}@${config.host}',
      ], mode: ProcessStartMode.normal);
      if (_disposed || generation != _generation) {
        process.kill();
        return;
      }
      _process = process;
      unawaited(_consume(process, config, generation));
    } on Object {
      if (generation != _generation || _disposed) return;
      error = '无法启动 Windows OpenSSH 实时监控。';
      notifyListeners();
      _scheduleReconnect();
    }
  }

  Future<void> _consume(
    Process process,
    DmitSshMonitorConfig config,
    int generation,
  ) async {
    final stderrDone = process.stderr.drain<void>();
    try {
      await for (final line
          in process.stdout
              .transform(const Utf8Decoder(allowMalformed: false))
              .transform(const LineSplitter())) {
        if (_disposed || generation != _generation) break;
        if (line.isEmpty || line.length > _maxLineLength) {
          throw const FormatException('Invalid SSH monitor line');
        }
        final value = jsonDecode(line);
        if (value is! Map) throw const FormatException('Invalid SSH sample');
        info = DmitRuntimeInfo.fromMonitorJson(
          Map<String, dynamic>.from(value),
          serviceId: config.serviceId,
          receivedAt: DateTime.now().toUtc(),
        );
        error = null;
        notifyListeners();
      }
    } on Object {
      if (!_disposed && generation == _generation) {
        error = 'SSH 实时监控返回了无效数据，正在重新连接。';
      }
      process.kill();
    }
    await process.exitCode;
    await stderrDone;
    if (_disposed || generation != _generation) return;
    _process = null;
    info = null;
    error ??= 'SSH 实时监控连接已断开，正在重试。';
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !configured) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_disposed) unawaited(_connect());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _reconnectTimer?.cancel();
    _staleTimer?.cancel();
    _process?.kill();
    _process = null;
    super.dispose();
  }
}

String _normalizeHost(String value) {
  var result = value.trim().toLowerCase();
  while (result.endsWith('.')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
