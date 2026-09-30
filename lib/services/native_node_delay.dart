import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../models/vpn_config.dart';

/// Server RTT, not a URL test or proof that proxy authentication succeeds.
/// The native probe binds its sockets to the physical default interface.
class NativeNodeDelay {
  static Future<int> measure(
    VPNConfig node, {
    required int timeoutMs,
    String? libraryPath,
  }) async {
    final executableLibrary = path.join(
      path.dirname(Platform.resolvedExecutable),
      'singbox.dll',
    );
    final dll =
        libraryPath ??
        (File(executableLibrary).existsSync()
            ? executableLibrary
            : path.absolute('windows', 'singbox.dll'));
    final outbound = node.toSingBoxOutbound(tag: 'latency');
    // Only transport metadata is needed; never send proxy credentials.
    final request = jsonEncode({
      'type': node.type.toLowerCase(),
      'server': node.server,
      'server_port': node.port,
      if (outbound['tls'] != null) 'tls': outbound['tls'],
      if (node.settings['obfs'] != null) 'obfs': node.settings['obfs'],
    });
    // Blocking FFI must not stall the UI or serialize batch measurements.
    return Isolate.run(() => _measure(dll, request, timeoutMs));
  }

  static int _measure(String libraryPath, String request, int timeoutMs) {
    final library = DynamicLibrary.open(libraryPath);
    final probe = library
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)
        >('ProbeNodeDelay');
    final input = request.toNativeUtf8();
    try {
      return probe(input, timeoutMs);
    } finally {
      calloc.free(input);
    }
  }
}
