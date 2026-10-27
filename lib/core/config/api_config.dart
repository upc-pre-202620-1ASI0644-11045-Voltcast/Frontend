import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._();

  /// Override with: flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
  /// (required on a physical device, which cannot reach the PC via localhost).
  static const _override = String.fromEnvironment('API_BASE_URL');

  static const apiPrefix = '/api/v1';
  static const requestTimeout = Duration(seconds: 15);

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    // The Android emulator reaches the host machine through 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }
}
