import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vps_exit_config.dart';
import 'package:gsou/screens/vps_exit_page.dart';
import 'package:gsou/services/vps_exit_controller.dart';
import 'package:gsou/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'vps_exit_fakes.dart';

Map<String, dynamic> dynamicStatus({
  String ip = '203.0.113.77',
  String label = '加拿大新出口',
}) => {
  ...exitStatus(policy: const VpsExitPolicy(claude: VpsExitTarget.direct)),
  'policy_schema': 2,
  'policy': {
    'default': 'edge_ca_2027',
    'claude': 'edge_ca_2027',
    'openai': 'direct',
    'domain_rules': {
      'edge_ca_2027': ['ca.example'],
      'direct': ['direct.example'],
    },
  },
  'exits': {
    'direct': {'label': 'VPS 直连', 'ip': '192.0.2.1'},
    'edge_ca_2027': {'label': label, 'ip': ip},
  },
};

class DynamicTransport extends FakeVpsTransport {
  Map<String, dynamic> response = dynamicStatus();
  @override
  Future<Map<String, dynamic>> call(
    VpsExitProfile profile,
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (action == 'status') {
      if (submitted) {
        return {
          ...response,
          'job': {'id': repeat('b', 32), 'state': 'succeeded'},
        };
      }
      return response;
    }
    return super.call(profile, action, data);
  }
}

void main() {
  test('unseen ID and unused exit removal need no client release', () {
    final status = VpsExitStatus.fromJson(dynamicStatus());
    expect(status.availableTargets.map((t) => t.value), [
      'direct',
      'edge_ca_2027',
    ]);
    final encoded = status.encodePolicy(status.policy);
    expect(encoded['domain_rules']['edge_ca_2027'], ['ca.example']);
    final refreshed = VpsExitStatus.fromJson(
      dynamicStatus(ip: '203.0.113.88', label: '加拿大更名'),
    );
    expect(
      refreshed.address(VpsExitTarget.parse('edge_ca_2027')),
      '203.0.113.88',
    );
    expect(refreshed.label(VpsExitTarget.parse('edge_ca_2027')), '加拿大更名');
    final removed = dynamicStatus();
    (removed['exits'] as Map).remove('edge_ca_2027');
    expect(() => VpsExitStatus.fromJson(removed), throwsFormatException);
    expect(() => VpsExitTarget.parse('../shell'), throwsFormatException);
    final malformed = dynamicStatus();
    (malformed['exits'] as Map)['unused'] = {'label': 'bad', 'ip': 'invalid'};
    expect(() => VpsExitStatus.fromJson(malformed), throwsFormatException);
  });
  test(
    'unknown domain groups reject overlap and preserve explicit clearing',
    () {
      final status = VpsExitStatus.fromJson(dynamicStatus());
      expect(
        () => VpsExitPolicy(
          domainRules: {
            'edge_ca_2027': ['ca.example'],
            'direct': ['sub.ca.example'],
          },
        ).normalized(),
        throwsFormatException,
      );
      final cleared = status.encodePolicy(
        VpsExitPolicy(
          claude: VpsExitTarget.direct,
          domainRules: {'edge_ca_2027': []},
        ),
      );
      expect(cleared['domain_rules']['edge_ca_2027'], isEmpty);
    },
  );
  testWidgets(
    'unseen exit renders edits validates applies and survives IP changes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = DynamicTransport();
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
      expect(controller.error, isNull);
      final field = find.byKey(const ValueKey('domains-edge_ca_2027'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'edited.ca.example');
      await tester.ensureVisible(find.text('检查规则'));
      await tester.tap(find.text('检查规则'));
      await tester.pumpAndSettle();
      expect(
        fake.calls.last['data']['policy']['domain_rules']['edge_ca_2027'],
        ['edited.ca.example'],
      );
      await controller.apply(
        VpsExitPolicy(
          defaultTarget: VpsExitTarget.parse('edge_ca_2027'),
          claude: VpsExitTarget.direct,
          domainRules: {
            'edge_ca_2027': ['edited.ca.example'],
          },
        ),
      );
      expect(controller.error, isNull);
      expect(
        fake.calls.singleWhere(
          (c) => c['action'] == 'apply',
        )['data']['policy']['default'],
        'edge_ca_2027',
      );
      fake.submitted = false;
      fake.response = dynamicStatus(ip: '203.0.113.88', label: '加拿大更名');
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(controller.error, isNull);
      expect(find.textContaining('加拿大更名'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
