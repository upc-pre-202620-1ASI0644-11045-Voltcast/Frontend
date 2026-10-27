import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import 'inventory_controller.dart';

/// Offline-swap status: how many are waiting for the server, or the result of
/// the last sync. Renders nothing when there is nothing to say.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();
    final pending = inventory.pendingCount;

    final Widget banner;
    if (pending > 0) {
      banner = NoticeBanner(
        text: pending == 1
            ? '1 intercambio pendiente de sincronizar. Se enviará al servidor cuando se recupere la conexión a internet.'
            : '$pending intercambios pendientes de sincronizar. Se enviarán al servidor cuando se recupere la conexión a internet.',
        actionLabel: inventory.syncing ? 'Sincronizando…' : 'Reintentar ahora',
        onAction: inventory.syncing ? null : inventory.syncPending,
      );
    } else if (inventory.syncNotice != null) {
      banner = NoticeBanner(
        text: inventory.syncNotice!,
        icon: Icons.cloud_done_outlined,
        background: const Color(0xFFE8F8EE),
        foreground: AppColors.success,
        onClose: inventory.dismissSyncNotice,
      );
    } else {
      return const SizedBox.shrink();
    }

    return Padding(padding: const EdgeInsets.only(bottom: 14), child: banner);
  }
}
