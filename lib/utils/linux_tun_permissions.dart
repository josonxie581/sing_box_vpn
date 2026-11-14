/// CAP_NET_ADMIN creates/configures TUN and routes; CAP_NET_RAW binds RTT
/// probes to the physical interface. Check effective permissions of this
/// running process, not capabilities stored on a file or its owner UID.
bool hasLinuxTunCapabilities(String processStatus) {
  final match = RegExp(
    r'^CapEff:\s*([0-9a-fA-F]+)\s*$',
    multiLine: true,
  ).firstMatch(processStatus);
  final effective = match == null
      ? null
      : BigInt.tryParse(match.group(1)!, radix: 16);
  final required = (BigInt.one << 12) | (BigInt.one << 13);
  return effective != null && (effective & required) == required;
}
