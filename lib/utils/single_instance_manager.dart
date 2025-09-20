// -*- coding: utf-8 -*-
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// 单实例管理器
/// 确保应用只能运行一个实例
class SingleInstanceManager {
  static SingleInstanceManager? _instance;
  static SingleInstanceManager get instance {
    _instance ??= SingleInstanceManager._();
    return _instance!;
  }

  SingleInstanceManager._();

  static const String _lockFileName = 'gsou_app.lock';
  File? _lockFile;
  RandomAccessFile? _lockFileHandle;

  /// 检查是否已有实例运行
  /// 返回 true 表示当前是唯一实例，可以继续运行
  /// 返回 false 表示已有实例运行，应该退出
  Future<bool> checkAndLockInstance() async {
    try {
      print('开始单实例检查...');

      // 获取应用数据目录，增加超时和错误处理
      Directory? appDir;
      try {
        appDir = await getApplicationSupportDirectory().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('获取应用数据目录超时'),
        );
      } catch (e) {
        print('获取应用数据目录失败，使用临时目录: $e');
        // 如果获取应用数据目录失败，使用当前目录的temp子目录
        appDir = Directory(path.join(Directory.current.path, 'temp'));
        if (!await appDir.exists()) {
          await appDir.create(recursive: true);
        }
      }

      final lockFilePath = path.join(appDir.path, _lockFileName);
      _lockFile = File(lockFilePath);

      print('锁文件路径: $lockFilePath');

      // 确保锁文件目录存在
      await _lockFile!.parent.create(recursive: true);

      // 检查锁文件是否存在
      if (await _lockFile!.exists()) {
        print('发现锁文件，检查进程状态...');

        // 尝试读取现有锁文件中的PID
        try {
          final content = await _lockFile!.readAsString();
          final existingPid = int.tryParse(content.trim());
          print('锁文件中的PID: $existingPid');

          if (existingPid != null && existingPid != pid) {
            // 检查该PID对应的进程是否还在运行
            final isRunning = await _isProcessRunning(existingPid);
            print('PID $existingPid 是否运行: $isRunning');

            if (isRunning) {
              // 进程还在运行，尝试激活现有实例
              print('检测到应用已运行，尝试激活现有实例...');
              await _tryActivateExistingInstance();
              return false;
            } else {
              // 进程已经不存在，删除过期的锁文件
              print('清理过期的锁文件...');
              try {
                await _lockFile!.delete();
              } catch (e) {
                print('删除锁文件失败: $e');
              }
            }
          } else if (existingPid == pid) {
            // 当前进程的PID，允许继续
            print('检测到当前进程PID，允许继续运行');
            return true;
          }
        } catch (e) {
          // 锁文件损坏，删除并重新创建
          print('锁文件损坏，删除重建: $e');
          try {
            await _lockFile!.delete();
          } catch (deleteError) {
            print('删除损坏锁文件失败: $deleteError');
          }
        }
      } else {
        print('没有发现锁文件，创建新实例');
      }

      // 创建新的锁文件
      await _createLockFile();
      print('单实例检查完成，允许运行');
      return true;
    } catch (e) {
      print('单实例检查失败: $e');
      // 出错时允许运行，避免阻止正常启动
      return true;
    }
  }

  /// 创建锁文件
  Future<void> _createLockFile() async {
    try {
      // 确保目录存在
      await _lockFile!.parent.create(recursive: true);

      // 写入当前进程PID
      final currentPid = pid;
      await _lockFile!.writeAsString(currentPid.toString());

      // 尝试以独占模式打开文件（如果支持的话）
      try {
        _lockFileHandle = await _lockFile!.open(mode: FileMode.append);
      } catch (e) {
        // 某些平台可能不支持文件锁，忽略错误
      }

      print('创建实例锁文件: ${_lockFile!.path} (PID: $currentPid)');
    } catch (e) {
      print('创建锁文件失败: $e');
    }
  }

  /// 检查指定PID的进程是否还在运行
  Future<bool> _isProcessRunning(int pid) async {
    try {
      if (Platform.isWindows) {
        // Windows: 使用 tasklist 命令更可靠
        final result = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $pid'],
          runInShell: true,
        ).timeout(const Duration(seconds: 3));

        final output = result.stdout.toString();
        print('进程检查输出: $output');

        // 检查输出是否包含进程信息，同时验证是否为Gsou进程
        final lines = output.split('\n');
        for (final line in lines) {
          if (line.contains(pid.toString()) &&
              (line.toLowerCase().contains('gsou') || line.contains('.exe'))) {
            print('进程 $pid 检查结果: true (找到匹配的Gsou进程)');
            return true;
          }
        }

        print('进程 $pid 检查结果: false (未找到或非Gsou进程)');
        return false;
      } else if (Platform.isLinux || Platform.isMacOS) {
        // Unix系统: 使用 kill -0 命令
        final result = await Process.run('kill', ['-0', pid.toString()]);
        return result.exitCode == 0;
      }
    } catch (e) {
      // 命令执行失败，假设进程不存在
      print('进程检查异常: $e');
    }
    return false;
  }

  /// 尝试激活现有实例
  Future<void> _tryActivateExistingInstance() async {
    try {
      // 这里可以通过命名管道、套接字或其他IPC机制
      // 向现有实例发送激活信号
      // 由于Flutter桌面应用的限制，这里只是简单记录
      print('检测到应用已运行，尝试激活现有窗口');

      if (Platform.isWindows) {
        // Windows: 可以尝试查找并激活窗口
        await _activateWindowsApp();
      }
    } catch (e) {
      print('激活现有实例失败: $e');
    }
  }

  /// Windows平台激活现有应用窗口
  Future<void> _activateWindowsApp() async {
    try {
      // 使用PowerShell脚本查找并激活Gsou窗口
      final script = '''
\$proc = Get-Process | Where-Object {
  \$_.ProcessName -like "*gsou*" -or
  \$_.MainWindowTitle -like "*Gsou*"
} | Select-Object -First 1

if (\$proc) {
  Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32 {
      [DllImport("user32.dll")]
      public static extern bool SetForegroundWindow(IntPtr hWnd);
      [DllImport("user32.dll")]
      public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
"@
  [Win32]::ShowWindow(\$proc.MainWindowHandle, 9)  # SW_RESTORE
  [Win32]::SetForegroundWindow(\$proc.MainWindowHandle)
  Write-Host "Window activated"
} else {
  Write-Host "Window not found"
}
''';

      await Process.run(
        'powershell',
        ['-Command', script],
        runInShell: true,
      );
    } catch (e) {
      print('Windows窗口激活失败: $e');
    }
  }

  /// 释放实例锁
  Future<void> releaseLock() async {
    try {
      // 关闭文件句柄
      await _lockFileHandle?.close();
      _lockFileHandle = null;

      // 删除锁文件
      if (_lockFile != null && await _lockFile!.exists()) {
        await _lockFile!.delete();
        print('释放实例锁文件: ${_lockFile!.path}');
      }
    } catch (e) {
      print('释放锁文件失败: $e');
    }
  }

  /// 检查是否为唯一实例的静态方法
  static Future<bool> isUniqueInstance() async {
    return await instance.checkAndLockInstance();
  }

  /// 释放锁的静态方法
  static Future<void> release() async {
    await instance.releaseLock();
  }
}