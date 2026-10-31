import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'features/auth/presentation/auth_controller.dart';
import 'features/cells/data/inventory_repository.dart';
import 'features/cells/data/pending_swap.dart';
import 'features/cells/presentation/barcode_screen.dart';
import 'features/cells/presentation/inventory_controller.dart';
import 'features/cells/presentation/cell_screen.dart';
import 'features/cells/presentation/storage_screen.dart';
import 'features/cells/presentation/swap_screen.dart';
import 'features/datasets/data/datasets_repository.dart';
import 'features/datasets/presentation/dataset_detail_screen.dart';
import 'features/datasets/presentation/datasets_controller.dart';
import 'features/datasets/presentation/datasets_screen.dart';
import 'features/forecasting/presentation/alert_rules_screen.dart';
import 'features/forecasting/presentation/cell_forecast_screen.dart';
import 'features/forecasting/presentation/evaluation_export.dart';
import 'features/forecasting/presentation/forecasts_screen.dart';
import 'features/forecasting/presentation/model_screen.dart';
import 'features/auth/presentation/screens/forgot_code_screen.dart';
import 'features/auth/presentation/screens/forgot_email_screen.dart';
import 'features/auth/presentation/screens/forgot_new_password_screen.dart';
import 'features/auth/presentation/screens/forgot_success_screen.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/register_screen.dart';
import 'features/auth/presentation/screens/reset_args.dart';
import 'features/home/main_shell.dart';
import 'features/home/settings_screen.dart';
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
          if (location == '/splash' || _isPublic(location)) return '/line';
          // Supervisor-only area (the backend also answers 403 to engineers).
          if ((location.startsWith('/users') ||
                  location.startsWith('/limit')) &&
              auth.user?.isAdmin != true) {
            return '/line';
          }
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      // These screens read the same cells + components, so one controller
      // lives as long as the user stays inside this group. Files live
      // here too.
      ShellRoute(
        builder: (context, state, child) => MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (context) => InventoryController(
                context.read<InventoryRepository>(),
                store: PrefsPendingSwapStore(),
              )..load(),
            ),
            ChangeNotifierProvider(
              create: (context) =>
                  DatasetsController(context.read<DatasetsRepository>()),
            ),
          ],
          child: child,
        ),
        routes: [
          // The bottom bar; branch order matches MainTabs.
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => MainShell(shell: shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/line',
                    builder: (_, _) => CellScreen(
                      userName: auth.user?.fullName.split(' ').first,
                      userRole: auth.user?.roleLabel,
                      onLogout: auth.logout,
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/storage',
                    builder: (_, _) => const StorageScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/users',
                    builder: (_, _) => const UsersScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/forecasts',
                    builder: (_, _) => const ForecastsScreen(),
                  ),
                ],
              ),
            ],
          ),
          // Open over the bar.
          GoRoute(
            path: '/swap',
            builder: (_, state) => SwapScreen(
              initialCellId: int.tryParse(
                state.uri.queryParameters['cell'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/forecasts/cell/:id',
            builder: (_, state) {
              final query = state.uri.queryParameters;
              DateTime? date(String key) =>
                  query[key] == null ? null : DateTime.tryParse(query[key]!);
              return CellForecastScreen(
                cellId: int.parse(state.pathParameters['id']!),
                name: query['name'],
                from: date('from'),
                to: date('to'),
              );
            },
          ),
          GoRoute(
            path: '/model',
            builder: (_, _) => const ModelScreen(export: shareEvaluationXlsx),
          ),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(path: '/datasets', builder: (_, _) => const DatasetsScreen()),
          GoRoute(
            path: '/datasets/:id',
            builder: (_, state) =>
                DatasetDetailScreen(id: int.parse(state.pathParameters['id']!)),
          ),
          GoRoute(path: '/limit', builder: (_, _) => const AlertRulesScreen()),
          GoRoute(
            path: '/barcodes',
            builder: (_, state) => BarcodeScreen(
              initialCellId: int.tryParse(
                state.uri.queryParameters['cell'] ?? '',
              ),
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
            builder: (_, state) =>
                ForgotCodeScreen(email: state.extra! as String),
          ),
          GoRoute(
            path: 'new-password',
            redirect: (_, state) => state.extra is ResetArgs ? null : '/forgot',
            builder: (_, state) =>
                ForgotNewPasswordScreen(args: state.extra! as ResetArgs),
          ),
          GoRoute(
            path: 'success',
            builder: (_, _) => const ForgotSuccessScreen(),
          ),
        ],
      ),
    ],
  );
}
