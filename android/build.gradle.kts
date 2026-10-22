allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// FlutterFire 6.2+/13.3+ skips `kotlin-android` on AGP 9 (expects built-in Kotlin).
// This app keeps `android.builtInKotlin=false` for Flutter 3.35, so those Kotlin
// plugin classes never compile and GeneratedPluginRegistrant cannot find them.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val hasKotlin =
            pluginManager.hasPlugin("org.jetbrains.kotlin.android") ||
                pluginManager.hasPlugin("kotlin-android")
        if (!hasKotlin && file("src/main/kotlin").exists()) {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
