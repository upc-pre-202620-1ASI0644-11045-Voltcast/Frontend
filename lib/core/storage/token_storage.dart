import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  String? _access;
  String? _refresh;
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _access = await _storage.read(key: _accessKey);
    _refresh = await _storage.read(key: _refreshKey);
    _loaded = true;
  }

  Future<String?> get accessToken async {
    await _load();
    return _access;
  }

  Future<String?> get refreshToken async {
    await _load();
    return _refresh;
  }

  Future<void> saveTokens({required String access, String? refresh}) async {
    await _load();
    _access = access;
    await _storage.write(key: _accessKey, value: access);
    if (refresh != null) {
      _refresh = refresh;
      await _storage.write(key: _refreshKey, value: refresh);
    }
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _loaded = true;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
