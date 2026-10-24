import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/presentation/auth_controller.dart';
import 'home_screen.dart';
import 'supervisor_home_screen.dart';

/// `/home` shows a different landing per role.
class HomeGate extends StatelessWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthController>().user?.isAdmin ?? false;
    return isAdmin ? const SupervisorHomeScreen() : const HomeScreen();
  }
}
