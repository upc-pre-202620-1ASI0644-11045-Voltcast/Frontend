import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/data/auth_user.dart';

const _avatarColors = [AppColors.blue, Color(0xFF111827), Color(0xFF374151), Color(0xFF6B7FD7), Color(0xFF0F172A)];

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 56});

  final AuthUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      // Pending requests have no history yet: neutral grey like the mock-up.
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: user.isPending ? AppColors.disabledBg : null,
        gradient: user.isPending
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_avatarColors[user.id % _avatarColors.length], AppColors.headerBottom],
              ),
      ),
      child: Text(
        user.initials,
        style: TextStyle(
          fontSize: size * 0.32,
          fontWeight: FontWeight.w700,
          color: user.isPending ? AppColors.muted : Colors.white,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.background, required this.color});

  final String text;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Activo / Inactivo.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    return user.isActive
        ? const _Chip('Activo', background: Color(0xFFE8F8EE), color: AppColors.success)
        : const _Chip('Inactivo', background: AppColors.disabledBg, color: AppColors.muted);
  }
}

/// Supervisor (black) / Ingeniero (blue).
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    return user.isAdmin
        ? const _Chip('Supervisor', background: AppColors.blueSoft, color: AppColors.blue)
        : const _Chip('Ingeniero', background: Color(0xFFEEF3FF), color: AppColors.blue);
  }
}

/// Row of the "Equipo" list with edit and enable/disable actions.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.user, required this.busy, required this.onEdit, required this.onToggle});

  final AuthUser user;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final canAct = user.isManageable && !busy;

    return Opacity(
      opacity: user.isDisabled ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.large, boxShadow: AppCard.shadow),
        child: Row(
          children: [
            UserAvatar(user: user, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(user: user),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RoleChip(user: user),
                      if (user.createdAt != null)
                        Text(
                          'Desde ${formatShortDate(user.createdAt!)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAction(tooltip: 'Editar', icon: Icons.edit_outlined, size: 38, onPressed: canAct ? onEdit : null),
                const SizedBox(height: 8),
                if (busy)
                  const SizedBox.square(
                    dimension: 38,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue),
                    ),
                  )
                else
                  CircleAction(
                    tooltip: user.isDisabled ? 'Habilitar' : 'Deshabilitar',
                    icon: user.isDisabled ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 38,
                    onPressed: canAct ? onToggle : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Row in "SOLICITUDES PENDIENTES" with Aprobar / Rechazar.
class PendingRequestCard extends StatelessWidget {
  const PendingRequestCard({
    super.key,
    required this.user,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final AuthUser user;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final approve = SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: busy ? null : onApprove,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
          backgroundColor: AppColors.teal,
          // Stays coloured while the request runs so the white spinner is visible.
          disabledBackgroundColor: AppColors.teal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text('Aprobar', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
    final reject = SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: busy ? null : onReject,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.35)),
          foregroundColor: AppColors.error,
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: const Text('Rechazar', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.large, boxShadow: AppCard.shadow),
      // Wide: avatar | text | buttons on one row. Narrow: buttons drop below.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
            children: [
              UserAvatar(user: user, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (constraints.maxWidth >= 430) {
            return Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 12),
                approve,
                const SizedBox(width: 8),
                reject,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              info,
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: approve),
                  const SizedBox(width: 8),
                  Expanded(child: reject),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
