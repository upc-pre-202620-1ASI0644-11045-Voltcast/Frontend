import 'package:flutter/material.dart';

import 'app.dart';
import 'core/push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await PushService.init();
  } catch (e) {
    // Push is optional: the app must still start without Google Play services.
    debugPrint('Push init failed: $e');
  }
  runApp(const VoltCastApp());
}
