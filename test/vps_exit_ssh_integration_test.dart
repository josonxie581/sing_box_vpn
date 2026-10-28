import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/vps_exit_config.dart';
import 'package:gsou/services/vps_exit_service.dart';

void main() {
  test(
    'read-only real SSH status and validation share the website policy',
    () async {
      final profile = VpsExitProfile(
        host: const String.fromEnvironment('GSOU_VPS_HOST'),
        identityFile: const String.fromEnvironment('GSOU_VPS_KEY'),
        knownHostsFile: const String.fromEnvironment('GSOU_VPS_KNOWN_HOSTS'),
      );
      final service = VpsExitService();
      final status = VpsExitStatus.fromJson(
        await service.call(profile, 'status'),
      );
      final checked = await service.call(profile, 'validate', {
        'policy': status.policy.toJson(),
        'expected_revision': status.revision,
      });
      expect(checked['valid'], isTrue);
      expect(checked['unchanged'], isTrue);
      final after = VpsExitStatus.fromJson(
        await service.call(profile, 'status'),
      );
      expect(after.revision, status.revision);
    },
    skip: !const bool.fromEnvironment('GSOU_VPS_LIVE'),
  );
}
