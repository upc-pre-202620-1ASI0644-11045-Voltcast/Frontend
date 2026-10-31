class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  /// No answer from the server (no network, timeout): offline mode applies.
  bool get isOffline => statusCode == null;

  @override
  String toString() => message;
}
