import 'dart:convert';

import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/auth/data/auth_repository.dart';
import 'package:actualvoltcast/features/auth/presentation/auth_controller.dart';
import 'package:actualvoltcast/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_tokens.dart';

Future<AuthController> _pumpLogin(WidgetTester tester, MockClient client) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final tokens = MemoryTokens();
  final api = ApiClient(tokenStorage: tokens, httpClient: client);
  final auth = AuthController(AuthRepository(api: api, tokens: tokens));

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthController>.value(
      value: auth,
      child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
    ),
  );
  return auth;
}

void main() {
  testWidgets('submitting an empty form shows what is missing and does not call the API', (tester) async {
    var calls = 0;
    await _pumpLogin(tester, MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }));

    // The button is always enabled: pressing it on an empty form explains why it cannot go on.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Campo obligatorio: ingresa tu correo electrónico.'), findsOneWidget);
    expect(find.text('Campo obligatorio: ingresa tu contraseña.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('invalid credentials show the translated error banner', (tester) async {
    await _pumpLogin(
      tester,
      MockClient((_) async => http.Response(
            jsonEncode({'detail': 'Invalid credentials'}),
            401,
            headers: {'content-type': 'application/json'},
          )),
    );

    await tester.enterText(find.byType(TextFormField).first, 'jperez@empresa.com');
    await tester.enterText(find.byType(TextFormField).last, 'wrong');
    await tester.pump();
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
  });

  testWidgets('a malformed email is rejected before calling the API', (tester) async {
    var calls = 0;
    await _pumpLogin(tester, MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }));

    await tester.enterText(find.byType(TextFormField).first, 'no-es-un-correo');
    await tester.enterText(find.byType(TextFormField).last, 'algo');
    await tester.pump();
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Valor no válido: ingresa un correo válido.'), findsOneWidget);
    expect(calls, 0);
  });
}
