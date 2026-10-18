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
    id("com.android.application") version "9.0.1" apply false

    // Flutter 3.47+ requires KGP >= 2.2.20 (warns below 2.3.20).
    // Must be >= 2.2.20 because AGP 9.0.1 drags KGP 2.2.10 onto the plugin
    // classpath transitively, so anything lower resolves to the unsupported 2.2.10.
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false


    // Firebase plugins (keep if you use Firebase)
    id("com.google.gms.google-services") version "4.4.4" apply false
    id("com.google.firebase.crashlytics") version "3.0.6" apply false
}

include(":app")
