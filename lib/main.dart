// -*- coding: utf-8 -*-
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;

import 'providers/vpn_provider_v2.dart';
import 'services/improved_traffic_stats_service.dart';
import 'services/singbox_ffi.dart';
import 'screens/simple_modern_home.dart';
import 'theme/app_theme.dart';
import 'widgets/speed_overlay.dart';
import 'utils/privilege_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await acrylic.Window.initialize();
  // 设置窗口效果为禁用
  await acrylic.Window.setEffect(effect: acrylic.WindowEffect.disabled);

  await windowManager.ensureInitialized();

  // 提前预加载 sing-box FFI 库（异步执行，不阻塞启动流程）
  if (Platform.isWindows) {
    // 异步预加载，不等待完成，这样不会阻塞应用启动
    SingBoxFFI.preloadLibrary();
  }

  // 在应用首次启动时弹出UAC权限请求
  if (Platform.isWindows) {
    try {
      final bool isElevated = PrivilegeManager.instance.isElevated();

      if (!isElevated) {
        print('检测到应用未以管理员权限运行，尝试提权...');

        // 直接请求UAC提权
        final bool elevated = await PrivilegeManager.instance.requestElevation(
          reason: '应用启动需要管理员权限以支持TUN模式和系统代理功能',
        );

        if (!elevated) {
          print('用户取消了权限请求，应用将以普通权限运行');
        }
      }

      // 重新检查权限状态并记录
      final bool finalElevated = PrivilegeManager.instance.isElevated();
      final TunAvailability tunStatus = PrivilegeManager.instance
          .checkTunAvailability();

      print('=== 权限状态检查 ===');
      print('管理员权限: ${finalElevated ? "已获取" : "未获取"}');
      print('TUN 模式状态: ${tunStatus.description}');
      print('==================');
    } catch (e) {
      print('权限检查失败: $e');
    }
  }

  const windowOptions = WindowOptions(
    size: Size(450, 710),
    minimumSize: Size(450, 710),
    maximumSize: Size(450, 12000),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'Gsou',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(true);
    await windowManager.setMaximizable(false);
    await windowManager.setMinimumSize(const Size(450, 710));
    await windowManager.setMaximumSize(const Size(450, 12000));
    await windowManager.setPreventClose(true); // 防止直接关闭

    // 设置窗口图标
    // try {
    //   await windowManager.setIcon('assets/app_icon.ico');
    // } catch (e) {
    //   print('设置窗口图标失败: $e');
    // }
  });

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => VPNProviderV2())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  final SystemTray _systemTray = SystemTray();
  // ignore: unused_field
  final AppWindow _appWindow = AppWindow();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  Timer? _taskbarTimer;
  bool _isMinimized = false;
  bool _isEnteringOverlay = false;
  bool _isRestoringWindow = false;
  String _lastTrayTip = '';
  String _lastTitle = '';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initSystemTray();
    _taskbarTimer?.cancel();
    _taskbarTimer = Timer.periodic(
      const Duration(seconds: 1),
      (t) => _updateTaskbarAndTray(),
    );
  }

  @override
  void dispose() {
    _taskbarTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  String _resolveTrayIconPath() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final assetsIcon = [
        exeDir,
        'data',
        'flutter_assets',
        'assets',
        'app_icon.ico',
      ].join(Platform.pathSeparator);
      if (File(assetsIcon).existsSync()) return assetsIcon;
    } catch (_) {}

    const devIcon = 'assets/app_icon.ico';
    if (File(devIcon).existsSync()) return devIcon;

    const runnerIcon = 'windows/runner/resources/app_icon.ico';
    if (File(runnerIcon).existsSync()) return runnerIcon;

    return devIcon;
  }

  Future<void> _initSystemTray() async {
    final String path = _resolveTrayIconPath();

    await _systemTray.initSystemTray(
      title: 'Gsou VPN',
      iconPath: path,
      toolTip: 'Gsou VPN Client',
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'Show',
        onClicked: (item) async {
          if (_isMinimized) {
            await _restoreNormalWindow();
          } else {
            await windowManager.show();
            await windowManager.focus();
          }
        },
      ),
      MenuItemLabel(
        label: 'Hide',
        onClicked: (item) async {
          await windowManager.hide();
        },
      ),
      MenuItemLabel(
        label: 'Overlay Mode',
        onClicked: (item) async {
          if (!_isMinimized) {
            await _enterOverlayMode();
          }
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Exit',
        onClicked: (item) async {
          await windowManager.destroy();
        },
      ),
    ]);

    await _systemTray.setContextMenu(menu);

    _systemTray.registerSystemTrayEventHandler((eventName) async {
      if (eventName == kSystemTrayEventClick) {
        if (_isMinimized) {
          await _restoreNormalWindow();
        } else {
          await windowManager.show();
          await windowManager.focus();
        }
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });
  }

  Future<void> _enterOverlayMode() async {
    if (_isEnteringOverlay || _isMinimized) return;
    _isEnteringOverlay = true;

    try {
      // 首先清除所有的导航栈，回到根页面
      if (_navigatorKey.currentState != null) {
        _navigatorKey.currentState!.popUntil((route) => route.isFirst);
      }

      // 短暂延迟确保导航完成
      await Future.delayed(const Duration(milliseconds: 100));

      // 隐藏当前窗口
      await windowManager.hide();

      // 短暂延迟确保窗口已隐藏
      await Future.delayed(const Duration(milliseconds: 150));

      // 设置透明效果
      await acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.transparent,
        color: Colors.transparent,
      );

      // 移除标题栏
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );

      // 设置窗口属性
      await windowManager.setTitle('');
      await windowManager.setSkipTaskbar(true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setMinimizable(false);
      await windowManager.setClosable(false);

      // 设置悬浮窗大小
      const overlaySize = Size(220, 30);
      await windowManager.setMinimumSize(overlaySize);
      await windowManager.setMaximumSize(overlaySize);
      await windowManager.setSize(overlaySize);

      // 设置位置在屏幕右上角
      await windowManager.setPosition(const Offset(100, 50));

      // 更新状态并重建界面
      setState(() => _isMinimized = true);

      // 等待界面重建完成
      await Future.delayed(const Duration(milliseconds: 50));

      // 显示悬浮窗
      await windowManager.show();

      await _updateTaskbarAndTray();
    } catch (e) {
      print('进入悬浮窗模式失败: $e');
      // 如果失败，恢复状态
      if (mounted) {
        setState(() => _isMinimized = false);
      }
      // 尝试恢复窗口显示
      try {
        await _restoreNormalWindow();
      } catch (restoreError) {
        print('恢复窗口失败: $restoreError');
      }
    } finally {
      _isEnteringOverlay = false;
    }
  }

  Future<void> _restoreNormalWindow() async {
    if (!_isMinimized || _isRestoringWindow) return;
    _isRestoringWindow = true;

    try {
      // 隐藏悬浮窗
      await windowManager.hide();

      // 短暂延迟
      await Future.delayed(const Duration(milliseconds: 150));

      // 恢复窗口效果
      await acrylic.Window.setEffect(effect: acrylic.WindowEffect.disabled);

      // 恢复标题栏
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );

      // 恢复窗口属性
      await windowManager.setTitle('Gsou');
      await windowManager.setSkipTaskbar(false);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setResizable(true);
      await windowManager.setMaximizable(false);
      await windowManager.setMinimizable(true);
      await windowManager.setClosable(true);

      // 重新设置窗口图标
      // try {
      //   await windowManager.setIcon('assets/app_icon.ico');
      // } catch (e) {
      //   print('恢复窗口图标失败: $e');
      // }

      // 恢复窗口大小
      await windowManager.setMinimumSize(const Size(450, 710));
      await windowManager.setMaximumSize(const Size(450, 12000));
      await windowManager.setSize(const Size(450, 710));

      // 更新状态并重建界面
      setState(() => _isMinimized = false);

      // 等待界面重建完成
      await Future.delayed(const Duration(milliseconds: 50));

      // 居中并显示
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      print('恢复普通窗口失败: $e');
      // 如果恢复失败，至少确保状态正确
      if (mounted) {
        setState(() => _isMinimized = false);
      }
    } finally {
      _isRestoringWindow = false;
    }
  }

  Future<void> _updateTaskbarAndTray() async {
    if (!mounted) return;
    final vpn = Provider.of<VPNProviderV2>(context, listen: false);
    const String baseTitle = 'Gsou';
    try {
      if (vpn.isConnected) {
        final String up = ImprovedTrafficStatsService.formatSpeed(
          vpn.uploadSpeed,
        );
        final String down = ImprovedTrafficStatsService.formatSpeed(
          vpn.downloadSpeed,
        );
        final String tip = 'U ' + up + '  D ' + down;
        if (_lastTrayTip != tip) {
          await _systemTray.setToolTip(tip);
          _lastTrayTip = tip;
        }
        if (_isMinimized) {
          if (_lastTitle != '') {
            await windowManager.setTitle('');
            _lastTitle = '';
          }
        } else {
          if (_lastTitle != baseTitle) {
            await windowManager.setTitle(baseTitle);
            _lastTitle = baseTitle;
          }
        }
      } else {
        if (_lastTrayTip != 'Gsou VPN') {
          await _systemTray.setToolTip('Gsou VPN');
          _lastTrayTip = 'Gsou VPN';
        }
        if (_lastTitle != baseTitle) {
          await windowManager.setTitle(baseTitle);
          _lastTitle = baseTitle;
        }
      }
    } catch (_) {}
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'minimize') {
      // 拦截最小化事件，改为进入悬浮窗模式
      if (!_isMinimized && !_isEnteringOverlay && !_isRestoringWindow) {
        // 确保在主线程中执行，并添加延迟以确保状态稳定
        Future.microtask(() {
          if (mounted &&
              !_isMinimized &&
              !_isEnteringOverlay &&
              !_isRestoringWindow) {
            _enterOverlayMode();
          }
        });
      }
    }
  }

  @override
  void onWindowClose() {
    // 拦截关闭事件，改为隐藏到托盘
    windowManager.hide();
  }

  @override
  void onWindowResize() {
    if (_isMinimized) return;
    // 保持窗口宽度为400
    windowManager.getSize().then((size) {
      if (size.width != 450) {
        windowManager.setSize(Size(450, size.height));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _isMinimized ? '' : 'Gsou VPN',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        return _isMinimized && !_isRestoringWindow
            ? Consumer<VPNProviderV2>(
                builder: (context, vpnProvider, child) => SpeedOverlay(
                  onRestore: () async {
                    if (!_isRestoringWindow) {
                      await _restoreNormalWindow();
                    }
                  },
                ),
              )
            : child!;
      },
      home: const SimpleModernHome(),
    );
  }
}
