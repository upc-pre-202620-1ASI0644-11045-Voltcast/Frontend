import 'dart:convert';

import 'package:actualvoltcast/core/format.dart';
import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/integrations/data/drive_repository.dart';
import 'package:actualvoltcast/features/integrations/presentation/drive_controller.dart';
import 'package:actualvoltcast/features/integrations/presentation/drive_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_tokens.dart';

const _syncedAt = '2026-11-10T14:32:00Z';
const _connectedAt = '2026-11-01T09:00:00Z';

/// Stand-in for `/integrations/drive`.
class _FakeDrive {
  _FakeDrive() {
    client = MockClient(_handle);
  }

  late final MockClient client;
  final requests = <http.Request>[];
  Map<String, dynamic> status = notConnected;
  int? connectStatus;
  bool offline = false;

  static const notConnected = {
    'connected': false,
    'account': null,
    'lastSyncAt': null,
    'error': null,
    'connectedAt': null,
  };

  static Map<String, dynamic> connected({String? error, String? lastSyncAt}) => {
    'connected': true,
    'account': 'voltcast@empresa.com',
    'lastSyncAt': lastSyncAt,
    'error': error,
    'connectedAt': _connectedAt,
  };

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('no network');
    requests.add(request);
    final path = request.url.path.replaceFirst('/api/v1/integrations/drive', '');
    http.Response json(int code, Object body) => http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    switch ((request.method, path)) {
      case ('GET', '/status'):
        return json(200, status);
      case ('GET', '/connect'):
        final code = connectStatus;
        return code != null
            ? json(code, {'detail': 'Forbidden'})
            : json(200, {'authorizationUrl': 'https://accounts.google.com/o/x'});
      case ('DELETE', ''):
        status = notConnected;
        return http.Response('', 204);
    }
    return json(404, {'detail': 'Not found'});
  }

  int count(String method, String path) => requests
      .where((r) => r.method == method && r.url.path.endsWith(path))
      .length;
}

