import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
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

    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected < 0 ? 0 : selected,
        onDestinationSelected: (i) => _select(branches[i]),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
          if (isAdmin)
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _pending > 0,
                label: Text('$_pending'),
                child: const Icon(Icons.group_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _pending > 0,
                label: Text('$_pending'),
                child: const Icon(Icons.group),
              ),
              label: 'Usuarios',
              tooltip: _pending == 0
                  ? 'Usuarios'
                  : 'Usuarios: $_pending ${_pending == 1 ? 'solicitud pendiente' : 'solicitudes pendientes'}',
            ),
        ],
      ),
    );
  }
}
