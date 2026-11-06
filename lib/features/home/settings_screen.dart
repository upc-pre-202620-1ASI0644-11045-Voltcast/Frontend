import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../auth/presentation/auth_controller.dart';

/// "Centro de control": the data and configuration entries. The voltage limit
/// is for supervisors only (the backend also answers 403 to engineers).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          children: [
            PageHeader(
              eyebrow: 'Datos y configuración',
              title: 'Centro de control',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/line'),
            ),
            if (user != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.navy,
                      child: Text(
                        user.initials,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            user.roleLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Divider(height: 1, color: Color(0xFFE3E7EE)),
            ),
            _Entry(
              icon: Icons.folder_outlined,
              color: AppColors.success,
              soft: const Color(0xFFE8F8EE),
              title: 'Archivos históricos',
              subtitle: 'Datos de voltaje · Excel',
              onTap: () => context.push('/datasets'),
            ),
            _Entry(
              icon: Icons.speed_outlined,
              color: AppColors.blue,
              soft: AppColors.blueSoft,
              title: 'Precisión del modelo',
              subtitle: 'Qué tanto acierta el pronóstico',
              onTap: () => context.push('/model'),
            ),
            if (user?.isAdmin == true)
              _Entry(
                icon: Icons.tune,
                color: AppColors.amber,
                soft: const Color(0xFFFFF1D6),
                title: 'Límite de voltaje',
                subtitle: 'Configuración del máximo',
                onTap: () => context.push('/limit'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.color,
    required this.soft,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
