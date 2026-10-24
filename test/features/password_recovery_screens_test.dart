import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/auth/data/auth_repository.dart';
import 'package:actualvoltcast/features/auth/presentation/screens/forgot_code_screen.dart';
import 'package:actualvoltcast/features/auth/presentation/screens/forgot_new_password_screen.dart';
import 'package:actualvoltcast/features/auth/presentation/screens/forgot_success_screen.dart';
import 'package:actualvoltcast/features/auth/presentation/screens/reset_args.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_tokens.dart';

Future<void> _pump(WidgetTester tester, Widget screen, {List<http.Request>? sink}) async {
  // Small phone: the worst case for overflow.
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final tokens = MemoryTokens();
  final api = ApiClient(
    tokenStorage: tokens,
    httpClient: MockClient((request) async {
      sink?.add(request);
      return http.Response('{"message":"ok"}', 200, headers: {'content-type': 'application/json'});
    }),
  );

  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => screen),
    GoRoute(path: '/forgot/success', builder: (_, _) => const ForgotSuccessScreen()),
    GoRoute(path: '/login', builder: (_, _) => const Scaffold(body: Text('login'))),
  ]);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    Provider<AuthRepository>.value(
      value: AuthRepository(api: api, tokens: tokens),
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
}

void main() {
  testWidgets('code screen: verify enables at 6 digits; resend is in cooldown', (tester) async {
    await _pump(tester, const ForgotCodeScreen(email: 'jperez@empresa.com'));

    expect(find.text('jperez@empresa.com'), findsNothing); // inside a RichText span
    expect(find.textContaining('Reenviar código en'), findsOneWidget);

    FilledButton verify() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(verify().onPressed, isNull);

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.pump();
    expect(verify().onPressed, isNotNull);

    // Let the 30s cooldown run out so no timer is pending at teardown.
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Reenviar código'), findsOneWidget);
  });

  testWidgets('code field ignores non-digits and caps at 6', (tester) async {
    await _pump(tester, const ForgotCodeScreen(email: 'a@b.co'));

    await tester.enterText(find.byType(TextFormField), '12ab34567');
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '123456');
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('new password: button needs a policy-compliant, matching password', (tester) async {
    await _pump(
      tester,
      const ForgotNewPasswordScreen(args: ResetArgs(email: 'a@b.co', code: '123456')),
    );

    FilledButton save() => tester.widget<FilledButton>(find.byType(FilledButton));
    final fields = find.byType(TextFormField);
    expect(save().onPressed, isNull);

    await tester.enterText(fields.first, 'weak');
    await tester.enterText(fields.last, 'weak');
    await tester.pump();
    expect(save().onPressed, isNull);

    await tester.enterText(fields.first, 'SecurePass123!');
    await tester.enterText(fields.last, 'Different123!');
    await tester.pump();
    expect(save().onPressed, isNull);

    await tester.enterText(fields.last, 'SecurePass123!');
    await tester.pump();
    expect(save().onPressed, isNotNull);
  });

  testWidgets('new password sends email, code and password in one request', (tester) async {
    final requests = <http.Request>[];
    await _pump(
      tester,
      const ForgotNewPasswordScreen(args: ResetArgs(email: 'a@b.co', code: '123456')),
      sink: requests,
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'SecurePass123!');
    await tester.enterText(fields.last, 'SecurePass123!');
    await tester.pump();
    await tester.ensureVisible(find.text('Cambiar contraseña'));
    await tester.pump();
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pump();

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/v1/auth/password-reset/confirm');
    expect(requests.single.body,
        '{"email":"a@b.co","code":"123456","new_password":"SecurePass123!"}');

    await tester.pumpAndSettle();
    expect(find.text('¡Contraseña\nactualizada!'), findsOneWidget);
  });

  testWidgets('success screen renders without overflow', (tester) async {
    await _pump(tester, const ForgotSuccessScreen());
    expect(find.text('¡Contraseña\nactualizada!'), findsOneWidget);
  });
}
