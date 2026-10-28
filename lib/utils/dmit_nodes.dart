import '../models/vpn_config.dart';

final _dmitName = RegExp(
  r'(^|[^a-z0-9])dmit([^a-z0-9]|$)',
  caseSensitive: false,
);

/// Match the explicit provider marker, consistently with the DMIT status card.
bool isDmitNode(VPNConfig config) => _dmitName.hasMatch(config.name);

VPNConfig? findDmitNode(Iterable<VPNConfig> configs, {VPNConfig? preferred}) {
  VPNConfig? first;
  for (final config in configs) {
    if (!isDmitNode(config)) continue;
    if (config.id == preferred?.id) return config;
    first ??= config;
  }
  return first;
}
