import 'package:flutter_test/flutter_test.dart';
import 'package:gsou/models/dmit_billing_info.dart';

void main() {
  test(
    'parses the provider billing snapshot and computes remaining transfer',
    () {
      final info = DmitBillingInfo.fromJson({
        'serviceId': '159947',
        'name': 'DMIT-JP-Gsou',
        'addresses': ['154.31.116.184'],
        'usedMb': 324262.0,
        'limitMb': 512000.0,
        'transferMethod': 'both',
        'suspendWhenExceeded': true,
        'resetDisabled': false,
        'nextDueDate': '2027-01-01',
      });

      expect(info.remainingMb, 187738.0);
      expect(info.usageFraction, closeTo(0.63332421875, 0.0000001));
      expect(DmitBillingInfo.formatMb(info.remainingMb), '183.34 GB');
      expect(
        info.nextResetAt(DateTime.utc(2026, 10, 17, 8)),
        DateTime.utc(2026, 11, 1),
      );
      expect(info.resetDaysAt(DateTime.utc(2026, 10, 17, 8)), 15);
    },
  );

  test('projects only whitelisted bridge fields', () {
    final info = DmitBillingInfo.fromBridgeItem({
      'product': {
        'id': 159947,
        'domain': 'DMIT-JP-Gsou',
        'primaryip': '154.31.116.184',
        'ips': {
          'v6': ['2403:18c0:1001:1fe::'],
        },
      },
      'detail': {
        'serviceid': '159947',
        'hostname': 'dmit-jp-gsou',
        'vm_core': 1,
        'vm_ram': 1024,
        'disklimit': 20480,
        'bwusage': '324262',
        'bwlimit': '512000',
        'bw_method': 'both',
        'bw_disable_reset': 0,
        'nextduedate': '2027-01-01',
        'suspendonexceeded': 1,
      },
    });

    expect(info.serviceId, '159947');
    expect(info.addresses, containsAll(['154.31.116.184', 'dmit-jp-gsou']));
    expect(info.suspendWhenExceeded, isTrue);
  });

  test('rejects mismatched service ids', () {
    expect(
      () => DmitBillingInfo.fromBridgeItem({
        'product': {'id': 1, 'domain': 'x'},
        'detail': {
          'serviceid': 2,
          'bwusage': 1,
          'bwlimit': 2,
          'nextduedate': '2027-01-01',
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects malformed normalized data', () {
    expect(
      () => DmitBillingInfo.fromJson({
        'serviceId': '159947',
        'name': 'DMIT',
        'addresses': ['154.31.116.184'],
        'usedMb': double.nan,
        'limitMb': 512000,
        'transferMethod': 'both',
        'suspendWhenExceeded': true,
        'resetDisabled': false,
      }),
      throwsFormatException,
    );
  });
}
