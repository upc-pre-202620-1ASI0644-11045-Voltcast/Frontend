import 'dart:convert';

import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/auth/data/auth_repository.dart';
import 'package:actualvoltcast/features/auth/presentation/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_tokens.dart';

Future<List<http.Request>> _pump(WidgetTester tester, {int status = 201, String? detail}) async {
  tester.view.physicalSize = const Size(420, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final requests = <http.Request>[];
  final tokens = MemoryTokens();
  final api = ApiClient(
    tokenStorage: tokens,
    httpClient: MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(detail == null ? {'id': 9, 'status': 'pending'} : {'detail': detail}),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const RegisterScreen()),
    GoRoute(path: '/login', builder: (_, _) => const Scaffold(body: Text('pantalla de login'))),
  ]);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    Provider<AuthRepository>.value(
      value: AuthRepository(api: api, tokens: tokens),
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return requests;
}

Future<void> _fill(WidgetTester tester, {String name = 'María García', String email = 'maria@empresa.com'}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), email);
  await tester.enterText(fields.at(2), 'SecurePass123!');
  await tester.enterText(fields.at(3), 'SecurePass123!');
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  final button = find.text('Solicitar cuenta').last;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('there are no Terms or Privacy Policy to accept', (tester) async {
    await _pump(tester);

    expect(find.textContaining('Términos'), findsNothing);
    expect(find.textContaining('Política de privacidad'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('US023 E02: an empty form is rejected, naming every missing field', (tester) async {
    final requests = await _pump(tester);

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    await _submit(tester);

    expect(find.text('Campo obligatorio: ingresa tu nombre completo.'), findsOneWidget);
    expect(find.text('Campo obligatorio: ingresa tu correo electrónico.'), findsOneWidget);
    expect(find.text('Campo obligatorio: crea una contraseña.'), findsOneWidget);
    expect(find.text('Campo obligatorio: repite tu contraseña.'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('US023 E02: a partially filled form still names what is missing', (tester) async {
    final requests = await _pump(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'María García');
    await tester.pump();
    await _submit(tester);

    expect(find.text('Campo obligatorio: ingresa tu nombre completo.'), findsNothing);
    expect(find.text('Campo obligatorio: ingresa tu correo electrónico.'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('passwords that do not match are rejected before calling the API', (tester) async {
    final requests = await _pump(tester);
    await _fill(tester);
    await tester.enterText(find.byType(TextFormField).at(3), 'Different123!');
    await tester.pump();

    await _submit(tester);

    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('US023 E01: a complete request is sent and left pending for the supervisor', (tester) async {
    final requests = await _pump(tester);
    await _fill(tester);

    await _submit(tester);

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/v1/auth/register');
    expect(jsonDecode(requests.single.body), {
      'full_name': 'María García',
      'email': 'maria@empresa.com',
      'password': 'SecurePass123!',
    });
    expect(find.textContaining('Solicitud'), findsWidgets);
    expect(find.textContaining('Un supervisor revisará tu solicitud'), findsOneWidget);
  });

  testWidgets('an email that is already registered is reported in Spanish', (tester) async {
    await _pump(tester, status: 400, detail: "Email 'maria@empresa.com' is already registered");
    await _fill(tester);

    await _submit(tester);

    expect(find.textContaining('ya está registrado'), findsOneWidget);
    expect(find.text('Solicitar cuenta'), findsWidgets); // still on the form
  });
}
