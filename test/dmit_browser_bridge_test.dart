import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/services/dmit_bridge_protocol.dart';

const _bridgePath = 'build/windows/x64/runner/Release/GsouDmitBridge.exe';

void main() {
  test('compiled bridge writes only the normalized billing snapshot', () async {
    if (!Platform.isWindows || !File(_bridgePath).existsSync()) return;
    final temporary = await Directory.systemTemp.createTemp(
      'gsou-bridge-test-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final process = await Process.start(
      _bridgePath,
      [dmitExtensionOrigin],
      environment: {...Platform.environment, 'LOCALAPPDATA': temporary.path},
    );
    final reader = _FrameReader(process.stdout);
    final ready = await reader.readJson();
    expect(ready, {'type': 'ready', 'protocol': dmitBridgeProtocolVersion});

    await _writeJson(process.stdin, {
      'type': 'snapshot',
      'requestId': 'test-request',
      'items': [
        {
          'product': {
            'id': 159947,
            'domain': 'DMIT-JP-Gsou',
            'primaryip': '154.31.116.184',
          },
          'detail': {
            'serviceid': 159947,
            'hostname': 'dmit-jp-gsou',
            'bwusage': 324262,
            'bwlimit': 512000,
            'bw_method': 'both',
            'bw_disable_reset': 0,
            'nextduedate': '2027-01-01',
            'suspendonexceeded': 1,
            'password': 'must-not-be-copied',
          },
        },
      ],
    });
    final ack = await reader.readJson();
    expect(ack['type'], 'ack');
    expect(ack['serverCount'], 1);
    await process.stdin.close();
    expect(await process.exitCode, 0);

    final snapshot = File('${temporary.path}/Gsou/dmit/snapshot.json');
    expect(await snapshot.exists(), isTrue);
    final text = await snapshot.readAsString();
    expect(text, isNot(contains('must-not-be-copied')));
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final server = (decoded['servers'] as List).single as Map<String, dynamic>;
    expect(server['serviceId'], '159947');
    expect(server['usedMb'], 324262.0);
    expect(server['limitMb'], 512000.0);
  });

  test('compiled bridge rejects an untrusted extension origin', () async {
    if (!Platform.isWindows || !File(_bridgePath).existsSync()) return;
    final temporary = await Directory.systemTemp.createTemp(
      'gsou-bridge-test-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final process = await Process.run(
      _bridgePath,
      ['chrome-extension://untrusted/'],
      environment: {...Platform.environment, 'LOCALAPPDATA': temporary.path},
    );
    expect(process.exitCode, 2);
    expect(Directory('${temporary.path}/Gsou').existsSync(), isFalse);
  });
}

Future<void> _writeJson(IOSink sink, Map<String, dynamic> message) async {
  final payload = utf8.encode(jsonEncode(message));
  final header = ByteData(4)..setUint32(0, payload.length, Endian.little);
  sink.add(header.buffer.asUint8List());
  sink.add(payload);
  await sink.flush();
}

class _FrameReader {
  _FrameReader(Stream<List<int>> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];

  Future<Map<String, dynamic>> readJson() async {
    final header = await _read(4);
    final length = ByteData.sublistView(
      Uint8List.fromList(header),
    ).getUint32(0, Endian.little);
    final decoded = jsonDecode(utf8.decode(await _read(length)));
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<List<int>> _read(int count) async {
    while (_buffer.length < count) {
      if (!await _iterator.moveNext()) {
        throw StateError('Native host closed before a full frame arrived');
      }
      _buffer.addAll(_iterator.current);
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return result;
  }
}
