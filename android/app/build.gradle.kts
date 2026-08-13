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
val envFile = File(project.rootDir.parentFile, ".env")
val envExampleFile = File(project.rootDir.parentFile, ".env.example")
val envProperties = Properties()
when {
    envFile.exists() -> envFile.inputStream().use { envProperties.load(it) }
    envExampleFile.exists() -> envExampleFile.inputStream().use { envProperties.load(it) }
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
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        // Must match the package_name registered in google-services.json exactly.
        applicationId = "com.vero265.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Driven by pubspec.yaml `version: x.y.z+build` (Flutter injects these).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        // Load Google Maps API key from .env
        val googleMapsKey = envProperties.getProperty("GOOGLE_MAPS_API_KEY", "")
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsKey
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
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.multidex:multidex:2.0.1")
    // Apache HTTP library for Google Maps compatibility (required for Android API 28+)
    implementation("org.apache.httpcomponents:httpclient:4.5.14")
}