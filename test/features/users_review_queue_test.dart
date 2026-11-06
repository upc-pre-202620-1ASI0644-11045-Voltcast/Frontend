import 'dart:convert';

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
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_users_backend.dart';
import '../helpers/memory_tokens.dart';

UsersRepository _repo(FakeUsersBackend backend) => UsersRepository(
  ApiClient(
    tokenStorage: MemoryTokens(access: 'token'),
    httpClient: backend.client,
  ),
);

Future<(UsersController, FakeUsersBackend, MemoryPendingReviewStore)> _loaded({
  MemoryPendingReviewStore? store,
  FakeUsersBackend? backend,
  Duration retryEvery = const Duration(minutes: 5),
}) async {
  backend ??= FakeUsersBackend();
  store ??= MemoryPendingReviewStore();
  final controller = UsersController(
    _repo(backend),
    store: store,
    retryEvery: retryEvery,
  );
  addTearDown(controller.dispose);
  await controller.load();
  return (controller, backend, store);
}

AuthUser _user(UsersController c, int id) =>
    c.pending.firstWhere((u) => u.id == id);

String? _status(FakeUsersBackend backend, int id) =>
    backend.users.firstWhere((u) => u['id'] == id)['status'] as String?;

Map<String, dynamic> _sent(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

void main() {
  group('without a connection', () {
    test('approving is queued and saved instead of failing', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;

      final outcome = await c.approve(_user(c, 4));

      expect(outcome, ReviewOutcome.queued);
      expect(c.queuedCount, 1);
      expect(c.queuedReview(4)?.approve, isTrue);
      expect(store.reviews.single.userId, 4);
      expect(c.isBusy(4), isFalse);
    });

    test('rejecting is queued too', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;

      expect(await c.reject(_user(c, 4)), ReviewOutcome.queued);

      expect(store.reviews.single.approve, isFalse);
    });

    test('the account stays pending, but no longer awaits a decision', () async {
      final (c, backend, _) = await _loaded();
      backend.offline = true;

      await c.approve(_user(c, 4));

      expect(c.pending.map((u) => u.id), [4, 5]);
      expect(c.awaitingDecision.map((u) => u.id), [5]);
      expect(c.accounts.map((u) => u.id), isNot(contains(4)));
    });

    test('stays queued while there is still no connection', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      await c.syncQueue();

      expect(c.queuedCount, 1);
      expect(store.reviews, hasLength(1));
      expect(c.syncNotice, isNull);
      expect(c.syncIssue, isNull);
    });

    test('a refresh keeps the last list and says it is offline', () async {
      final (c, backend, _) = await _loaded();
      backend.offline = true;

      await c.load();

      expect(c.offline, isTrue);
      expect(c.hasLoaded, isTrue);
      expect(c.pending, hasLength(2));
    });
  });

  group('a real answer from the server is an error, not something to queue', () {
    for (final status in [400, 403, 404, 500]) {
      test('$status', () async {
        final (c, backend, store) = await _loaded();
        backend.failReviewWith = (status: status, detail: 'No');

        await expectLater(c.approve(_user(c, 4)), throwsA(isA<ApiException>()));

        expect(c.queuedCount, 0);
        expect(store.reviews, isEmpty);
        expect(c.pending, hasLength(2));
      });
    }
  });

  group('when the connection is back', () {
    test('sends the exact decision once and reports it', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));
      await c.reject(_user(c, 5));

      backend.offline = false;
      await c.syncQueue();

      expect(backend.reviews, hasLength(2));
      expect(backend.reviews[0].url.path, '/api/v1/users/4/approval');
      expect(_sent(backend.reviews[0]), {'decision': 'approve', 'role': 'USER'});
      expect(backend.reviews[1].url.path, '/api/v1/users/5/approval');
      expect(_sent(backend.reviews[1]), {'decision': 'reject', 'role': 'USER'});
      expect(_status(backend, 4), 'active');
      expect(_status(backend, 5), 'rejected');
      expect(c.queuedCount, 0);
      expect(store.reviews, isEmpty);
      expect(c.pending, isEmpty);
      expect(c.accounts.map((u) => u.id), contains(4));
      expect(c.syncNotice, contains('2 decisiones'));
      expect(c.syncNotice, contains('correo'));
      expect(c.syncNoticeIsProblem, isFalse);
    });

    test('retries by itself while decisions are queued', () async {
      final (c, backend, _) = await _loaded(
        retryEvery: const Duration(milliseconds: 30),
      );
      backend.offline = true;
      await c.approve(_user(c, 4));

      backend.offline = false;
      for (var i = 0; i < 40 && c.queuedCount > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(c.queuedCount, 0);
      expect(_status(backend, 4), 'active');
    });

    test('stops retrying once the queue is empty', () async {
      final (c, backend, _) = await _loaded(
        retryEvery: const Duration(milliseconds: 20),
      );
      backend.offline = true;
      await c.approve(_user(c, 4));
      backend.offline = false;
      await c.syncQueue();

      final seen = backend.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(backend.requests.length, seen);
    });

    test('two syncs at the same time send each decision once', () async {
      final (c, backend, _) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      backend.offline = false;
      await Future.wait([c.syncQueue(), c.syncQueue(), c.syncQueue()]);

      expect(backend.reviews, hasLength(1));
    });

    test('the connection lost halfway: each decision still arrives once', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));
      await c.approve(_user(c, 5));

      backend
        ..offline = false
        ..loseNextReviewReply = true;
      await c.syncQueue();
      expect(store.reviews, hasLength(2));
      expect(backend.reviews, hasLength(1));

      await c.syncQueue();

      expect(store.reviews, isEmpty);
      expect(backend.reviews.where((r) => r.url.path.contains('/4/')), hasLength(1));
      expect(backend.reviews.where((r) => r.url.path.contains('/5/')), hasLength(1));
      expect(c.syncNotice, contains('2 decisiones'));
    });
  });

  group('surviving a restart', () {
    test('what was queued is restored and sent when the app starts', () async {
      final store = MemoryPendingReviewStore([
        const PendingReview(userId: 4, approve: false, fullName: 'Mariana Torres'),
      ]);

      final (c, backend, _) = await _loaded(store: store);

      expect(_status(backend, 4), 'rejected');
      expect(c.queuedCount, 0);
      expect(store.reviews, isEmpty);
    });

    test('still offline at the start it stays queued and retries', () async {
      final store = MemoryPendingReviewStore([
        const PendingReview(userId: 4, approve: true, fullName: 'Mariana Torres'),
      ]);
      final backend = FakeUsersBackend()..offline = true;

      final (c, _, _) = await _loaded(
        store: store,
        backend: backend,
        retryEvery: const Duration(milliseconds: 30),
      );
      expect(c.hasLoaded, isFalse);
      expect(c.queuedCount, 1);

      backend.offline = false;
      for (var i = 0; i < 40 && c.queuedCount > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(_status(backend, 4), 'active');
      expect(c.hasLoaded, isTrue);
      expect(c.pending.map((u) => u.id), [5]);
    });
  });

  group('retries do not repeat an action', () {
    test('a reply lost on the first try is not sent again', () async {
      final (c, backend, _) = await _loaded();
      backend.loseNextReviewReply = true;

      expect(await c.approve(_user(c, 4)), ReviewOutcome.queued);
      expect(_status(backend, 4), 'active');

      await c.syncQueue();

      expect(backend.reviews, hasLength(1));
      expect(c.queuedCount, 0);
      expect(c.syncNotice, contains('1 decisión'));
      expect(c.syncNoticeIsProblem, isFalse);
    });

    test('a reply lost during a sync is not sent again', () async {
      final (c, backend, _) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      backend
        ..offline = false
        ..loseNextReviewReply = true;
      await c.syncQueue();
      expect(c.queuedCount, 1);
      expect(backend.reviews, hasLength(1));

      await c.syncQueue();

      expect(backend.reviews, hasLength(1));
      expect(c.queuedCount, 0);
    });
  });

  group('decisions repeated on the same account', () {
    test('the last one replaces the first, and only that is sent', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      expect(await c.reject(_user(c, 4)), ReviewOutcome.queued);
      expect(await c.approve(_user(c, 4)), ReviewOutcome.queued);
      expect(await c.reject(_user(c, 4)), ReviewOutcome.queued);

      expect(c.queuedCount, 1);
      expect(store.reviews.single.approve, isFalse);

      backend.offline = false;
      await c.syncQueue();

      expect(backend.reviews, hasLength(1));
      expect(_sent(backend.reviews.single)['decision'], 'reject');
    });

    test('a queued decision can be taken back', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      await c.cancelQueued(4);

      expect(c.queuedCount, 0);
      expect(store.reviews, isEmpty);
      expect(c.awaitingDecision.map((u) => u.id), [4, 5]);

      backend.offline = false;
      await c.syncQueue();
      expect(backend.reviews, isEmpty);
    });

    test('while it is being sent it can not be changed or taken back', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      final user = _user(c, 4);
      await c.approve(user);
      backend.offline = false;

      final sync = c.syncQueue();
      await c.cancelQueued(4);
      await expectLater(c.reject(user), throwsA(isA<ApiException>()));
      await sync;

      expect(_status(backend, 4), 'active');
      expect(store.reviews, isEmpty);
    });
  });

  group('the server resolved it or refuses it', () {
    test('the same decision already there counts as done', () async {
      final (c, backend, _) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      backend.offline = false;
      backend.users.firstWhere((u) => u['id'] == 4)['status'] = 'active';
      await c.syncQueue();

      expect(backend.reviews, isEmpty);
      expect(c.queuedCount, 0);
      expect(c.syncNoticeIsProblem, isFalse);
    });

    test('the opposite decision is reported and not sent', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      backend.offline = false;
      backend.users.firstWhere((u) => u['id'] == 4)['status'] = 'rejected';
      await c.syncQueue();

      expect(backend.reviews, isEmpty);
      expect(store.reviews, isEmpty);
      expect(c.syncNotice, contains('Mariana Torres'));
      expect(c.syncNotice, contains('ya fue resuelta'));
      expect(c.syncNoticeIsProblem, isTrue);
    });

    test('an account that is gone is reported and dropped', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      backend.offline = false;
      backend.users.removeWhere((u) => u['id'] == 4);
      await c.syncQueue();

      expect(store.reviews, isEmpty);
      expect(c.syncNotice, contains('ya no existe'));
    });

    test('resolved between the check and the send: reported, the rest goes on', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      backend
        ..offline = false
        ..failReviewWith = (status: 400, detail: 'Only pending requests can be approved');
      await c.syncQueue();

      expect(store.reviews, isEmpty);
      expect(c.syncNotice, contains('Esta solicitud ya fue procesada.'));
      expect(c.syncNoticeIsProblem, isTrue);
    });

    test('one refusal does not stop the next decision', () async {
      final (c, backend, _) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));
      await c.approve(_user(c, 5));

      backend.offline = false;
      backend.users.firstWhere((u) => u['id'] == 4)['status'] = 'rejected';
      await c.syncQueue();

      expect(_status(backend, 5), 'active');
      expect(c.queuedCount, 0);
      expect(c.syncNotice, contains('1 decisión'));
      expect(c.syncNotice, contains('Mariana Torres'));
    });

    test('no longer a supervisor: the queue is reported and dropped', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      backend
        ..offline = false
        ..failWith = (status: 403, detail: 'Forbidden');
      await c.syncQueue();

      expect(store.reviews, isEmpty);
      expect(c.syncNotice, contains('No tienes permisos'));
    });

    test('an expired session keeps the queue for the next sign-in', () async {
      final (c, backend, store) = await _loaded();
      backend.offline = true;
      await c.approve(_user(c, 4));

      backend
        ..offline = false
        ..failWith = (status: 401, detail: 'Not authenticated');
      await c.syncQueue();

      expect(store.reviews, hasLength(1));
      expect(c.queuedCount, 1);
      expect(c.syncIssue, 'Tu sesión expiró. Inicia sesión de nuevo.');
    });

    for (final status in [429, 500, 503]) {
      test('$status is temporary: it stays queued and retries', () async {
        final (c, backend, store) = await _loaded();
        backend.offline = true;
        await c.approve(_user(c, 4));

        backend
          ..offline = false
          ..failReviewWith = (status: status, detail: 'Later');
        await c.syncQueue();

        expect(store.reviews, hasLength(1));
        expect(c.syncIssue, isNotNull);

        backend.failReviewWith = null;
        await c.syncQueue();

        expect(store.reviews, isEmpty);
        expect(c.syncIssue, isNull);
        expect(_status(backend, 4), 'active');
      });
    }

    test('a sync that ends after the session does not break', () async {
      final backend = FakeUsersBackend();
      final store = MemoryPendingReviewStore();
      final c = UsersController(_repo(backend), store: store);
      await c.load();
      backend.offline = true;
      await c.approve(_user(c, 4));
      await c.approve(_user(c, 5));
      backend.offline = false;

      final sync = c.syncQueue();
      c.dispose();
      await sync;

      // Nothing went out with the closed session, and nothing was lost.
      expect(backend.reviews, isEmpty);
      expect(store.reviews, hasLength(2));
    });
  });

  group('PrefsPendingReviewStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    const review = PendingReview(userId: 4, approve: true, fullName: 'Mariana Torres');

    test('keeps the decisions across instances', () async {
      await PrefsPendingReviewStore(1).write([review]);

      final read = await PrefsPendingReviewStore(1).read();

      expect(read.single.userId, 4);
      expect(read.single.approve, isTrue);
      expect(read.single.fullName, 'Mariana Torres');
    });

    test('each supervisor has their own queue', () async {
      await PrefsPendingReviewStore(1).write([review]);

      expect(await PrefsPendingReviewStore(2).read(), isEmpty);
    });

    test('emptying it removes the entry', () async {
      await PrefsPendingReviewStore(1).write([review]);
      await PrefsPendingReviewStore(1).write([]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('a corrupted entry starts clean instead of breaking', () async {
      SharedPreferences.setMockInitialValues({
        'pending_account_reviews_1': 'not json',
      });

      expect(await PrefsPendingReviewStore(1).read(), isEmpty);
    });
  });

  group('UsersScreen', () {
    Future<(FakeUsersBackend, MemoryPendingReviewStore)> pump(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final backend = FakeUsersBackend();
      final store = MemoryPendingReviewStore();
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => UsersController(
            _repo(backend),
            store: store,
            retryEvery: const Duration(hours: 1),
          )..load(),
          child: MaterialApp(theme: AppTheme.light(), home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return (backend, store);
    }

    testWidgets('E02: offline, approving shows it waiting and says what happens next', (
      tester,
    ) async {
      final (backend, store) = await pump(tester);
      backend.offline = true;

      await tester.tap(find.text('Aprobar').first);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('se enviará al reconectar'), findsOneWidget);
      expect(find.text('Aprobación por sincronizar'), findsOneWidget);
      expect(find.textContaining('1 decisión pendiente de sincronizar'), findsOneWidget);
      expect(find.text('1 pendiente'), findsOneWidget);
      // The decided card has no buttons left to decide again; Diego's does.
      expect(find.text('Aprobar'), findsOneWidget);
      expect(find.textContaining('No se pudo conectar'), findsNothing);
      expect(store.reviews.single.userId, 4);
    });

    testWidgets('E02: offline, rejecting confirms first and then waits', (tester) async {
      final (backend, store) = await pump(tester);
      backend.offline = true;

      await tester.tap(find.text('Rechazar').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Rechazar')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rechazo por sincronizar'), findsOneWidget);
      expect(find.textContaining('El rechazo de Mariana Torres quedó guardado'), findsOneWidget);
      expect(store.reviews.single.approve, isFalse);
    });

    testWidgets('E02: back online, the banner retries and the account moves on', (
      tester,
    ) async {
      final (backend, _) = await pump(tester);
      backend.offline = true;
      await tester.tap(find.text('Aprobar').first);
      await tester.pumpAndSettle();

      backend.offline = false;
      await tester.tap(find.text('Reintentar ahora'));
      await tester.pumpAndSettle();

      expect(_status(backend, 4), 'active');
      expect(find.text('Aprobación por sincronizar'), findsNothing);
      expect(find.text('1 pendiente'), findsOneWidget);
      expect(find.text('4 usuarios'), findsOneWidget);
      expect(find.textContaining('notificará por correo'), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('notificará por correo'), findsNothing);
    });

    testWidgets('undoing brings the buttons back', (tester) async {
      final (backend, store) = await pump(tester);
      backend.offline = true;
      await tester.tap(find.text('Aprobar').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();

      expect(find.text('Aprobar'), findsNWidgets(2));
      expect(find.text('2 pendientes'), findsOneWidget);
      expect(store.reviews, isEmpty);
    });

    testWidgets('a server error is shown as an error and nothing waits', (tester) async {
      final (backend, store) = await pump(tester);
      backend.failReviewWith = (status: 500, detail: 'Internal error: boom');

      await tester.tap(find.text('Aprobar').first);
      await tester.pumpAndSettle();

      expect(find.text('Error del servidor. Inténtalo más tarde.'), findsOneWidget);
      expect(find.text('Aprobación por sincronizar'), findsNothing);
      expect(store.reviews, isEmpty);
    });

    testWidgets('a refresh without a connection keeps the list and explains', (tester) async {
      final (backend, _) = await pump(tester);
      backend.offline = true;

      await tester.element(find.byType(UsersScreen)).read<UsersController>().load();
      await tester.pumpAndSettle();

      expect(find.text('Mariana Torres'), findsOneWidget);
      expect(find.textContaining('No se pudo actualizar: sin conexión'), findsOneWidget);
      expect(find.textContaining('No se pudo conectar'), findsNothing);
    });

    testWidgets('a refused decision is told after the sync', (tester) async {
      final (backend, _) = await pump(tester);
      backend.offline = true;
      await tester.tap(find.text('Aprobar').first);
      await tester.pumpAndSettle();

      backend.offline = false;
      backend.users.firstWhere((u) => u['id'] == 4)['status'] = 'rejected';
      await tester.tap(find.text('Reintentar ahora'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ya fue resuelta en el servidor'), findsOneWidget);
    });
  });
}
