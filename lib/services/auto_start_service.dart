import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

typedef AutoStartProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Windows 登录任务 / Linux graphical-session 用户服务，以系统状态为准。
class AutoStartService {
  static const startupArgument = '--autostart';
  static const autoConnectPreferenceKey = 'auto_connect_on_startup';

  AutoStartService({
    AutoStartProcessRunner? runner,
    String? executablePath,
    bool? isSupported,
    String? operatingSystem,
  }) : _runner = runner ?? _runProcess,
       _executablePath = executablePath ?? Platform.resolvedExecutable,
       _operatingSystem = operatingSystem ?? Platform.operatingSystem,
       isSupported =
           isSupported ??
           [
             'windows',
             'linux',
           ].contains(operatingSystem ?? Platform.operatingSystem);

  final AutoStartProcessRunner _runner;
  final String _executablePath;
  final bool isSupported;
  final String _operatingSystem;

  String get description =>
      _operatingSystem == 'linux' ? '登录桌面后自动启动 Gsou' : '登录 Windows 后自动启动 Gsou';

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) => Process.run(
    executable,
    arguments,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  Future<bool> isEnabled() => _execute(null);

  Future<bool> isAutoConnectEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(autoConnectPreferenceKey) ?? false;
  }

  Future<bool> setAutoConnectEnabled(bool enabled) async {
    if (enabled) {
      // 自动开始包含开机自启；同时升级旧任务参数，读回成功后才保存偏好。
      await setEnabled(true);
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(autoConnectPreferenceKey, enabled)) {
      throw StateError('无法保存“开机后自动开始”设置，请重试');
    }
    if (await isAutoConnectEnabled() != enabled) {
      throw StateError('保存的“开机后自动开始”状态与设置不一致，请重试');
    }
    return enabled;
  }

  Future<bool> isAutoStartLaunch(List<String> arguments) async {
    if (!isSupported) return false;
    if (arguments.contains(startupArgument)) return true;
    if (_operatingSystem != 'linux') return false;
    // 兼容已经安装的旧 Linux 服务：仅该服务的主进程视为自动启动。
    // 不能只检查 INVOCATION_ID，手动启动的终端也可能继承此环境变量。
    try {
      final result = await _runner('systemctl', [
        '--user',
        'show',
        'gsou.service',
        '--property=MainPID',
        '--value',
      ]);
      return result.exitCode == 0 &&
          int.tryParse(result.stdout.toString().trim()) == pid;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    final actual = await _execute(enabled);
    if (actual != enabled) {
      throw StateError('系统返回的开机启动状态与设置不一致，请重试');
    }
    return actual;
  }

  Future<bool> _execute(bool? enabled) async {
    if (!isSupported) {
      throw UnsupportedError('开机自动启动仅支持 Windows 和 Linux');
    }
    if (_operatingSystem == 'linux') return _executeLinux(enabled);
    // PowerShell 单引号字符串只需转义单引号；不经过 cmd 或字符串拼接的 shell。
    final exe = _executablePath.replaceAll("'", "''");
    final directory = p.windows.dirname(_executablePath).replaceAll("'", "''");
    final operation = enabled == null
        ? 'query'
        : (enabled ? 'enable' : 'disable');
    final script =
        '''
\$ErrorActionPreference = 'Stop'
\$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(\$false)
try {
  \$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  \$userId = \$identity.User.Value
  \$userName = \$identity.Name
  function Test-CurrentUser([string]\$candidate) {
    if ([string]::IsNullOrWhiteSpace(\$candidate)) { return \$false }
    if (\$candidate -eq \$userId -or \$candidate -ieq \$userName) { return \$true }
    try {
      return [System.Security.Principal.NTAccount]::new(\$candidate).Translate([System.Security.Principal.SecurityIdentifier]).Value -eq \$userId
    } catch {
      return \$false
    }
  }
  \$taskName = 'Gsou_AutoStart_' + \$userId
  \$exe = '$exe'
  \$directory = '$directory'
  \$operation = '$operation'
  # 枚举失败必须报错，不能把权限或服务故障误报为关闭。
  \$task = Get-ScheduledTask -TaskPath '\\' | Where-Object { \$_.TaskName -eq \$taskName }
  if (\$operation -eq 'enable') {
    if (-not (Test-Path -LiteralPath \$exe -PathType Leaf)) {
      throw 'Application executable not found.'
    }
    \$action = New-ScheduledTaskAction -Execute ('"' + \$exe + '"') -Argument '$startupArgument' -WorkingDirectory \$directory
    \$trigger = New-ScheduledTaskTrigger -AtLogOn -User \$userId
    \$principal = New-ScheduledTaskPrincipal -UserId \$userId -LogonType Interactive -RunLevel Highest
    \$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskPath '\\' -TaskName \$taskName -Action \$action -Trigger \$trigger -Principal \$principal -Settings \$settings -Description 'Start Gsou when this user signs in.' -Force | Out-Null
  } elseif (\$operation -eq 'disable' -and \$null -ne \$task) {
    Unregister-ScheduledTask -TaskPath '\\' -TaskName \$taskName -Confirm:\$false
  }
  \$task = Get-ScheduledTask -TaskPath '\\' | Where-Object { \$_.TaskName -eq \$taskName }
  \$active = \$null -ne \$task -and \$task.Settings.Enabled -and
    @(\$task.Actions).Count -eq 1 -and
    \$task.Actions[0].Execute.Trim('"') -ieq \$exe -and
    @(\$task.Triggers | Where-Object { \$_.Enabled -and \$_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and (Test-CurrentUser \$_.UserId) }).Count -gt 0
  if (\$operation -eq 'enable' -and \$active) {
    \$active = \$task.Actions[0].Arguments -eq '$startupArgument'
  }
  @{ enabled = [bool]\$active } | ConvertTo-Json -Compress
} catch {
  [Console]::Error.WriteLine(\$_.Exception.Message)
  exit 1
}
''';
    // -EncodedCommand 使用 UTF-16LE，保留中文、空格及特殊字符路径。
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes.addAll([unit & 0xff, unit >> 8]);
    }
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final result = await _runner(
      p.windows.join(
        systemRoot,
        r'System32\WindowsPowerShell\v1.0\powershell.exe',
      ),
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        base64Encode(bytes),
      ],
    );
    if (result.exitCode != 0) {
      throw AutoStartException(
        '无法${enabled == null ? '读取' : '修改'}开机启动设置，请以管理员身份运行 Gsou 后重试。',
        result.stderr.toString().trim(),
      );
    }
    final data = jsonDecode(result.stdout.toString().trim());
    if (data is! Map || data['enabled'] is! bool) {
      throw const FormatException('无法识别系统返回的开机启动状态');
    }
    return data['enabled'] as bool;
  }

  Future<bool> _executeLinux(bool? enabled) async {
    if (enabled != null) {
      for (final args in [
        ['--user', 'daemon-reload'],
        ['--user', enabled ? 'enable' : 'disable', 'gsou.service'],
      ]) {
        final result = await _runner('systemctl', args);
        if (result.exitCode != 0) {
          throw AutoStartException(
            '无法修改开机启动，请先运行 Linux 安装脚本。',
            result.stderr.toString(),
          );
        }
      }
    }
    final result = await _runner('systemctl', [
      '--user',
      'is-enabled',
      'gsou.service',
    ]);
    final state = result.stdout.toString().trim();
    if (result.exitCode == 0 && state == 'enabled') return true;
    if (result.exitCode == 1 && state == 'disabled') return false;
    throw AutoStartException(
      '无法读取开机启动，请确认已安装 Gsou 且用户服务正常运行。',
      '${result.stdout}\n${result.stderr}'.trim(),
    );
  }
}

class AutoStartException implements Exception {
  const AutoStartException(this.message, this.details);

  final String message;
  final String details;

  @override
  String toString() => message;
}
