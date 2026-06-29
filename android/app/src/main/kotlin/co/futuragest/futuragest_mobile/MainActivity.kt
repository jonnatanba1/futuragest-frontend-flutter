package co.futuragest.futuragest_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createDefaultNotificationChannel()
    }

    /**
     * Creates the default FCM notification channel so heads-up notifications
     * work on Android 8+ (API 26+). The channel id MUST match
     * `com.google.firebase.messaging.default_notification_channel_id` declared
     * in AndroidManifest.xml (fcm_default_channel). No-op below API 26.
     */
    private fun createDefaultNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            DEFAULT_CHANNEL_ID,
            DEFAULT_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        )

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private companion object {
        const val DEFAULT_CHANNEL_ID = "fcm_default_channel"
        const val DEFAULT_CHANNEL_NAME = "Novedades"
    }
}
