import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter plugin must come after Android & Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties (edit path if yours is in android/key.properties)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
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

    // ✅ Use Java 1.8 for both Kotlin and Java to fix JVM target mismatch
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8.toString()
    }

    // 🔐 Signing config for release
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: error("keyAlias missing in key.properties")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: error("keyPassword missing in key.properties")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                    ?: error("storeFile missing in key.properties")
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: error("storePassword missing in key.properties")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Flutter dependencies
flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
}