Future<List<Uri>> _pump(
  WidgetTester tester,
  _FakeDrive backend, {
  bool canManage = true,
  MemoryDriveStatusStore? store,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final opened = <Uri>[];
  final repository = DriveRepository(
    ApiClient(tokenStorage: MemoryTokens(access: 'token'), httpClient: backend.client),
    store: store ?? MemoryDriveStatusStore(),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => DriveController(
        repository,
        open: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: DriveScreen(canManage: canManage),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  final connectButton = find.text('Conectar Google Drive');

  testWidgets('supervisor, not connected: connect opens the browser', (tester) async {
    final backend = _FakeDrive();
    final opened = await _pump(tester, backend);

    expect(find.text('• Desconectado'), findsOneWidget);
    expect(find.text('Cuenta desvinculada'), findsOneWidget);
    expect(find.text('Correo sin vincular'), findsOneWidget);
    expect(find.text('Desconectar'), findsNothing);
    expect(
      find.text('La sincronización es automática, una vez al día.'),
      findsOneWidget,
    );

    await tester.tap(connectButton);
    await tester.pumpAndSettle();

    expect(opened.single.toString(), 'https://accounts.google.com/o/x');
    expect(backend.requests.first.headers['Authorization'], 'Bearer token');

    // Back from the browser: the status is asked again.
    backend.status = _FakeDrive.connected();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(backend.count('GET', '/status'), 2);
    expect(find.text('• Conectado'), findsOneWidget);
  });

  testWidgets('connected: shows the account and dates; disconnect asks first', (tester) async {
    final backend = _FakeDrive()
      ..status = _FakeDrive.connected(lastSyncAt: _syncedAt);
    await _pump(tester, backend);

    expect(find.text('• Conectado'), findsOneWidget);
    expect(find.text('voltcast@empresa.com'), findsOneWidget);
    expect(find.text(formatShortDate(parseApiDateTime(_syncedAt))), findsOneWidget);
    expect(find.text(formatTime(parseApiDateTime(_syncedAt))), findsOneWidget);
    expect(find.text(formatShortDate(parseApiDateTime(_connectedAt))), findsOneWidget);
    expect(connectButton, findsNothing);

    await tester.tap(find.text('Desconectar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('datasets ya creados se conservan'), findsOneWidget);

    // Cancel: nothing is sent.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(backend.count('DELETE', '/drive'), 0);

    await tester.tap(find.text('Desconectar'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Desconectar')));
    await tester.pumpAndSettle();

    expect(backend.count('DELETE', '/drive'), 1);
    expect(find.text('• Desconectado'), findsOneWidget);
    expect(connectButton, findsOneWidget);
  });

  testWidgets('connected but never synced', (tester) async {
    await _pump(tester, _FakeDrive()..status = _FakeDrive.connected());
    expect(find.text('Aún no se ha sincronizado'), findsOneWidget);
  });

  testWidgets('invalid_grant: banner with the connect button', (tester) async {
    final backend = _FakeDrive()
      ..status = {..._FakeDrive.notConnected, 'error': 'invalid_grant'};
    final opened = await _pump(tester, backend);

    expect(find.text('Google revocó el acceso. Vuelve a conectar Drive.'), findsOneWidget);
    expect(connectButton, findsOneWidget);

    await tester.tap(connectButton);
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
  });

  testWidgets('sync_failed: banner without any action', (tester) async {
    await _pump(
      tester,
      _FakeDrive()..status = _FakeDrive.connected(error: 'sync_failed', lastSyncAt: _syncedAt),
    );

    expect(
      find.text('La última sincronización falló; se reintentará en la próxima ejecución diaria.'),
      findsOneWidget,
    );
    expect(connectButton, findsNothing);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('no error: no banner', (tester) async {
    await _pump(tester, _FakeDrive()..status = _FakeDrive.connected(lastSyncAt: _syncedAt));
    expect(find.textContaining('revocó'), findsNothing);
    expect(find.textContaining('falló'), findsNothing);
  });

  testWidgets('engineer: read only, even with invalid_grant', (tester) async {
    final backend = _FakeDrive()
      ..status = {..._FakeDrive.connected(lastSyncAt: _syncedAt), 'error': 'invalid_grant'};
    await _pump(tester, backend, canManage: false);

    expect(find.text('voltcast@empresa.com'), findsOneWidget);
    expect(find.text('Google revocó el acceso. Vuelve a conectar Drive.'), findsOneWidget);
    expect(connectButton, findsNothing);
    expect(find.text('Desconectar'), findsNothing);
  });

  testWidgets('connect refused with 403 shows the permissions message', (tester) async {
    final backend = _FakeDrive()..connectStatus = 403;
    final opened = await _pump(tester, backend);

    await tester.tap(connectButton);
    await tester.pumpAndSettle();

    expect(find.text('No tienes permisos para realizar esta acción.'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('connect with Drive not configured (503)', (tester) async {
    final backend = _FakeDrive()..connectStatus = 503;
    await _pump(tester, backend);

    await tester.tap(connectButton);
    await tester.pumpAndSettle();

    expect(find.text(notConfiguredMessage), findsOneWidget);
  });

  testWidgets('offline shows the last saved status and can retry', (tester) async {
    final store = MemoryDriveStatusStore();
    final backend = _FakeDrive()
      ..status = _FakeDrive.connected(lastSyncAt: _syncedAt);
    await _pump(tester, backend, store: store);
    expect(store.value, isNotNull);
    expect(store.value, isNot(contains('token')));

    // Same device, no network: the screen opens again (a fresh controller).
    await tester.pumpWidget(const SizedBox());
    backend.offline = true;
    await _pump(tester, backend, store: store);

    expect(find.text('voltcast@empresa.com'), findsOneWidget);
    expect(find.textContaining('Sin conexión.'), findsOneWidget);

    backend.offline = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin conexión.'), findsNothing);
  });

  testWidgets('offline with nothing saved', (tester) async {
    final backend = _FakeDrive()..offline = true;
    await _pump(tester, backend);

    expect(find.text('Sin conexión.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    backend.offline = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('• Desconectado'), findsOneWidget);
  });
}
