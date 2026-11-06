import 'dart:convert';

import 'package:actualvoltcast/core/format.dart';
import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/network/api_exception.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/auth/data/auth_user.dart';
import 'package:actualvoltcast/features/users/data/pending_review.dart';
import 'package:actualvoltcast/features/users/data/users_repository.dart';
import 'package:actualvoltcast/features/users/presentation/users_controller.dart';
import 'package:actualvoltcast/features/users/presentation/users_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_users_backend.dart';
import '../helpers/memory_tokens.dart';

UsersRepository _repo(FakeUsersBackend backend) => UsersRepository(
      ApiClient(tokenStorage: MemoryTokens(access: 'token'), httpClient: backend.client),
    );

UsersController _controller(FakeUsersBackend backend) =>
    UsersController(_repo(backend), store: MemoryPendingReviewStore());

/// The screen under the controller the session provides in the app.
Widget _app(FakeUsersBackend backend) => ChangeNotifierProvider(
      create: (_) => _controller(backend)..load(),
      child: MaterialApp(theme: AppTheme.light(), home: const UsersScreen()),
    );

Future<FakeUsersBackend> _pumpScreen(WidgetTester tester) async {
  // Tall phone so every card is built and tappable without scrolling.
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final backend = FakeUsersBackend();
  await tester.pumpWidget(_app(backend));
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  group('model and formatting', () {
    test('initials', () {
      AuthUser u(String name) => AuthUser(id: 1, email: 'a@b.co', fullName: name, status: 'active');
      expect(u('Mariana Torres').initials, 'MT');
      expect(u('  carlos   andrés mendoza ').initials, 'CA');
      expect(u('Madonna').initials, 'M');
    });

    test('supervisors are not manageable', () {
      const admin = AuthUser(id: 1, email: 'a@b.co', fullName: 'A', status: 'active', role: 'ADMIN');
      const engineer = AuthUser(id: 2, email: 'b@b.co', fullName: 'B', status: 'active', role: 'USER');
      expect(admin.isManageable, isFalse);
      expect(engineer.isManageable, isTrue);
    });

    test('formatShortDate', () {
      expect(formatShortDate(DateTime(2026, 1, 12)), '12 ene 2026');
      expect(formatShortDate(DateTime(2026, 12, 3)), '03 dic 2026');
    });
  });

  group('UsersRepository', () {
    test('sends the exact payloads the backend expects', () async {
      final backend = FakeUsersBackend();
      final repo = _repo(backend);

      await repo.review(4, approve: true);
      await repo.review(5, approve: false);
      await repo.setEnabled(2, enabled: false);
      await repo.update(2, fullName: '  Ana R. ', email: 'ANA@Voltcast.io ');
      await repo.list(status: 'pending');

      final sent = backend.requests;
      expect(sent[0].method, 'PATCH');
      expect(sent[0].url.path, '/api/v1/users/4/approval');
      expect(jsonDecode(sent[0].body), {'decision': 'approve', 'role': 'USER'});
      expect(jsonDecode(sent[1].body), {'decision': 'reject', 'role': 'USER'});
      expect(sent[2].url.path, '/api/v1/users/2/status');
      expect(jsonDecode(sent[2].body), {'status': 'disabled'});
      expect(sent[3].method, 'PUT');
      expect(jsonDecode(sent[3].body), {'full_name': 'Ana R.', 'email': 'ana@voltcast.io'});
      expect(sent[4].url.toString(), endsWith('/api/v1/users?status=pending'));
      expect(sent.every((r) => r.headers['Authorization'] == 'Bearer token'), isTrue);
    });
  });

  group('UsersController', () {
    test('splits pending requests from accounts and hides rejected ones', () async {
      final controller = _controller(FakeUsersBackend());
      await controller.load();

      expect(controller.pending.map((u) => u.id), [4, 5]);
      expect(controller.accounts.map((u) => u.id), [1, 2, 3]);
    });

    test('approving moves a request into accounts', () async {
      final controller = _controller(FakeUsersBackend());
      await controller.load();

      await controller.approve(controller.pending.first);

      expect(controller.pending.map((u) => u.id), [5]);
      expect(controller.accounts.map((u) => u.id), contains(4));
      expect(controller.isBusy(4), isFalse);
    });

    test('a failed action rethrows, clears busy and keeps the list', () async {
      final backend = FakeUsersBackend();
      final controller = _controller(backend);
      await controller.load();

      backend.failWith = (status: 400, detail: 'Only pending requests can be approved');
      await expectLater(
        controller.approve(controller.pending.first),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Esta solicitud ya fue procesada.')),
      );
      expect(controller.pending, hasLength(2));
      expect(controller.isBusy(4), isFalse);
    });

    test('load failure is exposed and does not throw', () async {
      final backend = FakeUsersBackend()..failWith = (status: 403, detail: 'Forbidden');
      final controller = _controller(backend);

      await controller.load();

      expect(controller.hasLoaded, isFalse);
      expect(controller.loadError, 'No tienes permisos para realizar esta acción.');
    });
  });

  group('UsersScreen', () {
    testWidgets('shows pending requests and accounts with counts', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('2 pendientes'), findsOneWidget);
      expect(find.text('3 usuarios'), findsOneWidget);
      expect(find.text('Mariana Torres'), findsOneWidget);
      expect(find.text('Sofía Vargas'), findsOneWidget);
      expect(find.text('Rechazado Uno'), findsNothing);
      expect(find.text('Inactivo'), findsOneWidget);
      expect(find.text('Supervisor'), findsOneWidget);
      expect(find.text('Desde 12 ene 2026'), findsNWidgets(3));
    });

    testWidgets('approve updates the lists and confirms', (tester) async {
      final backend = await _pumpScreen(tester);

      await tester.tap(find.text('Aprobar').first);
      await tester.pumpAndSettle();

      expect(find.text('1 pendiente'), findsOneWidget);
      expect(find.text('4 usuarios'), findsOneWidget);
      expect(find.textContaining('ya puede iniciar sesión'), findsOneWidget);
      expect(backend.users.firstWhere((u) => u['id'] == 4)['status'], 'active');
    });

    testWidgets('reject asks for confirmation first', (tester) async {
      final backend = await _pumpScreen(tester);

      await tester.tap(find.text('Rechazar').first);
      await tester.pumpAndSettle();
      expect(find.text('¿Rechazar solicitud?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(backend.users.firstWhere((u) => u['id'] == 4)['status'], 'pending');

      await tester.tap(find.text('Rechazar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Rechazar')));
      await tester.pumpAndSettle();

      expect(find.text('1 pendiente'), findsOneWidget);
      expect(backend.users.firstWhere((u) => u['id'] == 4)['status'], 'rejected');
    });

    testWidgets('disable confirms; enable does not', (tester) async {
      final backend = await _pumpScreen(tester);

      // Index 0 is the Supervisor's (locked) button; Ana Ríos (active) is 1.
      await tester.tap(find.byTooltip('Deshabilitar').at(1));
      await tester.pumpAndSettle();
      expect(find.text('¿Deshabilitar cuenta?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Deshabilitar')));
      await tester.pumpAndSettle();
      expect(backend.users.firstWhere((u) => u['id'] == 2)['status'], 'disabled');

      // Sofía Vargas (disabled) -> enable straight away. Ana, just disabled,
      // is now first in the list of "Habilitar" buttons.
      await tester.tap(find.byTooltip('Habilitar').at(1));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(backend.users.firstWhere((u) => u['id'] == 3)['status'], 'active');
    });

    testWidgets('supervisor accounts cannot be edited or disabled', (tester) async {
      await _pumpScreen(tester);

      IconButton button(IconData icon, int index) =>
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon).at(index));

      // Cards are in list order: Carlos (Supervisor), Ana, Sofía.
      expect(button(Icons.edit_outlined, 0).onPressed, isNull);
      expect(button(Icons.visibility_off_outlined, 0).onPressed, isNull);
      expect(button(Icons.edit_outlined, 1).onPressed, isNotNull);
      expect(button(Icons.visibility_off_outlined, 1).onPressed, isNotNull);
    });

    testWidgets('edit saves trimmed values and shows them', (tester) async {
      final backend = await _pumpScreen(tester);

      await tester.tap(find.byTooltip('Editar').at(1)); // Ana Ríos
      await tester.pumpAndSettle();
      expect(find.text('Editar usuario'), findsOneWidget);

      final save = find.widgetWithText(FilledButton, 'Guardar cambios');
      expect(tester.widget<FilledButton>(save).onPressed, isNull); // nothing changed yet

      await tester.enterText(find.widgetWithText(TextFormField, 'Ana Ríos'), 'Ana Ríos Paz');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text('Editar usuario'), findsNothing);
      expect(find.text('Ana Ríos Paz'), findsOneWidget);
      expect(backend.users.firstWhere((u) => u['id'] == 2)['full_name'], 'Ana Ríos Paz');
    });

    testWidgets('edit shows backend errors inside the sheet', (tester) async {
      final backend = await _pumpScreen(tester);

      await tester.tap(find.byTooltip('Editar').at(1));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'a.rios@voltcast.io'), 'otro@voltcast.io');
      await tester.pump();

      backend.failWith = (status: 400, detail: "Email 'otro@voltcast.io' is already registered");
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar cambios'));
      await tester.pumpAndSettle();

      expect(find.text('Editar usuario'), findsOneWidget);
      expect(find.textContaining('ya está registrado'), findsOneWidget);
    });

    testWidgets('load failure offers a retry that recovers', (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final backend = FakeUsersBackend()..failWith = (status: 500, detail: 'Internal error: boom');
      await tester.pumpWidget(_app(backend));
      await tester.pumpAndSettle();

      expect(find.text('Error del servidor. Inténtalo más tarde.'), findsOneWidget);

      backend.failWith = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Mariana Torres'), findsOneWidget);
    });
  });
}
