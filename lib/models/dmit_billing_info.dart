/// DMIT-side monthly transfer data projected by the background browser helper.
///
/// These values come from the provider account and are deliberately kept
/// separate from SSH operating-system counters.
class DmitBillingInfo {
  const DmitBillingInfo({
    required this.serviceId,
    required this.name,
    required this.addresses,
    required this.usedMb,
    required this.limitMb,
    required this.transferMethod,
    required this.suspendWhenExceeded,
    required this.resetDisabled,
    required this.nextDueDate,
  });

  final String serviceId;
  final String name;
  final List<String> addresses;
  final double usedMb;
  final double limitMb;
  final String transferMethod;
  final bool suspendWhenExceeded;
  final bool resetDisabled;
  final String? nextDueDate;

  factory DmitBillingInfo.fromJson(Map<String, dynamic> json) {
    final serviceId = _requiredString(json['serviceId'], maxLength: 32);
    final name = _requiredString(json['name'], maxLength: 256);
    final usedMb = _finiteNumber(json['usedMb']);
    final limitMb = _finiteNumber(json['limitMb']);
    final method = _requiredString(json['transferMethod'], maxLength: 32);
    final rawAddresses = json['addresses'];
    if (!RegExp(r'^\d+$').hasMatch(serviceId) ||
        usedMb == null ||
        usedMb < 0 ||
        limitMb == null ||
        limitMb < 0 ||
        rawAddresses is! List ||
        rawAddresses.length > 32 ||
        json['suspendWhenExceeded'] is! bool ||
        json['resetDisabled'] is! bool) {
      throw const FormatException('Invalid DMIT billing snapshot');
    }
    final addresses = rawAddresses
        .map((value) => _requiredString(value, maxLength: 512))
        .toSet()
        .toList(growable: false);
    final dueDate = json['nextDueDate'];
    if (dueDate != null &&
        (dueDate is! String || !_datePattern.hasMatch(dueDate))) {
      throw const FormatException('Invalid DMIT billing date');
    }
    return DmitBillingInfo(
      serviceId: serviceId,
      name: name,
      addresses: addresses,
      usedMb: usedMb,
      limitMb: limitMb,
      transferMethod: method,
      suspendWhenExceeded: json['suspendWhenExceeded'] as bool,
      resetDisabled: json['resetDisabled'] as bool,
      nextDueDate: dueDate as String?,
    );
  }

  factory DmitBillingInfo.fromBridgeItem(Map<String, dynamic> item) {
    final product = _requiredMap(item['product']);
    final detail = _requiredMap(item['detail']);
    final productId = _id(product['id']);
    final detailId = _id(detail['serviceid']);
    if (productId != detailId) {
      throw const FormatException('Mismatched DMIT service id');
    }
    final addresses = <String>{};
    _collectAddresses(addresses, product['domain']);
    _collectAddresses(addresses, product['primaryip']);
    _collectAddresses(addresses, product['ips']);
    _collectAddresses(addresses, detail['hostname']);
    _collectAddresses(addresses, detail['dedicatedip']);
    _collectAddresses(addresses, detail['assignedips']);
    final name = _firstString([
      product['domain'],
      detail['hostname'],
      productId,
    ]);
    final usedMb = _finiteNumber(detail['bwusage']);
    final limitMb = _finiteNumber(detail['bwlimit']);
    if (usedMb == null || usedMb < 0 || limitMb == null || limitMb < 0) {
      throw const FormatException('Invalid DMIT transfer values');
    }
    final method =
        _optionalString(detail['bw_method'], maxLength: 32) ?? 'both';
    final dueDate = _optionalString(detail['nextduedate'], maxLength: 32);
    if (dueDate != null && !_datePattern.hasMatch(dueDate)) {
      throw const FormatException('Invalid DMIT due date');
    }
    return DmitBillingInfo(
      serviceId: productId,
      name: name,
      addresses: addresses.toList(growable: false),
      usedMb: usedMb,
      limitMb: limitMb,
      transferMethod: method,
      suspendWhenExceeded: _boolean(detail['suspendonexceeded']),
      resetDisabled: _boolean(detail['bw_disable_reset']),
      nextDueDate: dueDate,
    );
  }

  Map<String, dynamic> toJson() => {
    'serviceId': serviceId,
    'name': name,
    'addresses': addresses,
    'usedMb': usedMb,
    'limitMb': limitMb,
    'transferMethod': transferMethod,
    'suspendWhenExceeded': suspendWhenExceeded,
    'resetDisabled': resetDisabled,
    'nextDueDate': nextDueDate,
  };

  bool get isUnmetered => limitMb <= 0;
  double get remainingMb =>
      isUnmetered ? double.infinity : (limitMb - usedMb).clamp(0, limitMb);
  double? get usageFraction =>
      isUnmetered ? null : (usedMb / limitMb).clamp(0, 1);

  DateTime? nextResetAt(DateTime now) {
    if (resetDisabled || nextDueDate == null) return null;
    final due = DateTime.tryParse('${nextDueDate!}T00:00:00Z');
    if (due == null) return null;
    final utc = now.toUtc();
    var candidate = _dateWithClampedDay(utc.year, utc.month, due.day);
    if (!candidate.isAfter(utc)) {
      candidate = _dateWithClampedDay(utc.year, utc.month + 1, due.day);
    }
    return candidate;
  }

  int? resetDaysAt(DateTime now) {
    final reset = nextResetAt(now);
    if (reset == null) return null;
    final seconds = reset.difference(now.toUtc()).inSeconds;
    return seconds <= 0 ? 0 : (seconds / Duration.secondsPerDay).ceil();
  }

  static String formatMb(double value) {
    if (!value.isFinite) return 'Unlimited';
    return '${(value / 1024).toStringAsFixed(2)} GB';
  }
}

final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime _dateWithClampedDay(int year, int month, int day) {
  final firstNextMonth = DateTime.utc(year, month + 1, 1);
  final lastDay = firstNextMonth.subtract(const Duration(days: 1)).day;
  return DateTime.utc(year, month, day.clamp(1, lastDay));
}

Map<String, dynamic> _requiredMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected an object');
  return Map<String, dynamic>.from(value);
}

String _id(Object? value) {
  final result = value?.toString().trim() ?? '';
  if (!RegExp(r'^\d+$').hasMatch(result)) {
    throw const FormatException('Invalid service id');
  }
  return result;
}

String _requiredString(Object? value, {required int maxLength}) {
  final result = _optionalString(value, maxLength: maxLength);
  if (result == null) throw const FormatException('Expected a string');
  return result;
}

String? _optionalString(Object? value, {required int maxLength}) {
  if (value == null) return null;
  if (value is! String) return null;
  final result = value.trim();
  if (result.isEmpty || result.length > maxLength) return null;
  return result;
}

String _firstString(List<Object?> values) {
  for (final value in values) {
    final result = _optionalString(value, maxLength: 256);
    if (result != null) return result;
  }
  throw const FormatException('Missing DMIT server name');
}

double? _finiteNumber(Object? value) {
  final result = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return result != null && result.isFinite ? result : null;
}

bool _boolean(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

void _collectAddresses(Set<String> output, Object? value) {
  if (value == null) return;
  if (value is Map) {
    for (final entry in value.values) {
      _collectAddresses(output, entry);
    }
    return;
  }
  if (value is Iterable) {
    for (final entry in value) {
      _collectAddresses(output, entry);
    }
    return;
  }
  if (value is! String) return;
  for (final part in value.split(RegExp(r'[\s,;]+'))) {
    final address = part.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (address.isNotEmpty && address.length <= 512) output.add(address);
  }
}
