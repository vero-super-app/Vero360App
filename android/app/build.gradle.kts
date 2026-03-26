import org.gradle.api.JavaVersion
import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    // id("com.google.firebase.crashlytics") // optional
}

// Load .env file
val envFile = File(project.rootDir.parentFile, ".env")
val envProperties = Properties()
if (envFile.exists()) {
    envFile.inputStream().use { envProperties.load(it) }
}

// Release signing: create android/key.properties (see Flutter keystore guide).
// If missing, release uses the debug keystore so local APK installs still work.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.vero.vero360"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.vero.vero360"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 10001
        versionName = "1.0.1"
        multiDexEnabled = true
        
        // Load Google Maps API key from .env
        val googleMapsKey = envProperties.getProperty("GOOGLE_MAPS_API_KEY", "")
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsKey
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    buildFeatures {
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "META-INF/DEPENDENCIES"
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.multidex:multidex:2.0.1")
    // Apache HTTP library for Google Maps compatibility (required for Android API 28+)
    implementation("org.apache.httpcomponents:httpclient:4.5.14")
}
