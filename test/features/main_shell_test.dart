import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/auth/data/auth_repository.dart';
import 'package:actualvoltcast/features/auth/data/auth_user.dart';
import 'package:actualvoltcast/features/auth/presentation/auth_controller.dart';
import 'package:actualvoltcast/features/home/main_shell.dart';
import 'package:actualvoltcast/features/users/data/users_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_users_backend.dart';
import '../helpers/memory_tokens.dart';

/// A signed-in session without going through the login flow.
class _SignedIn extends AuthController {
  _SignedIn(this._user, ApiClient api)
    : super(
        AuthRepository(
          api: api,
          tokens: MemoryTokens(access: 'token'),
        ),
      );

  final AuthUser _user;

  @override
  AuthUser? get user => _user;
}

Future<FakeUsersBackend> _pump(WidgetTester tester, {required String? role}) async {
  final backend = FakeUsersBackend();
  final api = ApiClient(
    tokenStorage: MemoryTokens(access: 'token'),
    httpClient: backend.client,
  );
  final user = AuthUser(id: 1, email: 'o@voltcast.io', fullName: 'Oscar Aranda', status: 'active', role: role);

  final router = GoRouter(
    initialLocation: '/line',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(shell: shell),
        branches: [
          for (final path in ['/line', '/storage', '/users'])
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  builder: (_, _) => Center(child: Text('screen $path')),
                ),
              ],
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>(create: (_) => _SignedIn(user, api)),
        Provider<UsersRepository>.value(value: UsersRepository(api)),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  testWidgets('the app opens on Inicio, the production line', (tester) async {
    await _pump(tester, role: 'USER');

    expect(find.text('screen /line'), findsOneWidget);
    expect(find.text('Inicio'), findsOneWidget); // the current tab spells its name
    expect(find.text('Inventario'), findsNothing); // the others are icons
  });

  testWidgets('an engineer gets Inicio and Inventario, but not Usuarios', (tester) async {
    await _pump(tester, role: 'USER');

    expect(find.byTooltip('Inventario'), findsOneWidget);
    expect(find.byTooltip(RegExp('^Usuarios')), findsNothing);

    await tester.tap(find.byTooltip('Inventario'));
    await tester.pumpAndSettle();
    expect(find.text('screen /storage'), findsOneWidget);
    expect(find.text('Inventario'), findsOneWidget);

    await tester.tap(find.byTooltip('Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('screen /line'), findsOneWidget);
  });

  testWidgets('a supervisor also gets Usuarios, with the pending requests counted', (tester) async {
    final backend = await _pump(tester, role: 'ADMIN');

    expect(find.byTooltip('Usuarios: 2 solicitudes pendientes'), findsOneWidget);
    expect(find.text('2'), findsWidgets); // Mariana Torres and Diego Salcedo

    await tester.tap(find.byTooltip('Usuarios: 2 solicitudes pendientes'));
    await tester.pumpAndSettle();
    expect(find.text('screen /users'), findsOneWidget);

    // A request handled in the Usuarios tab is reflected when leaving it.
    backend.users.firstWhere((u) => u['id'] == 4)['status'] = 'active';
    await tester.tap(find.byTooltip('Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsWidgets);
    expect(find.byTooltip('Usuarios: 1 solicitud pendiente'), findsOneWidget);
  });
}
