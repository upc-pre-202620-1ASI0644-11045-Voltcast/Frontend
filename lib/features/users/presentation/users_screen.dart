import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/submit_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../auth/data/auth_user.dart';
import '../data/users_repository.dart';
import 'users_controller.dart';
import 'users_widgets.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => UsersController(context.read<UsersRepository>())..load(),
      child: const _UsersView(),
    );
  }
}

class _UsersView extends StatelessWidget {
  const _UsersView();

  Future<void> _reject(BuildContext context, AuthUser user) async {
    final controller = context.read<UsersController>();
    final ok = await confirmDialog(
      context,
      title: '¿Rechazar solicitud?',
      message: '${user.fullName} no tendrá acceso al sistema.',
      action: 'Rechazar',
    );
    if (ok && context.mounted) {
      await runAction(context, () => controller.reject(user), 'Solicitud rechazada.');
    }
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

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(onBack: () => context.canPop() ? context.pop() : context.go('/home')),
            Expanded(child: _body(context, users)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, UsersController users) {
    if (!users.hasLoaded) {
      if (users.loading) {
        return const Center(child: CircularProgressIndicator(color: AppColors.blue));
      }
      return _LoadError(message: users.loadError ?? 'No se pudo cargar.', onRetry: users.load);
    }

    final pending = users.pending;
    final accounts = users.accounts;

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: users.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          const Text(
            'Gestión de usuarios',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.ink),
          ),
          if (users.loadError != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(users.loadError!),
          ],
          const SizedBox(height: 24),
          SectionLabel('Solicitudes pendientes · ${pending.length}'),
          const SizedBox(height: 12),
          if (pending.isEmpty)
            const InfoBox(text: 'No hay solicitudes pendientes.')
          else
            for (final user in pending) ...[
              PendingRequestCard(
                user: user,
                busy: users.isBusy(user.id),
                onApprove: () => runAction(
                  context,
                  () => context.read<UsersController>().approve(user),
                  'Solicitud aprobada. ${user.fullName} ya puede iniciar sesión.',
                ),
                onReject: () => _reject(context, user),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 16),
          SectionLabel('Usuarios · ${accounts.length}'),
          const SizedBox(height: 12),
          if (accounts.isEmpty)
            const InfoBox(text: 'Aún no hay usuarios registrados.')
          else
            _AccountGrid(
              children: [
                for (final user in accounts)
                  AccountCard(
                    user: user,
                    busy: users.isBusy(user.id),
                    onEdit: () => _edit(context, user),
                    onToggle: () => _toggle(context, user),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Two columns when there is room, one on very narrow screens.
class _AccountGrid extends StatelessWidget {
  const _AccountGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = constraints.maxWidth >= 320 ? 2 : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
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
      _name.text.trim() != widget.user.fullName ||
      _email.text.trim().toLowerCase() != widget.user.email;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await submit(
      () => widget.controller.edit(widget.user, fullName: _name.text, email: _email.text),
    );
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
                if (error != null) ...[
                  ErrorBanner(error!),
                  const SizedBox(height: 16),
                ],
                ListenableBuilder(
                  listenable: Listenable.merge([_name, _email]),
                  builder: (context, _) => PrimaryButton(
                    label: 'Guardar cambios',
                    loading: loading,
                    onPressed: _changed ? _save : null,
                  ),
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Cancelar',
                  onPressed: loading ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
