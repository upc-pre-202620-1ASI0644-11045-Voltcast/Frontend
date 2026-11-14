import '../../../core/format.dart';

/// State of the Google Drive connection (`GET /integrations/drive/status`).
class DriveStatus {
  const DriveStatus({
    required this.connected,
    this.account,
    this.lastSyncAt,
    this.connectedAt,
    this.error,
  });

  final bool connected;
  final String? account;

  /// Local time; null until the first sync.
  final DateTime? lastSyncAt;
  final DateTime? connectedAt;

  /// `invalid_grant` or `sync_failed`; null when all is well.
  final String? error;

  /// Google revoked the access: the supervisor must connect again.
  bool get isRevoked => error == 'invalid_grant';
  bool get syncFailed => error == 'sync_failed';

  factory DriveStatus.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) => json[key] is String
        ? parseApiDateTime(json[key] as String)
        : null;
    return DriveStatus(
      connected: json['connected'] == true,
      account: json['account'] as String?,
      lastSyncAt: date('lastSyncAt'),
      connectedAt: date('connectedAt'),
      error: json['error'] as String?,
    );
  }

  /// Only for the offline copy; carries no token or code.
  Map<String, dynamic> toJson() => {
    'connected': connected,
    'account': account,
    'lastSyncAt': lastSyncAt?.toUtc().toIso8601String(),
    'connectedAt': connectedAt?.toUtc().toIso8601String(),
    'error': error,
  };
}
