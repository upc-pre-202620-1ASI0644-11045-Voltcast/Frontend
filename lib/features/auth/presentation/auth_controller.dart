import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/auth_repository.dart';
import '../data/auth_user.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

/// Holds the session; the router listens to it to guard private routes.
class AuthController extends ChangeNotifier {
  AuthController(
    this._repository, {
    this.restoreRetryEvery = const Duration(seconds: 15),
  });

  final AuthRepository _repository;

  /// How often a stored session is tried again after opening without a
  /// connection. What was queued offline goes out once it is back.
  final Duration restoreRetryEvery;

  AuthStatus _status = AuthStatus.unknown;
  AuthUser? _user;
  Timer? _restoreRetry;

  AuthStatus get status => _status;
  AuthUser? get user => _user;

  /// Restores the session from stored tokens on app start.
  Future<void> restoreSession() async {
    _cancelRestoreRetry();
    if (!await _repository.hasStoredSession()) {
      return _set(AuthStatus.unauthenticated);
    }
    try {
      final user = await _repository.currentUser();
      // Signed in by hand while this attempt was on its way.
      if (_status != AuthStatus.authenticated) {
        _set(AuthStatus.authenticated, user);
      }
    } on ApiException catch (e) {
      if (_status == AuthStatus.authenticated) return;
      // 401 means the tokens are dead (ApiClient already cleared them after a
      // failed refresh). Any other failure (offline) keeps the tokens, so the
      // session can come back by itself with the connection.
      if (e.isUnauthorized) {
        await _repository.logout();
      } else {
        _restoreRetry = Timer(restoreRetryEvery, restoreSession);
      }
      if (_status != AuthStatus.unauthenticated) {
        _set(AuthStatus.unauthenticated);
      }
    }
  }

  void _cancelRestoreRetry() {
    _restoreRetry?.cancel();
    _restoreRetry = null;
  }

  /// Throws [ApiException] with a user-facing message on failure.
  Future<void> login({required String email, required String password}) async {
    final user = await _repository.login(email: email, password: password);
    _cancelRestoreRetry();
    _set(AuthStatus.authenticated, user);
  }

  Future<void> logout() async {
    _cancelRestoreRetry();
    await _repository.logout();
    _set(AuthStatus.unauthenticated);
  }

  /// Wired to ApiClient.onSessionExpired.
  void handleSessionExpired() {
    _cancelRestoreRetry();
    _set(AuthStatus.unauthenticated);
  }

  void _set(AuthStatus status, [AuthUser? user]) {
    _status = status;
    _user = user;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelRestoreRetry();
    super.dispose();
  }
}
