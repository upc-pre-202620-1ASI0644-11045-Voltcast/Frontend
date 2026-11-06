import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../auth/presentation/auth_controller.dart';
import '../users/presentation/users_controller.dart';

/// Branch order of the bottom bar, as declared in the router.
abstract final class MainTabs {
  static const home = 0;
  static const inventory = 1;
  static const users = 2;
  static const forecasts = 3;
}

/// Signed-in frame: a bottom bar with Inicio (the cell line), Pronósticos,
/// Inventario and, for supervisors, Usuarios with the pending-requests count.
/// Each tab keeps its own state while the others are shown.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  void _select(BuildContext context, int branch) {
    final leavingUsers = shell.currentIndex == MainTabs.users;
    // Tapping the current tab again goes back to its first screen.
    shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
    // Requests may have been approved or rejected from another device.
    if (leavingUsers || branch == MainTabs.users) {
      context.read<UsersController>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthController>().user?.isAdmin ?? false;
    // Reading it creates it, which loads the list and restores the queue of
    // decisions; the backend only answers these requests to supervisors.
    // A decision already queued no longer waits for the supervisor: not counted.
    final pending = isAdmin
        ? context.watch<UsersController>().awaitingDecision.length
        : 0;
    final branches = [
      MainTabs.home,
      MainTabs.forecasts,
      MainTabs.inventory,
      if (isAdmin) MainTabs.users,
    ];
    final selected = branches.indexOf(shell.currentIndex);

    final usersTooltip = pending == 0
        ? 'Usuarios'
        : 'Usuarios: $pending ${pending == 1 ? 'solicitud pendiente' : 'solicitudes pendientes'}';
    final items = [
      (
        icon: _icon(Icons.home_outlined),
        label: 'Inicio',
        tooltip: 'Inicio',
        badge: 0,
      ),
      (
        icon: _icon(Icons.show_chart),
        label: 'Pronósticos',
        tooltip: 'Pronósticos',
        badge: 0,
      ),
      (
        icon: (Color c) => _CubeIcon(color: c),
        label: 'Inventario',
        tooltip: 'Inventario',
        badge: 0,
      ),
      if (isAdmin)
        (
          icon: _icon(Icons.people_outline),
          label: 'Usuarios',
          tooltip: usersTooltip,
          badge: pending,
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: shell,
      // Floating navy bar: the current tab is a lime pill with its name.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 60,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          // Stretched: the lime pill fills the bar's height, not just the icon's.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++)
                // The current tab is wider: it spells its name.
                Expanded(
                  flex: i == (selected < 0 ? 0 : selected) ? 3 : 1,
                  child: _TabItem(
                    icon: items[i].icon,
                    label: items[i].label,
                    tooltip: items[i].tooltip,
                    badge: items[i].badge,
                    selected: i == (selected < 0 ? 0 : selected),
                    onTap: () => _select(context, branches[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final Widget Function(Color color) icon;
  final String label;
  final String tooltip;
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.ink : const Color(0xFF94A3B8);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? AppColors.lime : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  child: icon(color),
                ),
                // Only the current tab spells its name; the others are icons.
                if (selected) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget Function(Color color) _icon(IconData icon) =>
    (color) => Icon(icon, size: 22, color: color);

/// Outlined cube for Inventario, as in the mock-ups (the icon font has none).
class _CubeIcon extends StatelessWidget {
  const _CubeIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size.square(22), painter: _CubePainter(color));
}

class _CubePainter extends CustomPainter {
  const _CubePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = Offset(w / 2, h * 0.1),
        centre = Offset(w / 2, h * 0.46),
        bottom = Offset(w / 2, h * 0.9);
    final left = w * 0.14, right = w * 0.86;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    // Hexagon outline, then the three inner edges meeting at the front corner.
    canvas.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(right, h * 0.28)
        ..lineTo(right, h * 0.72)
        ..lineTo(bottom.dx, bottom.dy)
        ..lineTo(left, h * 0.72)
        ..lineTo(left, h * 0.28)
        ..close(),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(left, h * 0.28)
        ..lineTo(centre.dx, centre.dy)
        ..lineTo(right, h * 0.28)
        ..moveTo(centre.dx, centre.dy)
        ..lineTo(bottom.dx, bottom.dy),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_CubePainter old) => old.color != color;
}
