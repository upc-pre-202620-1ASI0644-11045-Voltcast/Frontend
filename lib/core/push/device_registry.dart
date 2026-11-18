import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import 'push_service.dart';

/// Registers this phone's FCM token with the backend so it receives pushes for
/// the signed-in account. Nothing here throws: a failed registration is simply
/// tried again the next time the app opens with a session.
class DeviceRegistry {
  DeviceRegistry(this._api);

  static const _idKey = 'fcm_device_id';

  final ApiClient _api;
  StreamSubscription<String>? _refresh;

  Future<void> register() async {
    try {
      final token = await PushService.token();
      if (token == null) return;
      await _post(token);
      // The backend reassigns a known token to the current user, so re-sending is safe.
      _refresh ??= PushService.onTokenRefresh.listen(
        (t) => _post(t).catchError((Object e) => _log('refresh', e)),
      );
    } catch (e) {
      _log('register', e);
    }
  }

  /// Call before the tokens are cleared: the DELETE needs the access token.
  Future<void> unregister() async {
    await _refresh?.cancel();
    _refresh = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt(_idKey);
      if (id == null) return;
      await prefs.remove(_idKey);
      // Capped so signing out offline does not hang on the HTTP timeout.
      await _api
          .delete('/notifications/devices/$id', auth: true)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      _log('unregister', e);
    }
  }

  Future<void> _post(String token) async {
    final data =
        await _api.post(
              '/notifications/devices',
              body: {'token': token},
              auth: true,
            )
            as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idKey, data['id'] as int);
  }

  void _log(String what, Object e) => debugPrint('Device $what failed: $e');
}
