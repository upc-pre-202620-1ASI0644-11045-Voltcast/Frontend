import 'dart:convert';

import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/network/api_exception.dart';
import 'package:actualvoltcast/core/network/backend_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/memory_tokens.dart';

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('login error from the backend becomes a Spanish ApiException', () async {
    final api = ApiClient(
      tokenStorage: MemoryTokens(),
      httpClient: MockClient((_) async => _json(401, {'detail': 'Invalid credentials'})),
    );

    await expectLater(
      api.post('/auth/login', body: {'email': 'a@b.co', 'password': 'x'}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.message, 'message', 'Correo o contraseña incorrectos.')
            .having((e) => e.statusCode, 'status', 401),
      ),
    );
  });

  test('validation errors (422) show the first message', () async {
    final api = ApiClient(
      tokenStorage: MemoryTokens(),
      httpClient: MockClient((_) async => _json(422, {
            'detail': [
              {'loc': ['body', 'email'], 'msg': 'value is not a valid email address'},
            ],
          })),
    );

    await expectLater(
      api.post('/auth/register', body: {}),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('email'))),
    );
  });

  test('5xx hides backend internals', () async {
    final api = ApiClient(
      tokenStorage: MemoryTokens(),
      httpClient: MockClient((_) async => _json(500, {'detail': 'Internal error: boom'})),
    );

    await expectLater(
      api.get('/auth/me'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', isNot(contains('boom')))),
    );
  });

  test('connection failures give a friendly message', () async {
    final api = ApiClient(
      tokenStorage: MemoryTokens(),
      httpClient: MockClient((_) async => throw http.ClientException('refused')),
    );

    await expectLater(
      api.get('/auth/me'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', isNull)),
    );
  });

  test('a 401 on an authenticated call refreshes the token and retries once', () async {
    final tokens = MemoryTokens(access: 'old', refresh: 'refresh-1');
    final seenAuth = <String?>[];

    final api = ApiClient(
      tokenStorage: tokens,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return _json(200, {'access_token': 'new', 'token_type': 'Bearer'});
        }
        seenAuth.add(request.headers['Authorization']);
        return request.headers['Authorization'] == 'Bearer new'
            ? _json(200, {'id': 1})
            : _json(401, {'detail': 'Not authenticated'});
      }),
    );

    final result = await api.get('/auth/me', auth: true);

    expect(result, {'id': 1});
    expect(seenAuth, ['Bearer old', 'Bearer new']);
    expect(await tokens.accessToken, 'new');
  });

  test('a rejected refresh clears tokens and signals session expiry', () async {
    final tokens = MemoryTokens(access: 'old', refresh: 'dead');
    var expired = false;

    final api = ApiClient(
      tokenStorage: tokens,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return _json(401, {'detail': 'Invalid or expired refresh token'});
        }
        return _json(401, {'detail': 'Not authenticated'});
      }),
    )..onSessionExpired = () => expired = true;

    await expectLater(api.get('/auth/me', auth: true), throwsA(isA<ApiException>()));
    expect(expired, isTrue);
    expect(await tokens.accessToken, isNull);
  });

  group('translateBackendMessage: the file could not be read (US002, US003)', () {
    test('columns that cannot be identified ask to check the structure', () {
      final date = translateBackendMessage(
        "Could not identify the date column 'Fecha' in sheet 'EL A'. Check the structure of the file",
      );
      final cols = translateBackendMessage(
        "Could not identify the columns ['Volts'] in sheet 'EL A' (total voltage / current). Check the structure of the file",
      );
      expect(date, contains('No se pudo identificar la columna de fechas'));
      expect(cols, contains('No se pudieron identificar las columnas'));
      expect(date, contains('Verifica la estructura del archivo'));
      expect(cols, contains('Verifica la estructura del archivo'));
    });

    test('a file without electrical cells says none were found', () {
      expect(
        translateBackendMessage(
          "No electrical cells were found in sheet 'EL A': cell columns are named with their number (1, 2, 3...)",
        ),
        contains('No se encontraron celdas eléctricas'),
      );
      expect(
        translateBackendMessage(
          "No sheet identifies an electrical section (for example 'EL A' or 'Sección A'). Sheets found: ['Hoja1']",
        ),
        contains('No se encontraron celdas eléctricas'),
      );
    });
  });

  group('translateBackendMessage', () {
    test('known and pattern messages', () {
      expect(translateBackendMessage('Your account request is pending approval'),
          contains('pendiente'));
      expect(translateBackendMessage("Email 'a@b.co' is already registered"),
          contains('ya está registrado'));
      expect(translateBackendMessage('Too many requests. Try again in 90 seconds.'),
          contains('2 minutos'));
      expect(translateBackendMessage('Too many requests. Try again in 20 seconds.'),
          contains('20 segundos'));
    });

    test('unknown messages pass through', () {
      expect(translateBackendMessage('Algo raro'), 'Algo raro');
    });
  });
}
