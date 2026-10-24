import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_header.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/auth_visuals.dart';
import '../auth/presentation/auth_controller.dart';
import '../users/data/users_repository.dart';

/// Supervisor landing. The forecasting KPIs, alerts and per-cell cards of the
/// mock-up need the ML and cell modules, which do not exist yet, so this only
/// offers what is real today: user management with the pending counter.
class SupervisorHomeScreen extends StatefulWidget {
  const SupervisorHomeScreen({super.key});

  @override
  State<SupervisorHomeScreen> createState() => _SupervisorHomeScreenState();
}

class _SupervisorHomeScreenState extends State<SupervisorHomeScreen> {
  int? _pendingCount;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    try {
      final pending = await context.read<UsersRepository>().list(status: 'pending');
      if (mounted) setState(() => _pendingCount = pending.length);
    } on ApiException {
      // The badge is a convenience; the Usuarios screen reports real errors.
    }
  }

  Future<void> _openUsers() async {
    await context.push('/users');
    if (mounted) _loadPending();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              actions: [
                IconButton(
                  tooltip: 'Cerrar sesión',
                  onPressed: () => context.read<AuthController>().logout(),
                  icon: const Icon(Icons.logout, color: AppColors.muted),
                ),
              ],
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.blue,
                onRefresh: _loadPending,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                  children: [
                    Text(
                      'Hola, ${user?.fullName.split(' ').first ?? ''}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(user?.roleLabel ?? '', style: AppTheme.subtitle),
                    const SizedBox(height: 28),
                    ShortcutTile(
                      icon: Icons.group_outlined,
                      label: 'Usuarios',
                      description: 'Solicitudes de acceso y cuentas de ingenieros',
                      badge: _pendingCount,
                      badgeText: _pendingCount == 1
                          ? '1 solicitud pendiente'
                          : '$_pendingCount solicitudes pendientes',
                      onTap: _openUsers,
                    ),
                    const SizedBox(height: 14),
                    ShortcutTile(
                      icon: Icons.electric_bolt_outlined,
                      label: 'Celdas y componentes',
                      description: 'Celdas eléctricas, cátodos, ánodos y códigos de barras',
                      onTap: () => context.push('/cells'),
                    ),
                    const SizedBox(height: 20),
                    const InfoBox(
                      text: 'Pronósticos de voltaje y alertas estarán disponibles en los '
                          'siguientes módulos.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
