import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.JavaVersion

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter plugin must come after Android & Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()

if (hasKeystore) {
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

    // 🔐 SIGNING CONFIG
    signingConfigs {
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
        // (optional) debug config stays default
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true

            // ✅ Only reference "release" signingConfig if it actually exists
            if (hasKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            // else: Gradle will keep the default signing (usually debug) for local builds
        }
    }

    // ✅ JVM target
    kotlinOptions {
        jvmTarget = "1.8"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

// Flutter dependencies
flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
}
