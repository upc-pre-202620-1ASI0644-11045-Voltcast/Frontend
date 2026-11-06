import 'dart:convert';

import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/features/auth/data/auth_repository.dart';
import 'package:actualvoltcast/features/auth/presentation/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/memory_tokens.dart';

void main() {
  group('restoring the session', () {
    late bool offline;
    late int answer;
    late MemoryTokens tokens;
    late AuthController auth;

    setUp(() {
      offline = true;
      answer = 200;
      tokens = MemoryTokens(access: 'token');
      final client = MockClient((request) async {
        if (offline) throw http.ClientException('no network');
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'access_token': 'new',
              'refresh_token': 'new',
              'user': _admin,
            }),
            200,
          );
        }
        return http.Response(jsonEncode(_admin), answer);
      });
      auth = AuthController(
        AuthRepository(
          api: ApiClient(tokenStorage: tokens, httpClient: client),
          tokens: tokens,
        ),
        restoreRetryEvery: const Duration(milliseconds: 20),
      );
      addTearDown(auth.dispose);
    });

    Future<void> settle() async {
      for (var i = 0; i < 40 && auth.status != AuthStatus.authenticated; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('opened offline it comes back by itself with the connection', () async {
      await auth.restoreSession();
      expect(auth.status, AuthStatus.unauthenticated);
      expect(await tokens.accessToken, 'token');

      offline = false;
      await settle();

      expect(auth.status, AuthStatus.authenticated);
      expect(auth.user?.id, 1);
    });

    test('while still offline it does not disturb the login screen', () async {
      await auth.restoreSession();
      var notified = 0;
      auth.addListener(() => notified++);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notified, 0);
    });

    test('signing in by hand ends the retries', () async {
      await auth.restoreSession();
      offline = false;

      await auth.login(email: 'a@b.co', password: 'x');
      final user = auth.user;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(auth.status, AuthStatus.authenticated);
      expect(identical(auth.user, user), isTrue);
    });

    test('signing out ends the retries', () async {
      await auth.restoreSession();

      await auth.logout();
      offline = false;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(auth.status, AuthStatus.unauthenticated);
    });

    test('dead tokens are not retried', () async {
      offline = false;
      answer = 401;

      await auth.restoreSession();
      answer = 200;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(auth.status, AuthStatus.unauthenticated);
      expect(await tokens.accessToken, isNull);
    });
  });
}

const _admin = {
  'id': 1,
  'email': 'c.mendoza@voltcast.io',
  'full_name': 'Carlos Mendoza',
  'role': 'ADMIN',
  'status': 'active',
  'created_at': '2026-01-12T10:00:00',
};
