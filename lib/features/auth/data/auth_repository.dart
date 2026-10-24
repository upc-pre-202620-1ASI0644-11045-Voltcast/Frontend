import '../../../core/network/api_client.dart';
import '../../../core/storage/token_storage.dart';
import 'auth_user.dart';

class AuthRepository {
  AuthRepository({required this._api, required this._tokens});

  final ApiClient _api;
  final TokenStorage _tokens;

  Future<bool> hasStoredSession() async => (await _tokens.accessToken) != null;

  Future<AuthUser> login({required String email, required String password}) async {
    final data = await _api.post(
      '/auth/login',
      body: {'email': email.trim().toLowerCase(), 'password': password},
    ) as Map<String, dynamic>;

    await _tokens.saveTokens(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AuthUser> currentUser() async {
    final data = await _api.get('/auth/me', auth: true) as Map<String, dynamic>;
    return AuthUser.fromJson(data);
  }

  /// Creates a *pending* request: the user cannot log in until a supervisor approves it.
  Future<void> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    await _api.post('/auth/register', body: {
      'full_name': fullName.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
    });
  }

  Future<void> requestPasswordReset(String email) async {
    await _api.post(
      '/auth/password-reset/request',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _api.post('/auth/password-reset/confirm', body: {
      'email': email.trim().toLowerCase(),
      'code': code,
      'new_password': newPassword,
    });
  }

  Future<void> logout() => _tokens.clear();
}
