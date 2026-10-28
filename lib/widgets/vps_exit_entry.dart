import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../providers/vpn_provider_v2.dart';
import '../screens/vps_exit_page.dart';
import '../theme/app_theme.dart';
import '../utils/dmit_nodes.dart';

/// Expose VPS management only while the node list contains a DMIT node.
class VpsExitEntry extends StatelessWidget {
  const VpsExitEntry({super.key});

  @override
  Widget build(BuildContext context) => Consumer<VPNProviderV2>(
    builder: (context, provider, _) {
      if (defaultTargetPlatform != TargetPlatform.windows ||
          findDmitNode(provider.configs) == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(
              Icons.cloud_sync_outlined,
              color: AppTheme.primaryNeon,
            ),
            title: const Text('VPS 出口管控'),
            subtitle: const Text('服务器出口规则 / 住宅 IP'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              if (findDmitNode(provider.configs) == null) return;
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const _DmitVpsPage()));
            },
          ),
        ),
      );
    },
  );
}

class _DmitVpsPage extends StatelessWidget {
  const _DmitVpsPage();

  @override
  Widget build(BuildContext context) => Consumer<VPNProviderV2>(
    builder: (context, provider, _) {
      final node = findDmitNode(
        provider.configs,
        preferred: provider.currentConfig,
      );
      if (node != null) return VpsExitPage(serverHost: node.server);
      // Disposing the page also stops further client-side SSH polling.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || findDmitNode(provider.configs) != null) return;
        final route = ModalRoute.of(context);
        if (route != null && route.isActive && !route.isFirst) {
          Navigator.of(context).removeRoute(route);
        }
      });
      return const SizedBox.shrink();
    },
  );
}
