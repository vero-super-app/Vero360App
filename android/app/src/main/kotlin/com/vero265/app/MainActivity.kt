package com.vero265.app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "vero365.app/driver_alerts"

    override fun onCreate(savedInstanceState: Bundle?) {
        // Draw behind the status and navigation bars on Android 14 and below.
        // Android 15+ already does this when the app targets SDK 35.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // Keep extras so Dart can open the accept popup after a lock-screen launch.
        intent?.let { DriverAlertIntents.store(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        DriverAlertIntents.store(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> {
                        result.success(canUseFullScreenIntent())
                    }
                    "requestFullScreenIntent" -> {
                        requestFullScreenIntentSettings()
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }
                    "takeLaunchExtras" -> {
                        result.success(DriverAlertIntents.take())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val nm = getSystemService(NotificationManager::class.java) ?: return true
        return nm.canUseFullScreenIntent()
    }

    private fun requestFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        if (canUseFullScreenIntent()) return
        try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
        } catch (_: Exception) {
            startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                },
            )
        } catch (_: Exception) {
        }
    }
}

object DriverAlertIntents {
    @Volatile
    private var extras: HashMap<String, Any?>? = null

    fun store(intent: Intent) {
        val restore = intent.getBooleanExtra("restore_driver_online", false)
        val rideId = intent.getStringExtra("ride_offer_id")
        if (!restore && rideId.isNullOrBlank()) return
        extras = hashMapOf(
            "restoreDriverOnline" to restore,
            "rideOfferId" to (rideId ?: ""),
        )
    }

    fun take(): HashMap<String, Any?>? {
        val current = extras
        extras = null
        return current
    }
}
