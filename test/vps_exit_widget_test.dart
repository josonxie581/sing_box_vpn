import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vps_exit_config.dart';
import 'package:gsou/screens/vps_exit_page.dart';
import 'package:gsou/services/vps_exit_controller.dart';
import 'package:gsou/services/vps_exit_service.dart';
import 'package:gsou/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vps_exit_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('restored profile remains editable after automatic read', (
    tester,
  ) async {
    await VpsExitService.saveProfile(exitProfile);
    final fake = FakeVpsTransport();
    final controller = VpsExitController(fake, pollInterval: Duration.zero);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: VpsExitPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '检查规则'),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('连接信息已修改，请先重新连接。'), findsNothing);
    expect(fake.calls.map((v) => v['action']), ['status']);
  });
  testWidgets(
    'loads remote policy without changing the server and fits narrow windows',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakeVpsTransport();
      final c = VpsExitController(fake, pollInterval: Duration.zero);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: VpsExitPage(controller: c, initialProfile: exitProfile),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('VPS 出口管控'), findsOneWidget);
      expect(find.text('当前管理：192.0.2.1'), findsOneWidget);
      expect(fake.calls.map((v) => v['action']), ['status']);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('检查规则'));
      await tester.tap(find.text('检查规则'));
      await tester.pumpAndSettle();
      expect(find.text('检查通过，与当前生效规则一致'), findsOneWidget);
      expect(fake.calls.last['action'], 'validate');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'apply requires explicit confirmation then uses the shared server revision',
    (tester) async {
      final fake = FakeVpsTransport();
      final controller = VpsExitController(fake, pollInterval: Duration.zero);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: VpsExitPage(
            controller: controller,
            initialProfile: exitProfile,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存并应用'));
      await tester.tap(find.text('保存并应用'));
      await tester.pumpAndSettle();
      expect(find.text('应用 VPS 出口规则'), findsOneWidget);
      expect(fake.calls.where((v) => v['action'] == 'apply'), isEmpty);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      final apply = fake.calls.singleWhere((v) => v['action'] == 'apply');
      expect(apply['data']['expected_revision'], repeat('a', 64));
      expect(apply['data']['policy'], const VpsExitPolicy().toJson());
      expect(find.text('规则已生效'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
