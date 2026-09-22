package com.vero265.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * After reboot, remind an online driver to reopen Vero so GPS matching resumes.
 * Ride offers themselves still arrive via FCM full-screen alerts.
 */
class DriverOnlineBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (
            action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val online = prefs.getBoolean("flutter.driver_online_session_active", false)
        if (!online) return

        val channelId = "driver_ride_requests"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Driver Ride Requests",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Incoming ride offers for drivers"
                    enableVibration(true)
                },
            )
        }

        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("restore_driver_online", true)
        }
        val pending = PendingIntent.getActivity(
            context,
            7101,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Vero Ride is still online")
            .setContentText("Open the app so you keep receiving nearby ride requests.")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setFullScreenIntent(pending, true)
            .setCategory(Notification.CATEGORY_CALL)
            .build()

        try {
            nm.notify(7101, notification)
        } catch (_: SecurityException) {
        }
    }
}
