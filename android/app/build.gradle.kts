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

// Load .env file (local). Fall back to committed .env.example for CI (Codemagic).
val envFileCandidates = listOf(
    File(project.rootDir.parentFile, ".env"),
    rootProject.file("../.env"),
    file("../../.env"),
)
val envExampleCandidates = listOf(
    File(project.rootDir.parentFile, ".env.example"),
    rootProject.file("../.env.example"),
    file("../../.env.example"),
)
val envProperties = Properties()
val envFile = envFileCandidates.firstOrNull { it.exists() }
val envExampleFile = envExampleCandidates.firstOrNull { it.exists() }
when {
    envFile != null -> envFile.inputStream().use { envProperties.load(it) }
    envExampleFile != null -> envExampleFile.inputStream().use { envProperties.load(it) }
}

// Release signing: create android/key.properties (see Flutter keystore guide).
// If missing, release uses the debug keystore so local APK installs still work.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.vero265.app"

    compileSdk = flutter.compileSdkVersion
    // Plugins (Firebase, Maps, WebView, …) require NDK 28. It is backward compatible.
    ndkVersion = "28.2.13676358"

    // NDK r28 crashes CMake 3.22.1 on Windows (access violation -1073741819).
    // 3.31.6 is installed under the Android SDK; pin it so AGP does not keep 3.22.1.
    externalNativeBuild {
        cmake {
            version = "3.31.6"
        }
    }

    defaultConfig {
        // Must match the package_name registered in google-services.json exactly.
        applicationId = "com.vero265.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Driven by pubspec.yaml `version: x.y.z+build` (Flutter injects these).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        // Play delivers one ABI per phone, so a 32-bit Redmi still gets armeabi-v7a.
        // arm64-v8a is required for 64-bit devices and for the 16 KB page-size check.
        // Do not also pass Flutter `--split-per-abi` — AGP rejects both together.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }

        // Load Google Maps API key from .env, with built-in fallback for local/CI.
        val googleMapsKey = envProperties.getProperty("GOOGLE_MAPS_API_KEY", "")
            ?.trim()
            .orEmpty()
            .ifEmpty { "AIzaSyAQtLkqSetILdLacfIxnqH8DEC0qcobCuI" }
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsKey
        buildConfigField("String", "GOOGLE_MAPS_API_KEY", "\"$googleMapsKey\"")
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "META-INF/DEPENDENCIES"
            pickFirsts += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
        }
        // Compress .so in the APK — smaller install on low-storage Redmi phones.
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storePassword = keystoreProperties["storePassword"] as String
                val rawStore = keystoreProperties["storeFile"] as String
                val fromAndroid = rootProject.file(rawStore)
                val fromApp = file(rawStore)
                storeFile = when {
                    fromAndroid.exists() -> fromAndroid
                    fromApp.exists() -> fromApp
                    else -> fromAndroid
                }
            }
        }
    }

    buildTypes {
        getByName("release") {
            // Local/dev: fall back to debug signing when key.properties is absent.
            // Play Store uploads still need android/key.properties (gitignored).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        // Profile is what you should run on 2GB phones (debug is too heavy).
        getByName("profile") {
            matchingFallbacks += listOf("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

// Play Console: libdatastore_shared_counter.so from DataStore 1.2.0 crashes on 16 KB devices.
// 1.2.1 rebuilds that library with 16 KB alignment.
configurations.configureEach {
    resolutionStrategy {
        force("androidx.datastore:datastore:1.2.1")
        force("androidx.datastore:datastore-android:1.2.1")
        force("androidx.datastore:datastore-core:1.2.1")
        force("androidx.datastore:datastore-core-android:1.2.1")
        force("androidx.datastore:datastore-preferences:1.2.1")
        force("androidx.datastore:datastore-preferences-android:1.2.1")
        force("androidx.datastore:datastore-preferences-core:1.2.1")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.multidex:multidex:2.0.1")
    // Apache HTTP library for Google Maps compatibility (required for Android API 28+)
    implementation("org.apache.httpcomponents:httpclient:4.5.14")
}
