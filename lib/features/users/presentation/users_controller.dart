import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/data/auth_user.dart';
import '../data/users_repository.dart';

/// State of the "Gestión de usuarios" screen. Action methods rethrow
/// [ApiException] so the screen can show a SnackBar; the list stays consistent.
class UsersController extends ChangeNotifier {
  UsersController(this._repository);

  final UsersRepository _repository;

  List<AuthUser> _all = [];
  bool _loading = false;
  String? _loadError;
  final Set<int> _busy = {};

  bool get loading => _loading;
  String? get loadError => _loadError;
  bool get hasLoaded => _loadedOnce;
  bool _loadedOnce = false;

  List<AuthUser> get pending => _all.where((u) => u.isPending).toList();

  /// Real accounts: active and disabled. Rejected requests are not shown.
  List<AuthUser> get accounts => _all.where((u) => u.isActive || u.isDisabled).toList();

  bool isBusy(int id) => _busy.contains(id);

  Future<void> load() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      _all = await _repository.list();
      _loadedOnce = true;
    } on ApiException catch (e) {
      _loadError = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> approve(AuthUser user) => _run(user, () => _repository.review(user.id, approve: true));

  Future<void> reject(AuthUser user) => _run(user, () => _repository.review(user.id, approve: false));

  Future<void> setEnabled(AuthUser user, {required bool enabled}) =>
      _run(user, () => _repository.setEnabled(user.id, enabled: enabled));

  Future<void> edit(AuthUser user, {required String fullName, required String email}) =>
      _run(user, () => _repository.update(user.id, fullName: fullName, email: email));

  Future<void> _run(AuthUser user, Future<AuthUser> Function() action) async {
    _busy.add(user.id);
    notifyListeners();
    try {
      final updated = await action();
      _all = [for (final u in _all) u.id == updated.id ? updated : u];
    } finally {
      _busy.remove(user.id);
      notifyListeners();
    }
  }
}
