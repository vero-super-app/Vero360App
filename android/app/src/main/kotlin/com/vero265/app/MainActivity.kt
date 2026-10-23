package com.vero265.app

import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "vero365.app/driver_alerts"
    private val galleryChannelName = "vero360.app/gallery"

    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge-to-edge on Android 14 and below. Android 15+ already does this
        // when the app targets SDK 35. This AndroidX version exposes the
        // Kotlin helper enableEdgeToEdge(), not a class named EdgeToEdge.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
        }
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, galleryChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveVideo" -> {
                        saveVideoToGallery(
                            call.argument("path"),
                            call.argument("fileName"),
                            result,
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveVideoToGallery(
        path: String?,
        fileName: String?,
        result: MethodChannel.Result,
    ) {
        if (path.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("bad_args", "Missing video file", null)
            return
        }
        val src = File(path)
        if (!src.exists() || src.length() <= 0L) {
            result.error("missing", "Video file is empty", null)
            return
        }
        Thread {
            fun fail(code: String, message: String) {
                runOnUiThread { result.error(code, message, null) }
            }
            fun ok() {
                runOnUiThread { result.success(true) }
            }
            try {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    val destDir = File(
                        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                        "Vero360",
                    )
                    if (!destDir.exists() && !destDir.mkdirs()) {
                        fail("mkdir", "Could not create Movies/Vero360")
                        return@Thread
                    }
                    val dest = File(destDir, fileName)
                    src.copyTo(dest, overwrite = true)
                    MediaScannerConnection.scanFile(
                        this,
                        arrayOf(dest.absolutePath),
                        arrayOf("video/mp4"),
                        null,
                    )
                    ok()
                    return@Thread
                }

                val resolver = contentResolver
                val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val folders = arrayOf(
                    Environment.DIRECTORY_MOVIES + "/Vero360/",
                    Environment.DIRECTORY_MOVIES + "/Vero360",
                    Environment.DIRECTORY_MOVIES,
                )
                var uri: Uri? = null
                for (folder in folders) {
                    val values = ContentValues().apply {
                        put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                        put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                        put(MediaStore.Video.Media.RELATIVE_PATH, folder)
                        put(MediaStore.Video.Media.IS_PENDING, 1)
                    }
                    uri = try {
                        resolver.insert(collection, values)
                    } catch (_: IllegalArgumentException) {
                        null
                    }
                    if (uri != null) break
                }
                if (uri == null) {
                    fail("insert", "Could not create gallery entry")
                    return@Thread
                }
                try {
                    resolver.openOutputStream(uri)?.use { out ->
                        FileInputStream(src).use { input -> input.copyTo(out) }
                    } ?: run {
                        resolver.delete(uri, null, null)
                        fail("write", "Could not write video")
                        return@Thread
                    }
                    val done = ContentValues().apply {
                        put(MediaStore.Video.Media.IS_PENDING, 0)
                    }
                    resolver.update(uri, done, null, null)
                    ok()
                } catch (e: Exception) {
                    try {
                        resolver.delete(uri, null, null)
                    } catch (_: Exception) {
                    }
                    fail("save", e.message ?: "Could not save video")
                }
            } catch (e: Exception) {
                fail("save", e.message ?: "Could not save video")
            }
        }.start()
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
