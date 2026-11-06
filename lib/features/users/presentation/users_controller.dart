import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/data/auth_user.dart';
import '../data/pending_review.dart';
import '../data/users_repository.dart';

/// How a decision ended: confirmed by the server, or saved on the device while
/// offline and waiting to be sent.
enum ReviewOutcome { applied, queued }

/// The server answered and will not take this decision, now or later. A 401 is
/// not one (the session can come back) nor are 408, 429 and 5xx (temporary).
bool _isRefusal(ApiException e) {
  final status = e.statusCode;
  return status != null &&
      status >= 400 &&
      status < 500 &&
      status != 401 &&
      status != 408 &&
      status != 429;
}

/// State of the "Gestión de usuarios" screen and of the Usuarios badge. It lives
/// as long as the session, so the queue is sent whichever tab is open.
///
/// Action methods rethrow [ApiException] so the screen can show a SnackBar; the
/// list stays consistent. Without a connection, approving or rejecting is queued
/// instead: the account stays in the list marked as waiting, and the decision
/// goes out when the connection is back. The server sends the email then.
class UsersController extends ChangeNotifier {
  UsersController(
    this._repository, {
    required this._store,
    this.retryEvery = const Duration(seconds: 15),
  });

  final UsersRepository _repository;
  final PendingReviewStore _store;

  /// How often queued decisions are retried while there are any.
  final Duration retryEvery;

  List<AuthUser> _all = [];
  List<PendingReview> _queue = [];
  bool _queueRead = false;
  bool _loading = false;
  bool _offline = false;
  bool _syncing = false;
  bool _disposed = false;
  String? _loadError;
  String? _syncIssue;
  String? _syncNotice;
  bool _syncNoticeIsProblem = false;
  Timer? _retryTimer;
  final Set<int> _busy = {};

  bool get loading => _loading;
  String? get loadError => _loadError;
  bool get hasLoaded => _loadedOnce;
  bool _loadedOnce = false;

  /// The last refresh failed for lack of a connection: the list is the last one
  /// received, and decisions on it will be queued.
  bool get offline => _offline;

  /// Every request the server still holds as pending, decided here or not.
  List<AuthUser> get pending => _all.where((u) => u.isPending).toList();

  /// Pending requests nobody has decided yet: what the badge counts.
  List<AuthUser> get awaitingDecision =>
      pending.where((u) => queuedReview(u.id) == null).toList();

  /// Real accounts: active and disabled. Rejected requests are not shown.
  List<AuthUser> get accounts => _all.where((u) => u.isActive || u.isDisabled).toList();

  bool isBusy(int id) => _busy.contains(id);

  /// Decisions the server has not received yet.
  int get queuedCount => _queue.length;
  bool get syncing => _syncing;

  /// The decision waiting to be sent for this account, if any.
  PendingReview? queuedReview(int userId) =>
      _queue.where((r) => r.userId == userId).firstOrNull;

  /// Why the queue could not go out although the server was reached (it failed,
  /// or the session expired). The queue is kept.
  String? get syncIssue => _syncIssue;

  /// Result of the last sync, shown until dismissed.
  String? get syncNotice => _syncNotice;
  bool get syncNoticeIsProblem => _syncNoticeIsProblem;

  Future<void> load() async {
    _loading = true;
    _loadError = null;
    _offline = false;
    notifyListeners();
    try {
      await _readQueue();
      _all = await _repository.list();
      _loadedOnce = true;
    } on ApiException catch (e) {
      _loadError = e.message;
      _offline = e.isOffline;
    } finally {
      _loading = false;
      notifyListeners();
    }
    if (_loadError == null) await syncQueue();
  }

  Future<ReviewOutcome> approve(AuthUser user) => _decide(user, approve: true);

  Future<ReviewOutcome> reject(AuthUser user) => _decide(user, approve: false);

  Future<void> setEnabled(AuthUser user, {required bool enabled}) =>
      _run(user, () => _repository.setEnabled(user.id, enabled: enabled));

  Future<void> edit(AuthUser user, {required String fullName, required String email}) =>
      _run(user, () => _repository.update(user.id, fullName: fullName, email: email));

  Future<void> _run(AuthUser user, Future<AuthUser> Function() action) async {
    _busy.add(user.id);
    notifyListeners();
    try {
      _replace(await action());
    } finally {
      _busy.remove(user.id);
      notifyListeners();
    }
  }

  void _replace(AuthUser updated) {
    _all = [for (final u in _all) u.id == updated.id ? updated : u];
  }

