pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localPropertiesFile = file("local.properties")

        require(localPropertiesFile.exists()) {
            "local.properties not found. Create android/local.properties with flutter.sdk=..."
        }

        localPropertiesFile.inputStream().use { stream ->
            properties.load(stream)
        }

        val sdkPath = properties.getProperty("flutter.sdk")
        require(!sdkPath.isNullOrBlank()) { "flutter.sdk not set in local.properties" }
        sdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // ✅ Upgrade AGP to satisfy the AndroidX metadata requirements
    id("com.android.application") version "8.11.0" apply false

    // Keep this for now (your warning is “soon”, not blocking)
    id("org.jetbrains.kotlin.android") version "2.1.20" apply false


    // Firebase plugins (keep if you use Firebase)
    id("com.google.gms.google-services") version "4.4.4" apply false
    id("com.google.firebase.crashlytics") version "3.0.6" apply false
}

include(":app")
