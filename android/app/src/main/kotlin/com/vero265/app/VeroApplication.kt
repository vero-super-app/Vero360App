package com.vero265.app

import android.app.Application
import io.flutter.FlutterInjector

/**
 * Force-disable Impeller before any FlutterEngine starts.
 * Impeller OpenGLES still OOMs Adreno 506 (Redmi 8A / 2GB) until SIGSEGV
 * on the raster thread — legacy Skia is required on this class of devices.
 */
class VeroApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(this)
        loader.ensureInitializationComplete(
            this,
            arrayOf("--enable-impeller=false"),
        )
    }
}
