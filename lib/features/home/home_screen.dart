import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_header.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/auth_visuals.dart';
import '../auth/presentation/auth_controller.dart';

/// Engineer landing. The forecasting dashboard of the mock-up needs the ML
/// module, which does not exist yet, so for now it links to what is real.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
              child: ListView(
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
          ],
        ),
      ),
    );
  }
}
