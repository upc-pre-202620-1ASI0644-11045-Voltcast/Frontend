import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../auth/presentation/auth_controller.dart';
import '../users/data/users_repository.dart';

/// Branch order of the bottom bar, as declared in the router.
abstract final class MainTabs {
  static const home = 0;
  static const inventory = 1;
  static const users = 2;
}

/// Signed-in frame: a bottom bar with Inicio (the production line),
/// Inventario and, for supervisors, Usuarios with the pending-requests count.
/// Each tab keeps its own state while the others are shown.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    if (context.read<AuthController>().user?.isAdmin != true) return;
    try {
      final pending = await context.read<UsersRepository>().list(status: 'pending');
      if (mounted) setState(() => _pending = pending.length);
    } on ApiException {
      // The badge is a convenience; the Usuarios tab reports real errors.
    }
  }

  void _select(int branch) {
    final leavingUsers = widget.shell.currentIndex == MainTabs.users;
    // Tapping the current tab again goes back to its first screen.
    widget.shell.goBranch(branch, initialLocation: branch == widget.shell.currentIndex);
    // Requests may have been approved or rejected in the Usuarios tab.
    if (leavingUsers || branch == MainTabs.users) _loadPending();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthController>().user?.isAdmin ?? false;
    final branches = [MainTabs.home, MainTabs.inventory, if (isAdmin) MainTabs.users];
    final selected = branches.indexOf(widget.shell.currentIndex);

    final usersTooltip = _pending == 0
        ? 'Usuarios'
        : 'Usuarios: $_pending ${_pending == 1 ? 'solicitud pendiente' : 'solicitudes pendientes'}';
    final items = [
      (icon: _icon(Icons.home_outlined), label: 'Inicio', tooltip: 'Inicio', badge: 0),
      (icon: (Color c) => _CubeIcon(color: c), label: 'Inventario', tooltip: 'Inventario', badge: 0),
      if (isAdmin) (icon: _icon(Icons.people_outline), label: 'Usuarios', tooltip: usersTooltip, badge: _pending),
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: widget.shell,
      // Floating navy bar: the current tab is a lime pill with its name.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 60,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [BoxShadow(color: Color(0x330F172A), blurRadius: 20, offset: Offset(0, 8))],
          ),
          // Stretched: the lime pill fills the bar's height, not just the icon's.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _TabItem(
                    icon: items[i].icon,
                    label: items[i].label,
                    tooltip: items[i].tooltip,
                    badge: items[i].badge,
                    selected: i == (selected < 0 ? 0 : selected),
                    onTap: () => _select(branches[i]),
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
                Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: icon(color)),
                // Only the current tab spells its name; the others are icons.
                if (selected) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
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
  Widget build(BuildContext context) => CustomPaint(size: const Size.square(22), painter: _CubePainter(color));
}

class _CubePainter extends CustomPainter {
  const _CubePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = Offset(w / 2, h * 0.1), centre = Offset(w / 2, h * 0.46), bottom = Offset(w / 2, h * 0.9);
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
