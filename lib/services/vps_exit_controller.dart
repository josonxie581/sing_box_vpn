import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/vps_exit_config.dart';
import 'vps_exit_service.dart';

/// One remote management session; deliberately independent of VPNProviderV2.
class VpsExitController extends ChangeNotifier {
  VpsExitController(
    this.transport, {
    this.pollInterval = const Duration(seconds: 2),
    this.maxPolls = 300,
    this.pollTimeout = const Duration(minutes: 10),
  });
  final VpsExitTransport transport;
  final Duration pollInterval;
  final int maxPolls;
  final Duration pollTimeout;
  VpsExitProfile? profile;
  VpsExitStatus? status;
  bool busy = false;
  bool applying = false;
  String? message;
  String? error;
  bool _disposed = false;
  int _generation = 0;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _active(int generation) => !_disposed && generation == _generation;
  String _error(Object e) =>
      e is FormatException ? e.message.toString() : '操作未完成，请刷新服务器状态核对结果';

  Future<void> connect(VpsExitProfile connection) async {
    if (busy) return;
    connection.validate();
    profile = connection;
    status = null;
    _generation++;
    await refresh();
  }

  Future<void> refresh() async {
    if (busy || profile == null) return;
    final generation = _generation;
    busy = true;
    error = null;
    message = '正在读取 VPS 生效规则…';
    _notify();
    try {
      status = VpsExitStatus.fromJson(await transport.call(profile!, 'status'));
      if (!_active(generation)) return;
      if (status!.job?.pending == true) {
        applying = true;
        await _poll(status!.job!.id, generation);
      } else {
        message = '已读取服务器当前生效配置';
      }
    } on Object catch (e) {
      if (_active(generation)) error = _error(e);
    } finally {
      if (_active(generation)) {
        busy = false;
        applying = false;
        _notify();
      }
    }
  }

  Future<void> validate(VpsExitPolicy policy) async {
    if (busy || status == null || profile == null || status!.externalRules) {
      return;
    }
    final normalized = policy.normalized();
    busy = true;
    error = null;
    message = '正在检查规则…';
    _notify();
    try {
      final result = await transport.call(profile!, 'validate', {
        'policy': normalized.toJson(),
        'expected_revision': status!.revision,
      });
      if (result['valid'] != true) throw const FormatException('规则校验未通过');
      message = result['unchanged'] == true
          ? '检查通过，与当前生效规则一致'
          : '检查通过，点击“保存并应用”后生效';
    } on Object catch (e) {
      error = _error(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> apply(VpsExitPolicy policy, {bool rollback = false}) async {
    if (busy || status == null || profile == null || status!.externalRules) {
      return;
    }
    final normalized = rollback ? status!.policy : policy.normalized();
    final generation = _generation;
    busy = true;
    applying = true;
    error = null;
    message = '正在提交出口规则…';
    _notify();
    try {
      final result = await transport
          .call(profile!, rollback ? 'rollback' : 'apply', {
            'expected_revision': status!.revision,
            if (!rollback) 'policy': normalized.toJson(),
          });
      if (result['accepted'] != true || result['job'] is! Map) {
        throw const FormatException('未收到有效任务回执，请刷新服务器状态');
      }
      final job = VpsExitJob.fromJson(
        Map<String, dynamic>.from(result['job'] as Map),
      );
      await _poll(job.id, generation);
    } on Object catch (e) {
      if (_active(generation)) error = _error(e);
    } finally {
      if (_active(generation)) {
        busy = false;
        applying = false;
        _notify();
      }
    }
  }

  Future<void> _poll(String jobId, int generation) async {
    final elapsed = Stopwatch()..start();
    for (
      var attempt = 0;
      attempt < maxPolls &&
          _active(generation) &&
          elapsed.elapsed < pollTimeout;
      attempt++
    ) {
      if (attempt > 0) await Future<void>.delayed(pollInterval);
      if (!_active(generation)) return;
      VpsExitStatus value;
      try {
        value = VpsExitStatus.fromJson(
          await transport.call(profile!, 'status'),
        );
      } on Object {
        message = '规则已提交，等待 SSH 恢复并核对结果…';
        _notify();
        continue;
      }
      if (!_active(generation)) return;
      status = value;
      final job = value.job;
      if (job == null) continue;
      message = job.message.isEmpty ? '正在验证出口…' : job.message;
      _notify();
      if (job.pending) continue;
      if (job.id != jobId) {
        message = '服务器已有后续操作，请核对当前生效规则';
        return;
      }
      if (job.state == 'failed') error = job.message;
      return;
    }
    if (_active(generation)) error = '暂时无法确认应用结果，请刷新服务器状态核对，不要重复提交';
  }

  Future<void> deploy() async {
    if (busy || profile == null) return;
    busy = true;
    error = null;
    message = '正在部署出口控制服务…';
    _notify();
    try {
      final result = await transport.deploy(profile!);
      if (result['installed'] != true || result['policy_preserved'] != true) {
        throw const FormatException('部署结果未通过校验');
      }
      status = VpsExitStatus.fromJson(await transport.call(profile!, 'status'));
      message = '控制服务已部署，现有代理规则已保留';
    } on Object catch (e) {
      error = _error(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
