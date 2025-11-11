import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter plugin must come after Android & Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties") // or "android/key.properties"
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.vero.vero360"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        applicationId = "com.vero.vero360"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 10001
        versionName = "1.0.1"
        multiDexEnabled = true
    }

    signingConfigs {
        // Only create release signing config if key.properties exists
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: error("keyAlias is missing in key.properties")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: error("keyPassword is missing in key.properties")

                val storeFilePath = keystoreProperties.getProperty("storeFile")
                    ?: error("storeFile is missing in key.properties")
                storeFile = file(storeFilePath)

                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: error("storePassword is missing in key.properties")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
            // debug will use the default debug keystore
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            // Only set signingConfig if we created it
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}
