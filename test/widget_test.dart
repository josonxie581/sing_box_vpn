// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gsou/providers/vpn_provider.dart';

/// 当前应用已不再使用默认计数器示例，这里改为最小冒烟测试：
/// 1. 能够创建并提供 VPNProvider
/// 2. WidgetTree 构建后可访问 provider
/// 3. 不触发桌面系统托盘 / window 管理等需要原生环境的逻辑
void main() {
  testWidgets('VPNProvider smoke build', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => VPNProvider(),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('SMOKE_OK'))),
        ),
      ),
    );

    // 允许一帧构建完成
    await tester.pump();

    // 断言文本存在
    expect(find.text('SMOKE_OK'), findsOneWidget);

    // 读取 provider 并做一个简单断言
    final context = tester.element(find.text('SMOKE_OK'));
    final provider = Provider.of<VPNProvider>(context, listen: false);
    expect(provider.configs, isEmpty);
  });
}
