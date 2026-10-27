import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/auth_repository.dart';
import '../data/auth_user.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

/// Holds the session; the router listens to it to guard private routes.
class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthRepository _repository;

  AuthStatus _status = AuthStatus.unknown;
  AuthUser? _user;

  AuthStatus get status => _status;
  AuthUser? get user => _user;

  /// Restores the session from stored tokens on app start.
  Future<void> restoreSession() async {
    if (!await _repository.hasStoredSession()) {
      return _set(AuthStatus.unauthenticated);
    }
    try {
      _set(AuthStatus.authenticated, await _repository.currentUser());
    } on ApiException catch (e) {
      // 401 means the tokens are dead (ApiClient already cleared them after a
      // failed refresh). Any other failure (offline) keeps the tokens.
      if (e.isUnauthorized) await _repository.logout();
      _set(AuthStatus.unauthenticated);
    }
  }

  /// Throws [ApiException] with a user-facing message on failure.
  Future<void> login({required String email, required String password}) async {
    final user = await _repository.login(email: email, password: password);
    _set(AuthStatus.authenticated, user);
  }

  Future<void> logout() async {
    await _repository.logout();
    _set(AuthStatus.unauthenticated);
  }

  /// Wired to ApiClient.onSessionExpired.
  void handleSessionExpired() => _set(AuthStatus.unauthenticated);

  void _set(AuthStatus status, [AuthUser? user]) {
    _status = status;
    _user = user;
    notifyListeners();
  }
}
