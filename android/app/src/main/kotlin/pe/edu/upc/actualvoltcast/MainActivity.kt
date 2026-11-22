package pe.edu.upc.actualvoltcast

import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // url_launcher only has mailto:, which opens a compose screen; this opens the inbox.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voltcast/mail")
            .setMethodCallHandler { call, result ->
                if (call.method != "openInbox") return@setMethodCallHandler result.notImplemented()
                val intent = Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_EMAIL)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                result.success(
                    try {
                        startActivity(intent)
                        true
                    } catch (e: ActivityNotFoundException) {
                        false
                    },
                )
            }
    }
}
