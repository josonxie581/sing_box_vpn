import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/dmit_billing_info.dart';

/// Reads the last provider-authoritative DMIT billing snapshot written by the
/// background browser helper. It never opens a page or handles credentials.
class DmitBillingService extends ChangeNotifier {
  DmitBillingService._();
  static final DmitBillingService instance = DmitBillingService._();

  static const int _maxSnapshotBytes = 2 * 1024 * 1024;

  bool initialized = false;
  String? error;
  DateTime? updatedAt;
  List<DmitBillingInfo> servers = const [];

  Directory? _directory;
  StreamSubscription<FileSystemEvent>? _watcher;
  Future<void>? _initializing;
  Timer? _reloadTimer;

  DmitBillingInfo? infoFor(String? serviceId) {
    if (serviceId == null) return null;
    for (final server in servers) {
      if (server.serviceId == serviceId) return server;
    }
    return null;
  }

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (!Platform.isWindows) {
      initialized = true;
      error = 'DMIT 后台计费同步目前仅支持 Windows。';
      notifyListeners();
      return;
    }
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) {
      initialized = true;
      error = '无法确定 DMIT 本地数据目录。';
      notifyListeners();
      return;
    }
    final directory = Directory('$local/Gsou/dmit');
    await directory.create(recursive: true);
    _directory = directory;
    await _load();
    _watcher = directory.watch().listen((event) {
      final path = event.path.toLowerCase();
      if (!path.endsWith('snapshot.json')) return;
      _reloadTimer?.cancel();
      _reloadTimer = Timer(const Duration(milliseconds: 150), () {
        unawaited(_load());
      });
    });
    initialized = true;
    notifyListeners();
  }

  Future<void> _load() async {
    final directory = _directory;
    if (directory == null) return;
    final file = File('${directory.path}/snapshot.json');
    if (!await file.exists()) {
      error = '等待 DMIT 后台计费同步。';
      notifyListeners();
      return;
    }
    try {
      if (await file.length() > _maxSnapshotBytes) {
        throw const FormatException('Oversized DMIT snapshot');
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('Invalid snapshot');
      final json = Map<String, dynamic>.from(decoded);
      final timestamp = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
      final rawServers = json['servers'];
      if (timestamp == null || rawServers is! List || rawServers.length > 128) {
        throw const FormatException('Invalid snapshot');
      }
      final parsed = rawServers
          .map((value) {
            if (value is! Map) throw const FormatException('Invalid server');
            return DmitBillingInfo.fromJson(Map<String, dynamic>.from(value));
          })
          .toList(growable: false);
      if (parsed.map((server) => server.serviceId).toSet().length !=
          parsed.length) {
        throw const FormatException('Duplicate service id');
      }
      servers = parsed;
      updatedAt = timestamp.toUtc();
      error = null;
    } on Object {
      error = 'DMIT 计费快照无效，已保留上次有效数据。';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    unawaited(_watcher?.cancel());
    super.dispose();
  }
}
