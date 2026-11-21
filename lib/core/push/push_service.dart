import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Must be top-level: Android runs it in a separate isolate when the app is in background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// shortcut: getToken/onTokenRefresh are deprecated for FID-based register(), but the backend
// sends via FCM v1 with a classic registration token; migrate if the backend moves to FIDs.
// ignore_for_file: deprecated_member_use
class PushService {
  /// Must match the `android.notification.channel_id` the backend sends, character by
  /// character. Android never raises a channel's importance once created: if it ever has
  /// to change, ship a new id (and the backend the same one).
  static const voltageChannelId = 'voltage_alerts';
  static const _voltageChannel = AndroidNotificationChannel(
    voltageChannelId,
    'Alertas de voltaje',
    importance: Importance.high,
  );

  static final _local = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // shortcut: Android (google-services.json) and iOS (GoogleService-Info.plist) read their
    // config from the native file; run `flutterfire configure` to add web.
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS hides foreground pushes by default; let the system banner show them,
      // so no local notification is needed there.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_voltcast'),
      ),
    );
    // Created at startup so it exists before the first push; background and closed pushes
    // use it too when the backend names it.
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_voltageChannel);
    // FCM never shows a `notification` message by itself while the app is open.
    // shortcut: every foreground push uses the voltage channel, also the supervisors'
    // access-request one; split by message.notification?.android?.channelId if it matters.
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      _local
          .show(
            id: (m.messageId ?? '${n.title}${n.body}').hashCode & 0x7fffffff,
            title: n.title,
            body: n.body,
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                voltageChannelId,
                'Alertas de voltaje',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          )
          .catchError((Object e) => debugPrint('Local notification failed: $e'));
    });
  }

  /// Asks for notification permission (Android 13+ / iOS) and returns the FCM
  /// token, or null when the user denied it.
  static Future<String?> token() async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
    final token = await messaging.getToken();
    debugPrint('FCM token: $token');
    return token;
  }

  /// Emits when FCM rotates the token, so it can be re-sent to the backend.
  static Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;
}
