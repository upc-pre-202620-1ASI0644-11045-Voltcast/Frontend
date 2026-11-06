import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Must be top-level: Android runs it in a separate isolate when the app is in background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// shortcut: getToken/onTokenRefresh are deprecated for FID-based register(), but the backend
// sends via FCM v1 with a classic registration token; migrate if the backend moves to FIDs.
// ignore_for_file: deprecated_member_use
class PushService {
  /// Current FCM token; null until permission is granted and Firebase is ready.
  static Future<String?> init() async {
    // shortcut: Android only (google-services.json); run `flutterfire configure` to add iOS/web.
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    final messaging = FirebaseMessaging.instance;
    // Android 13+ asks for POST_NOTIFICATIONS here.
    await messaging.requestPermission();
    FirebaseMessaging.onMessage.listen((m) {
      debugPrint('FCM foreground: ${m.notification?.title} ${m.data}');
    });
    final token = await messaging.getToken();
    debugPrint('FCM token: $token');
    return token;
  }

  /// Emits when FCM rotates the token, so it can be re-sent to the backend.
  static Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;
}
