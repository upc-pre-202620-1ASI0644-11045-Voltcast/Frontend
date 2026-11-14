import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/page_header.dart';
import '../data/drive_status.dart';
import 'drive_controller.dart';

/// "Integración con Google Drive": everyone sees the status; only the
/// supervisor ([canManage]) can connect or disconnect.
class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key, required this.canManage});

  final bool canManage;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // load() notifies, which is not allowed while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DriveController>().load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the browser (or any other app): ask again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<DriveController>().load();
    }
  }

  Future<void> _disconnect() async {
    final controller = context.read<DriveController>();
    final ok = await confirmDialog(
      context,
      title: 'Desconectar Google Drive',
      message: 'Dejarán de detectarse registros nuevos. Los datasets ya creados se conservan.',
      action: 'Desconectar',
    );
    if (ok) await controller.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriveController>();
    final status = c.status;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              eyebrow: 'Datos y configuración',
              title: 'Integración con Google Drive',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/settings'),
            ),
            Expanded(
              child: status == null
                  ? (c.error != null
                        ? LoadErrorView(message: c.error!, onRetry: c.load)
                        : const Center(child: CircularProgressIndicator()))
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (c.error != null) ...[
                          _Notice(
                            icon: Icons.cloud_off_outlined,
                            text: c.error == offlineMessage
                                ? '$offlineMessage Último estado guardado el ${formatDateTime(c.savedAt!)}.'
                                : c.error!,
                            actionLabel: 'Reintentar',
                            onAction: c.load,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (status.isRevoked) ...[
                          _Notice(
                            icon: Icons.error_outline,
                            background: const Color(0xFFFEF2F2),
                            foreground: const Color(0xFF991B1B),
                            text: 'Google revocó el acceso. Vuelve a conectar Drive.',
                            actionLabel: widget.canManage
                                ? 'Conectar Google Drive'
                                : null,
                            onAction: c.busy ? null : c.connect,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (status.syncFailed) ...[
                          const _Notice(
                            text: 'La última sincronización falló; se reintentará en la próxima ejecución diaria.',
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (c.actionError != null) ...[
                          ErrorBanner(c.actionError!),
                          const SizedBox(height: 12),
                        ],
                        _StatusCard(status),
                        const SizedBox(height: 16),
                        const _InfoBox(
                          'La sincronización es automática, una vez al día.',
                        ),
                        if (widget.canManage) ...[
                          const SizedBox(height: 24),
                          if (!status.connected && !status.isRevoked)
                            PrimaryButton(
                              label: 'Conectar Google Drive',
                              loading: c.busy,
                              onPressed: c.connect,
                            ),
                          if (status.connected)
                            SizedBox(
                              height: 56,
                              child: OutlinedButton.icon(
                                onPressed: c.busy ? null : _disconnect,
                                icon: const Icon(Icons.logout, size: 20),
                                label: const Text('Desconectar'),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(
                                    color: Color(0xFFF4A9A9),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppRadius.large,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    this.icon = Icons.sync_problem_outlined,
    this.background = const Color(0xFFFEF6E0),
    this.foreground = const Color(0xFF92400E),
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final IconData icon;
  final Color background;
  final Color foreground;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: AppRadius.medium,
    child: NoticeBanner(
      text: text,
      icon: icon,
      background: background,
      foreground: foreground,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

/// The featured blue card (state + linked account) and, once connected, one
/// tile each for the last sync and the connection date.
class _StatusCard extends StatelessWidget {
  const _StatusCard(this.status);

  final DriveStatus status;

  @override
  Widget build(BuildContext context) {
    final connected = status.connected;
    final lastSync = status.lastSyncAt;
    final connectedAt = status.connectedAt;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: connected ? AppColors.blue : AppColors.navy,
            borderRadius: AppRadius.large,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.storage_rounded,
                    size: 30,
                    color: Colors.white,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: connected ? 0.2 : 0.15,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      connected ? '• Conectado' : '• Desconectado',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                connected ? 'Cuenta vinculada' : 'Cuenta desvinculada',
                style: TextStyle(
                  fontSize: 13,
                  color: connected
                      ? Colors.white.withValues(alpha: 0.8)
                      : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                connected ? status.account ?? '—' : 'Correo sin vincular',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        if (connected) ...[
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _DateTile(
                    icon: Icons.sync,
                    label: 'Última sync',
                    date: lastSync,
                    empty: 'Aún no se ha sincronizado',
                  ),
                ),
                if (connectedAt != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateTile(
                      icon: Icons.schedule,
                      label: 'Conectado desde',
                      date: connectedAt,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.icon,
    required this.label,
    required this.date,
    this.empty = '—',
  });

  final IconData icon;
  final String label;
  final DateTime? date;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.large,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.blue),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 2),
          Text(
            date == null ? empty : formatShortDate(date),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          if (date != null)
            Text(
              formatTime(date),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.blueSoft,
      borderRadius: AppRadius.large,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 20, color: AppColors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.blue,
            ),
          ),
        ),
      ],
    ),
  );
}
