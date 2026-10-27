import 'package:actualvoltcast/core/storage/token_storage.dart';

/// In-memory stand-in for the secure storage, so no platform channel is needed.
class MemoryTokens extends TokenStorage {
  MemoryTokens({String? access, String? refresh}) : _a = access, _r = refresh;

  String? _a;
  String? _r;

  @override
  Future<String?> get accessToken async => _a;

  @override
  Future<String?> get refreshToken async => _r;

  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    _a = access;
    if (refresh != null) _r = refresh;
  }

  @override
  Future<void> clear() async {
    _a = null;
    _r = null;
  }
}
