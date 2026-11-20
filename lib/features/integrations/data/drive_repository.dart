import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import 'drive_status.dart';

/// Where the last known status lives, to show it without network.
abstract class DriveStatusStore {
  Future<String?> read();
  Future<void> write(String json);
}

class PrefsDriveStatusStore implements DriveStatusStore {
  static const _key = 'drive_status';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String json) async =>
      (await SharedPreferences.getInstance()).setString(_key, json);
}

/// In-memory store for tests.
class MemoryDriveStatusStore implements DriveStatusStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

/// `/integrations/drive` endpoints. `/callback` is Google's, not the app's.
class DriveRepository {
  DriveRepository(this._api, {DriveStatusStore? store})
    : _store = store ?? PrefsDriveStatusStore();

  static const _base = '/integrations/drive';

  final ApiClient _api;
  final DriveStatusStore _store;

  /// Any signed-in user. Remembers the answer for [lastKnown].
  Future<DriveStatus> status() async {
    final status = DriveStatus.fromJson(
      await _api.get('$_base/status', auth: true) as Map<String, dynamic>,
    );
    try {
      await _store.write(
        jsonEncode({
          'saved': DateTime.now().toUtc().toIso8601String(),
          'status': status.toJson(),
        }),
      );
    } on Object {
      // The copy is a convenience; a failed write only loses it.
    }
    return status;
  }

  /// The last status received and when it was saved, or null.
  Future<({DriveStatus status, DateTime savedAt})?> lastKnown() async {
    try {
      final raw = await _store.read();
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        status: DriveStatus.fromJson(json['status'] as Map<String, dynamic>),
        savedAt: DateTime.parse(json['saved'] as String).toLocal(),
      );
    } on Object {
      return null;
    }
  }

  /// Supervisors only (403 otherwise; 503 when the server has no Drive set up).
  /// Returns the Google consent URL.
  Future<Uri> connect() async {
    final data =
        await _api.get('$_base/connect', auth: true) as Map<String, dynamic>;
    return Uri.parse(data['authorizationUrl'] as String);
  }

  /// Supervisors only. Answers 204; the datasets already created are kept.
  Future<void> disconnect() => _api.delete(_base, auth: true);
}
