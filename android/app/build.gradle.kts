import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.JavaVersion

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter plugin must come after Android & Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    // Add Google services plugin if using Firebase
    id("com.google.gms.google-services") version "4.4.0" apply false
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
    compileSdk = 35  // Use explicit value instead of flutter.compileSdkVersion

    defaultConfig {
        applicationId = "com.vero.vero360"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
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
            // REMOVE this line or fix it:
            // signingConfig = signingConfigs.findByName("debug") ?: signingConfigs.getAt(0)
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")

            // ✅ Only reference "release" signingConfig if it actually exists
            if (hasKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            // else: Gradle will keep the default signing (usually debug) for local builds
        }
    }

    // ✅ Fix Java version warnings - update to Java 11
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"  // Updated from "1.8" to "11"
    }

    // Add buildFeatures if needed
    buildFeatures {
        buildConfig = true
    }
}

// Flutter dependencies
flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    
    // Add Firebase BoM if using Firebase
    // implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    // implementation("com.google.firebase:firebase-auth")
    
    // Core AndroidX dependencies
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
}
