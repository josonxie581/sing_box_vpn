import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vps_exit_config.dart';
import 'package:gsou/screens/vps_exit_page.dart';
import 'package:gsou/services/vps_exit_controller.dart';
import 'package:gsou/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'vps_exit_fakes.dart';

Map<String, dynamic> fourExitStatus() {
  final data = exitStatus(singapore: true);
  (data['exits'] as Map)['au'] = {'label': '日本住宅 IP', 'ip': '61.124.29.24'};
  (data['exits'] as Map)['australia'] = {
    'label': '澳大利亚住宅 IP',
    'ip': '163.8.194.100',
  };
  data['policy'] = {
    'default': 'australia',
    'claude': 'australia',
    'openai': 'australia',
    'direct_domains': <String>[],
    'australia_domains': ['japan.example'],
    'singapore_domains': ['sg.example'],
    'australia_exit_domains': ['au.example'],
  };
  return data;
}

class FourExitTransport extends FakeVpsTransport {
  @override
  Future<Map<String, dynamic>> call(
    VpsExitProfile profile,
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (action == 'status') return fourExitStatus();
    return super.call(profile, action, data);
  }
}

void main() {
  test('four exit response parses and preserves every domain group', () {
    final status = VpsExitStatus.fromJson(fourExitStatus());
    expect(status.availableTargets.map((v) => v.value), [
      'direct',
      'au',
      'sg',
      'australia',
    ]);
    final encoded = status.encodePolicy(status.policy);
    expect(encoded['default'], 'australia');
    expect(encoded['australia_exit_domains'], ['au.example']);
    expect(encoded['australia_domains'], ['japan.example']);
    expect(encoded['singapore_domains'], ['sg.example']);
    final bad = fourExitStatus();
    (bad['policy'] as Map)['direct_domains'] = ['sub.au.example'];
    expect(() => VpsExitStatus.fromJson(bad), throwsFormatException);
  });
  testWidgets(
    'four exit editor shows current Australia policy and preserves edits',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fake = FourExitTransport();
      final controller = VpsExitController(fake);
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
      expect(controller.error, isNull);
      expect(find.textContaining('当前生效：Claude → 澳大利亚住宅 IP'), findsOneWidget);
      expect(
        tester
            .widgetList<DropdownButtonFormField<VpsExitTarget>>(
              find.byType(DropdownButtonFormField<VpsExitTarget>),
            )
            .length,
        3,
      );
      final field = find.widgetWithText(TextField, '走澳大利亚住宅 IP的域名');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'new.au.example');
      await tester.ensureVisible(find.text('检查规则'));
      await tester.tap(find.text('检查规则'));
      await tester.pumpAndSettle();
      expect(fake.calls.last['data']['policy']['australia_exit_domains'], [
        'new.au.example',
      ]);
      expect(fake.calls.last['data']['policy']['australia_domains'], [
        'japan.example',
      ]);
      expect(fake.calls.last['data']['policy']['singapore_domains'], [
        'sg.example',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
