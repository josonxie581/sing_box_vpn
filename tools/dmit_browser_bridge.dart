import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gsou/models/dmit_billing_info.dart';
import 'package:gsou/services/dmit_bridge_protocol.dart';

const int _maxMessageBytes = 1024 * 1024;

Future<void> main(List<String> args) async {
  if (!Platform.isWindows ||
      args.isEmpty ||
      args.first != dmitExtensionOrigin) {
    exitCode = 2;
    return;
  }
  final local = Platform.environment['LOCALAPPDATA'];
  if (local == null || local.isEmpty) {
    exitCode = 3;
    return;
  }
  final directory = Directory('$local/Gsou/dmit');
  await directory.create(recursive: true);
  final bridge = _DmitBridge(directory);
  await bridge.send({'type': 'ready', 'protocol': dmitBridgeProtocolVersion});
  await bridge.run();
}

class _DmitBridge {
  _DmitBridge(this.directory);

  final Directory directory;
  final List<int> _pending = <int>[];

  Future<void> run() async {
    await for (final chunk in stdin) {
      _pending.addAll(chunk);
      while (true) {
        if (_pending.length < 4) break;
        final header = Uint8List.fromList(_pending.sublist(0, 4));
        final length = ByteData.sublistView(header).getUint32(0, Endian.little);
        if (length == 0 || length > _maxMessageBytes) {
          await send({'type': 'error', 'code': 'invalidData'});
          exitCode = 4;
          return;
        }
        if (_pending.length < length + 4) break;
        final payload = _pending.sublist(4, length + 4);
        _pending.removeRange(0, length + 4);
        await _handle(payload);
      }
    }
  }

  Future<void> _handle(List<int> payload) async {
    try {
      final decoded = jsonDecode(utf8.decode(payload, allowMalformed: false));
      if (decoded is! Map) throw const FormatException('Invalid message');
      final message = Map<String, dynamic>.from(decoded);
      switch (message['type']) {
        case 'pong':
          return;
        case 'status':
          await _handleStatus(message);
          return;
        case 'snapshot':
          await _handleSnapshot(message);
          return;
        default:
          throw const FormatException('Unsupported message');
      }
    } on Object {
      await send({'type': 'error', 'code': 'invalidData'});
    }
  }

  Future<void> _handleStatus(Map<String, dynamic> message) async {
    final code = message['code'];
    if (code is! String || !dmitBridgeStatusCodes.contains(code)) {
      throw const FormatException('Invalid status');
    }
    final requestId = _requestId(message['requestId']);
    await _writeJson('status.json', {
      'code': code,
      'requestId': requestId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _handleSnapshot(Map<String, dynamic> message) async {
    final requestId = _requestId(message['requestId']);
    final items = message['items'];
    if (items is! List || items.length > 128) {
      throw const FormatException('Invalid snapshot');
    }
    final servers = <DmitBillingInfo>[];
    final ids = <String>{};
    for (final item in items) {
      if (item is! Map) throw const FormatException('Invalid server');
      final server = DmitBillingInfo.fromBridgeItem(
        Map<String, dynamic>.from(item),
      );
      if (!ids.add(server.serviceId)) {
        throw const FormatException('Duplicate service id');
      }
      servers.add(server);
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await _writeJson('snapshot.json', {
      'updatedAt': updatedAt,
      'servers': servers.map((server) => server.toJson()).toList(),
    });
    await _writeJson('status.json', {
      'code': 'ok',
      'requestId': requestId,
      'updatedAt': updatedAt,
    });
    await send({
      'type': 'ack',
      'forType': 'snapshot',
      'requestId': requestId,
      'updatedAt': updatedAt,
      'serverCount': servers.length,
    });
  }

  Future<void> send(Map<String, dynamic> message) async {
    final payload = utf8.encode(jsonEncode(message));
    if (payload.length > _maxMessageBytes) {
      throw const FormatException('Oversized response');
    }
    final header = ByteData(4)..setUint32(0, payload.length, Endian.little);
    stdout.add(header.buffer.asUint8List());
    stdout.add(payload);
    await stdout.flush();
  }

  Future<void> _writeJson(String name, Map<String, dynamic> value) async {
    final destination = File('${directory.path}/$name');
    final temporary = File('${destination.path}.$pid.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }
}

String _requestId(Object? value) {
  if (value is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw const FormatException('Invalid request id');
  }
  return value;
}
