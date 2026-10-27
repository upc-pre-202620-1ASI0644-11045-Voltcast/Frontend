import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'features/auth/presentation/auth_controller.dart';
import 'features/cells/data/inventory_repository.dart';
import 'features/cells/data/pending_swap.dart';
import 'features/cells/presentation/barcode_screen.dart';
import 'features/cells/presentation/cells_screen.dart';
import 'features/cells/presentation/components_screen.dart';
import 'features/cells/presentation/inventory_controller.dart';
import 'features/auth/presentation/screens/forgot_code_screen.dart';
import 'features/auth/presentation/screens/forgot_email_screen.dart';
import 'features/auth/presentation/screens/forgot_new_password_screen.dart';
import 'features/auth/presentation/screens/forgot_success_screen.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/register_screen.dart';
import 'features/auth/presentation/screens/reset_args.dart';
import 'features/home/home_gate.dart';
import 'features/users/presentation/users_screen.dart';
import 'splash_screen.dart';

const _publicPrefixes = ['/login', '/register', '/forgot'];

bool _isPublic(String location) => _publicPrefixes.any(location.startsWith);

GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final location = state.matchedLocation;

      switch (auth.status) {
        case AuthStatus.unknown:
          return location == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return _isPublic(location) ? null : '/login';
        case AuthStatus.authenticated:
          if (location == '/splash' || _isPublic(location)) return '/home';
          // Supervisor-only area (the backend also answers 403 to engineers).
          if (location.startsWith('/users') && auth.user?.isAdmin != true) return '/home';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeGate()),
      GoRoute(path: '/users', builder: (_, _) => const UsersScreen()),
      // The three screens read the same cells + components, so one controller
      // lives as long as the user stays inside this group.
      ShellRoute(
        builder: (context, state, child) => ChangeNotifierProvider(
          create: (context) => InventoryController(
            context.read<InventoryRepository>(),
            store: PrefsPendingSwapStore(),
          )..load(),
          child: child,
        ),
        routes: [
          GoRoute(path: '/cells', builder: (_, _) => const CellsScreen()),
          GoRoute(path: '/components', builder: (_, _) => const ComponentsScreen()),
          GoRoute(
            path: '/barcodes',
            builder: (_, state) => BarcodeScreen(
              initialCellId: int.tryParse(state.uri.queryParameters['cell'] ?? ''),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/forgot',
        builder: (_, _) => const ForgotEmailScreen(),
        routes: [
          GoRoute(
            path: 'code',
            // Extras are lost on a cold restart: go back to the first step.
            redirect: (_, state) => state.extra is String ? null : '/forgot',
            builder: (_, state) => ForgotCodeScreen(email: state.extra! as String),
          ),
          GoRoute(
            path: 'new-password',
            redirect: (_, state) => state.extra is ResetArgs ? null : '/forgot',
            builder: (_, state) => ForgotNewPasswordScreen(args: state.extra! as ResetArgs),
          ),
          GoRoute(path: 'success', builder: (_, _) => const ForgotSuccessScreen()),
        ],
      ),
    ],
  );
}
