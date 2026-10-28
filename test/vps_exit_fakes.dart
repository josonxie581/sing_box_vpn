import 'dart:convert';

import 'package:gsou/models/vps_exit_config.dart';
import 'package:gsou/services/vps_exit_service.dart';

const exitProfile = VpsExitProfile(
  host: '192.0.2.1',
  identityFile: r'C:\keys\id_rsa.pem',
  knownHostsFile: r'C:\keys\known_hosts',
);
String repeat(String text, int count) => List.filled(count, text).join();

Map<String, dynamic> exitStatus({
  VpsExitPolicy policy = const VpsExitPolicy(),
  String? jobState,
  bool rollback = false,
  bool external = false,
  String? revision,
}) => {
  'revision': revision ?? repeat('a', 64),
  'policy': policy.toJson(),
  'external_rules': external,
  'can_rollback': rollback,
  'job': jobState == null
      ? null
      : {
          'id': repeat('b', 32),
          'state': jobState,
          'message': jobState == 'failed'
              ? '应用失败，已恢复旧规则'
              : jobState == 'running'
              ? '正在验证出口'
              : '规则已生效',
        },
  'history': [],
  'exits': {
    'direct': {'label': '日本 DMIT', 'ip': '192.0.2.1'},
    'au': {'label': '澳洲住宅 IP', 'ip': '198.51.100.1'},
  },
};

class FakeVpsTransport implements VpsExitTransport {
  final calls = <Map<String, dynamic>>[];
  VpsExitPolicy policy = const VpsExitPolicy();
  bool applyThrows = false,
      validateThrows = false,
      failJob = false,
      canRollback = true,
      external = false;
  bool submitted = false;
  int polls = 0, transientFailures = 0;
  Future<void>? statusGate;
  @override
  Future<Map<String, dynamic>> call(
    VpsExitProfile profile,
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    calls.add({
      'action': action,
      'profile': profile.toJson(),
      'data': jsonDecode(jsonEncode(data)),
    });
    if (action == 'status') {
      if (statusGate != null) await statusGate;
      if (submitted) {
        if (transientFailures > 0) {
          transientFailures--;
          throw const FormatException('temporary disconnect');
        }
        polls++;
      }
      return exitStatus(
        policy: policy,
        rollback: canRollback,
        external: external,
        jobState: submitted
            ? (polls == 1
                  ? 'running'
                  : failJob
                  ? 'failed'
                  : 'succeeded')
            : null,
      );
    }
    if (action == 'validate') {
      if (validateThrows) throw const FormatException('配置已更新，请刷新');
      return {
        'valid': true,
        'unchanged': data['policy'].toString() == policy.toJson().toString(),
      };
    }
    if (action == 'apply' || action == 'rollback') {
      submitted = true;
      polls = 0;
      policy = action == 'rollback'
          ? const VpsExitPolicy()
          : VpsExitPolicy.fromJson(
              Map<String, dynamic>.from(data['policy'] as Map),
            );
      if (applyThrows) throw const FormatException('SSH 回执丢失，请刷新状态核对');
      return {
        'accepted': true,
        'job': {'id': repeat('b', 32), 'state': 'queued'},
      };
    }
    throw StateError(action);
  }

  @override
  Future<Map<String, dynamic>> deploy(VpsExitProfile profile) async {
    calls.add({'action': 'deploy'});
    return {'installed': true, 'policy_preserved': true};
  }
}

class RecordingVpsRunner implements VpsSshRunner {
  final calls = <Map<String, dynamic>>[];
  VpsSshResult result = VpsSshResult(
    0,
    jsonEncode({'ok': true, 'result': exitStatus()}),
    '',
  );
  @override
  Future<VpsSshResult> run(
    String executable,
    List<String> arguments,
    String input, {
    Duration timeout = const Duration(seconds: 35),
  }) async {
    calls.add({
      'executable': executable,
      'arguments': arguments,
      'input': input,
      'timeout': timeout,
    });
    return result;
  }
}
