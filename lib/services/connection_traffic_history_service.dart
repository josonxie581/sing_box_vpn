import 'package:flutter/foundation.dart';
import '../services/connection_stats_service.dart';

/// 连接流量历史服务（单例）
/// - 监听每次连接列表更新
/// - 跟踪活跃连接（按 id）
/// - 当连接消失时，持久化其最终累计上传/下载到本地 json
class ConnectionTrafficHistoryService extends ChangeNotifier {
  ConnectionTrafficHistoryService._internal();
  static final ConnectionTrafficHistoryService instance =
      ConnectionTrafficHistoryService._internal();

  bool _loaded = true; // 仅内存，无需加载

  // 历史（已结束）
  final List<ConnectionTrafficRecord> _history = [];

  // 活跃连接快照（用于检测结束）
  final Map<String, _LiveRecord> _active = {};

  bool get isLoaded => _loaded;
  List<ConnectionTrafficRecord> get history => List.unmodifiable(_history);

  /// 合并视图：已结束 + 进行中（进行中用当前累计展示）
  List<ConnectionTrafficRecord> get allRecords {
    final list = <ConnectionTrafficRecord>[];
    list.addAll(_history);
    for (final e in _active.values) {
      list.add(
        ConnectionTrafficRecord(
          id: e.id,
          host: e.host,
          domain: e.domain,
          process: e.process,
          protocol: e.protocol,
          rule: e.rule,
          target: e.target,
          startTime: e.startTime,
          endTime: null,
          uploadBytes: e.lastUpload,
          downloadBytes: e.lastDownload,
          active: true,
        ),
      );
    }
    // 默认按总字节降序
    list.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return list;
  }

  Future<void> load() async {
    // 内存模式，无需加载
    _loaded = true;
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
  }

  /// 开启新会话时重置（清空历史与活跃缓存）
  Future<void> reset() async {
    _history.clear();
    _active.clear();
    notifyListeners();
  }

  // 内存模式，无需持久化

  /// 供 Provider 在每次刷新连接信息时调用
  void onConnectionStats(List<ConnectionInfo> connections) {
    final nowIds = <String>{};

    for (final c in connections) {
      // 仅当累计字节有意义时追踪（避免 netstat 的 0 记录干扰）
      final up = c.uploadBytes;
      final down = c.downloadBytes;
      final id = c.id.isEmpty
          ? '${c.host}-${c.startTime.millisecondsSinceEpoch}'
          : c.id;
      nowIds.add(id);

      final lr = _active[id];
      if (lr == null) {
        _active[id] = _LiveRecord(
          id: id,
          host: c.host,
          domain: c.domain,
          process: c.process,
          protocol: c.protocol,
          rule: c.rule,
          target: c.target,
          startTime: c.startTime,
          lastUpload: up,
          lastDownload: down,
          lastSeen: DateTime.now(),
        );
      } else {
        lr.lastUpload = up;
        lr.lastDownload = down;
        lr.lastSeen = DateTime.now();
      }
    }

    // 检测结束的连接（活跃表里有，但这次未出现）
    final ended = _active.keys.where((k) => !nowIds.contains(k)).toList();
    if (ended.isNotEmpty) {
      for (final id in ended) {
        final lr = _active.remove(id);
        if (lr == null) continue;
        // 仅在有实际流量时记录历史
        final total = lr.lastUpload + lr.lastDownload;
        if (total <= 0) continue;
        _history.add(
          ConnectionTrafficRecord(
            id: lr.id,
            host: lr.host,
            domain: lr.domain,
            process: lr.process,
            protocol: lr.protocol,
            rule: lr.rule,
            target: lr.target,
            startTime: lr.startTime,
            endTime: lr.lastSeen,
            uploadBytes: lr.lastUpload,
            downloadBytes: lr.lastDownload,
            active: false,
          ),
        );
      }
      // 内存模式，无需落盘
      notifyListeners();
    }
  }
}

class _LiveRecord {
  final String id;
  final String host;
  final String? domain;
  final String process;
  final String protocol;
  final String rule;
  final String target;
  final DateTime startTime;
  int lastUpload;
  int lastDownload;
  DateTime lastSeen;

  _LiveRecord({
    required this.id,
    required this.host,
    required this.domain,
    required this.process,
    required this.protocol,
    required this.rule,
    required this.target,
    required this.startTime,
    required this.lastUpload,
    required this.lastDownload,
    required this.lastSeen,
  });
}

class ConnectionTrafficRecord {
  final String id;
  final String host;
  final String? domain;
  final String process;
  final String protocol;
  final String rule;
  final String target;
  final DateTime startTime;
  final DateTime? endTime; // null 表示还在进行中
  final int uploadBytes;
  final int downloadBytes;
  final bool active;

  ConnectionTrafficRecord({
    required this.id,
    required this.host,
    required this.domain,
    required this.process,
    required this.protocol,
    required this.rule,
    required this.target,
    required this.startTime,
    required this.endTime,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.active,
  });

  int get totalBytes => uploadBytes + downloadBytes;
  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  Map<String, dynamic> toJson() => {
    'id': id,
    'host': host,
    'domain': domain,
    'process': process,
    'protocol': protocol,
    'rule': rule,
    'target': target,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'uploadBytes': uploadBytes,
    'downloadBytes': downloadBytes,
    'active': active,
  };

  factory ConnectionTrafficRecord.fromJson(Map<String, dynamic> json) {
    return ConnectionTrafficRecord(
      id: json['id'] ?? '',
      host: json['host'] ?? '',
      domain: json['domain'],
      process: json['process'] ?? '',
      protocol: json['protocol'] ?? '',
      rule: json['rule'] ?? '',
      target: json['target'] ?? '',
      startTime:
          DateTime.tryParse(json['startTime'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endTime: json['endTime'] != null
          ? DateTime.tryParse(json['endTime'])
          : null,
      uploadBytes: (json['uploadBytes'] as num?)?.toInt() ?? 0,
      downloadBytes: (json['downloadBytes'] as num?)?.toInt() ?? 0,
      active: json['active'] == true ? true : false,
    );
  }
}
