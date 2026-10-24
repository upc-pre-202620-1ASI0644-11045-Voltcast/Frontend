import '../../../core/network/api_client.dart';
import '../../auth/data/auth_user.dart';

/// Supervisor-only endpoints (`/users`). The backend answers 403 to engineers.
class UsersRepository {
  UsersRepository(this._api);

  final ApiClient _api;

  Future<List<AuthUser>> list({String? status}) async {
    final query = status == null ? '' : '?status=$status';
    final data = await _api.get('/users$query', auth: true) as List;
    return data.map((e) => AuthUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Approved requests become engineers (`USER`); the app never grants ADMIN.
  Future<AuthUser> review(int id, {required bool approve}) => _user(
        _api.patch(
          '/users/$id/approval',
          body: {'decision': approve ? 'approve' : 'reject', 'role': 'USER'},
          auth: true,
        ),
      );

  Future<AuthUser> update(int id, {String? fullName, String? email}) => _user(
        _api.put(
          '/users/$id',
          body: {
            'full_name': ?fullName?.trim(),
            'email': ?email?.trim().toLowerCase(),
          },
          auth: true,
        ),
      );

  Future<AuthUser> setEnabled(int id, {required bool enabled}) => _user(
        _api.patch(
          '/users/$id/status',
          body: {'status': enabled ? 'active' : 'disabled'},
          auth: true,
        ),
      );

  Future<AuthUser> _user(Future<dynamic> call) async =>
      AuthUser.fromJson(await call as Map<String, dynamic>);
}