  /// Sends the decision. No answer from the server means it is queued; any
  /// answer that is an error is a real error, reported and not queued.
  Future<ReviewOutcome> _decide(AuthUser user, {required bool approve}) async {
    await _readQueue();
    final review = PendingReview(userId: user.id, approve: approve, fullName: user.fullName);

    // Already waiting: the last decision replaces it, there are never two.
    if (queuedReview(user.id) != null) {
      if (_syncing) {
        throw const ApiException('Esta decisión se está enviando al servidor. Espera un momento.');
      }
      await _enqueue(review);
      notifyListeners();
      return ReviewOutcome.queued;
    }

    _busy.add(user.id);
    notifyListeners();
    try {
      _replace(await _repository.review(user.id, approve: approve));
      return ReviewOutcome.applied;
    } on ApiException catch (e) {
      if (!e.isOffline) rethrow;
      await _enqueue(review);
      return ReviewOutcome.queued;
    } finally {
      _busy.remove(user.id);
      notifyListeners();
    }
  }

  // ── Offline queue ────────────────────────────────────────────────────────

  Future<void> _readQueue() async {
    if (_queueRead) return;
    _queue = await _store.read();
    _queueRead = true;
    if (_queue.isNotEmpty) _scheduleRetry();
  }

  Future<void> _enqueue(PendingReview review) async {
    _queue = [
      for (final r in _queue)
        if (r.userId != review.userId) r,
      review,
    ];
    await _store.write(_queue);
    _scheduleRetry();
  }

  /// Takes back a decision that has not been sent. Not while a sync is running:
  /// it may already be on its way.
  Future<void> cancelQueued(int userId) async {
    if (_syncing) return;
    _queue = [
      for (final r in _queue)
        if (r.userId != userId) r,
    ];
    await _store.write(_queue);
    if (_queue.isEmpty) _stopRetry();
    notifyListeners();
  }

  void _scheduleRetry() {
    _retryTimer ??= Timer.periodic(retryEvery, (_) => syncQueue());
  }

  void _stopRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Sends the queued decisions. Before each one it checks what the server
  /// holds: a decision whose reply was lost is already applied (sending it again
  /// could not repeat the email, but would report a false error), and a request
  /// someone else resolved no longer accepts it.
  Future<void> syncQueue() async {
    if (_queue.isEmpty || _syncing) return;
    _syncing = true;
    _syncIssue = null;
    notifyListeners();

    var sent = 0;
    final problems = <String>[];
    try {
      _all = await _repository.list();
      _loadedOnce = true;
      _loadError = null;
      _offline = false;

      for (final review in [..._queue]) {
        // Signed out meanwhile: the rest must not go out with another session.
        if (_disposed) break;
        final name = review.fullName;
        final current = _all.where((u) => u.id == review.userId).firstOrNull;

        if (current == null) {
          _queue.remove(review);
          problems.add('$name: la cuenta ya no existe.');
        } else if (review.isAppliedOn(current)) {
          _queue.remove(review);
          sent++;
        } else if (!current.isPending) {
          _queue.remove(review);
          problems.add(
            '$name: la solicitud ya fue resuelta en el servidor y no se aplicó ${review.decisionLabel}.',
          );
        } else {
          try {
            _replace(await _repository.review(review.userId, approve: review.approve));
            _queue.remove(review);
            sent++;
          } on ApiException catch (e) {
            if (!_isRefusal(e)) rethrow; // keep this one and the rest queued
            _queue.remove(review);
            problems.add('$name: ${e.message}');
          }
        }
      }
    } on ApiException catch (e) {
      if (_isRefusal(e)) {
        // Refused before looking at any account: no longer allowed to review.
        problems.add('No se enviaron las decisiones pendientes: ${e.message}');
        _queue.clear();
      } else if (!e.isOffline) {
        _syncIssue = e.message;
      }
    } finally {
      await _store.write(_queue);
      _syncing = false;
    }

    if (_queue.isEmpty) _stopRetry();
    if (sent > 0 || problems.isNotEmpty) {
      _syncNotice = [
        if (sent == 1) 'Se envió 1 decisión al servidor, que notificará por correo a la persona.',
        if (sent > 1) 'Se enviaron $sent decisiones al servidor, que notificará por correo a cada persona.',
        ...problems,
      ].join(' ');
      _syncNoticeIsProblem = problems.isNotEmpty;
    }
    notifyListeners();
  }

  void dismissSyncNotice() {
    _syncNotice = null;
    notifyListeners();
  }

  /// A sync can end after the session does (the provider is gone by then).
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopRetry();
    super.dispose();
  }
}
