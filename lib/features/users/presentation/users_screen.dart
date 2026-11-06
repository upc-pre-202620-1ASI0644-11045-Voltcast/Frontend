import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/submit_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/screen_header.dart';
import '../../auth/data/auth_user.dart';
import '../../auth/presentation/auth_controller.dart';
import 'users_controller.dart';
import 'users_widgets.dart';
import '../../home/settings_menu.dart';

/// The controller comes from above: it outlives this tab because the queue of
/// decisions and the Usuarios badge need it whichever tab is open.
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  /// Sends the decision and says how it ended: done, saved for later, or refused.
  Future<void> _decide(BuildContext context, AuthUser user, {required bool approve}) async {
    final controller = context.read<UsersController>();
    final messenger = ScaffoldMessenger.of(context);
    final name = user.fullName;
    try {
      final outcome = await (approve ? controller.approve(user) : controller.reject(user));
      final queued = outcome == ReviewOutcome.queued;
      messenger.showSnackBar(
        SnackBar(
          duration: Duration(seconds: queued ? 7 : 4),
          content: Text(switch ((queued, approve)) {
            (true, true) => 'Sin conexión. La aprobación de $name quedó guardada: se enviará al reconectar y entonces saldrá el correo.',
            (true, false) => 'Sin conexión. El rechazo de $name quedó guardado: se enviará al reconectar y entonces saldrá el correo.',
            (false, true) => 'Solicitud aprobada. $name ya puede iniciar sesión.',
            (false, false) => 'Solicitud rechazada.',
          }),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reject(BuildContext context, AuthUser user) async {
    final ok = await confirmDialog(
      context,
      title: '¿Rechazar solicitud?',
      message: '${user.fullName} no tendrá acceso al sistema.',
      action: 'Rechazar',
    );
    if (ok && context.mounted) await _decide(context, user, approve: false);
  }

  Future<void> _toggle(BuildContext context, AuthUser user) async {
    final controller = context.read<UsersController>();
    if (user.isActive) {
      final ok = await confirmDialog(
        context,
        title: '¿Deshabilitar cuenta?',
        message: '${user.fullName} no podrá iniciar sesión hasta que la habilites de nuevo.',
        action: 'Deshabilitar',
      );
      if (!ok || !context.mounted) return;
    }
    if (!context.mounted) return;
    await runAction(
      context,
      () => controller.setEnabled(user, enabled: user.isDisabled),
      user.isActive ? 'Cuenta deshabilitada.' : 'Cuenta habilitada.',
    );
  }

  Future<void> _edit(BuildContext context, AuthUser user) {
    final controller = context.read<UsersController>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditUserSheet(user: user, controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = context.watch<UsersController>();
    // Absent in screen tests that mount this tab alone.
    final auth = Provider.of<AuthController?>(context, listen: false);
    // A tab of the bottom bar: no way back to offer.
    final header = BrandHeader(
      eyebrow: 'Gestión de accesos',
      title: 'Usuarios',
      onLogout: auth?.logout,
      onSettings: settingsAction(context),
      bottom: users.hasLoaded
          ? StatRow(
              tiles: [
                StatTile(label: 'Usuarios', value: users.accounts.length),
                StatTile(
                  label: 'Activos',
                  value: users.accounts.where((u) => u.isActive).length,
                  color: AppColors.success,
                ),
                StatTile(label: 'Pendientes', value: users.awaitingDecision.length, color: AppColors.amber),
              ],
            )
          : null,
    );

    return Scaffold(backgroundColor: AppColors.surface, body: _body(context, users, header));
  }

  Widget _body(BuildContext context, UsersController users, Widget header) {
    if (!users.hasLoaded) {
      return Column(
        children: [
          header,
          Expanded(
            child: users.loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
                : _LoadError(message: users.loadError ?? 'No se pudo cargar.', onRetry: users.load),
          ),
        ],
      );
    }

    final pending = users.pending;
    final accounts = users.accounts;
    final waiting = users.awaitingDecision.length;

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: users.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          header,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ReviewSyncBanner(),
                if (users.offline) ...[
                  const NoticeBanner(
                    icon: Icons.cloud_off_outlined,
                    text:
                        'No se pudo actualizar: sin conexión. Ves los últimos datos recibidos; lo que apruebes o rechaces se enviará al reconectar.',
                  ),
                  const SizedBox(height: 16),
                ] else if (users.loadError != null) ...[
                  ErrorBanner(users.loadError!),
                  const SizedBox(height: 16),
                ],
                SectionTitle(
                  'Solicitudes',
                  trailing: switch (waiting) {
                    0 when pending.isEmpty => null,
                    0 => '${pending.length} por sincronizar',
                    1 => '1 pendiente',
                    _ => '$waiting pendientes',
                  },
                ),
                const SizedBox(height: 12),
                if (pending.isEmpty)
                  const _AllClear()
                else
                  for (final user in pending) ...[
                    PendingRequestCard(
                      user: user,
                      busy: users.isBusy(user.id),
                      onApprove: () => _decide(context, user, approve: true),
                      onReject: () => _reject(context, user),
                      queuedApproval: users.queuedReview(user.id)?.approve,
                      onUndo: users.syncing ? null : () => users.cancelQueued(user.id),
                    ),
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 24),
                SectionTitle('Equipo', trailing: accounts.length == 1 ? '1 usuario' : '${accounts.length} usuarios'),
                const SizedBox(height: 12),
                if (accounts.isEmpty)
                  const InfoBox(text: 'Aún no hay usuarios registrados.')
                else
                  for (final user in accounts) ...[
                    AccountCard(
                      user: user,
                      busy: users.isBusy(user.id),
                      onEdit: () => _edit(context, user),
                      onToggle: () => _toggle(context, user),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Decisions waiting to be sent and the result of the last sync. Renders nothing
/// when there is nothing to say.
class _ReviewSyncBanner extends StatelessWidget {
  const _ReviewSyncBanner();

  @override
  Widget build(BuildContext context) {
    final users = context.watch<UsersController>();
    final count = users.queuedCount;
    final notice = users.syncNotice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (count > 0) ...[
          NoticeBanner(
            text: [
              count == 1 ? '1 decisión pendiente de sincronizar.' : '$count decisiones pendientes de sincronizar.',
              users.syncIssue ??
                  (count == 1
                      ? 'Se enviará al servidor cuando se recupere la conexión; entonces saldrá el correo.'
                      : 'Se enviarán al servidor cuando se recupere la conexión; entonces saldrán los correos.'),
            ].join(' '),
            actionLabel: users.syncing ? 'Sincronizando…' : 'Reintentar ahora',
            onAction: users.syncing ? null : users.syncQueue,
          ),
          const SizedBox(height: 16),
        ],
        if (notice != null) ...[
          if (users.syncNoticeIsProblem)
            NoticeBanner(text: notice, onClose: users.dismissSyncNotice)
          else
            NoticeBanner(
              text: notice,
              icon: Icons.cloud_done_outlined,
              background: const Color(0xFFE8F8EE),
              foreground: AppColors.success,
              onClose: users.dismissSyncNotice,
            ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

/// No pending requests: a calm dashed box instead of an empty list.
class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: AppRadius.large,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Color(0xFFE8F8EE), shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 20, color: AppColors.success),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Todo al día',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                Text('No hay solicitudes pendientes.', style: TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorBanner(message),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Reintentar', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _EditUserSheet extends StatefulWidget {
  const _EditUserSheet({required this.user, required this.controller});

  final AuthUser user;
  final UsersController controller;

  @override
  State<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends State<_EditUserSheet> with SubmitState {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.fullName);
  late final _email = TextEditingController(text: widget.user.email);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _changed =>
      _name.text.trim() != widget.user.fullName || _email.text.trim().toLowerCase() != widget.user.email;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await submit(() => widget.controller.edit(widget.user, fullName: _name.text, email: _email.text));
    if (ok) {
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Datos actualizados.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Editar usuario',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const SizedBox(height: 24),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextField(
                        label: 'Nombre completo',
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        validator: Validators.fullName,
                        enabled: !loading,
                      ),
                      const SizedBox(height: 20),
                      AppTextField(
                        label: 'Correo electrónico',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        validator: Validators.email,
                        onSubmitted: (_) => _changed ? _save() : null,
                        enabled: !loading,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (error != null) ...[ErrorBanner(error!), const SizedBox(height: 16)],
                ListenableBuilder(
                  listenable: Listenable.merge([_name, _email]),
                  builder: (context, _) =>
                      PrimaryButton(label: 'Guardar cambios', loading: loading, onPressed: _changed ? _save : null),
                ),
                const SizedBox(height: 12),
                SecondaryButton(label: 'Cancelar', onPressed: loading ? null : () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
