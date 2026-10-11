# R8 is on for release (minify + shrink + proguard-android-optimize).
# Do not add blanket `-keep class io.flutter.** { *; }` or
# `-keep class com.google.firebase.** { *; }` rules. Those stop shrinking,
# optimization, and obfuscation, which is what Play Console flags.
#
# Flutter's Gradle plugin already keeps FlutterPlugin implementations
# with allowshrinking and allowobfuscation. Firebase, Play services, and
# Maps ship their own consumer rules.

-dontwarn io.flutter.embedding.**
-dontwarn io.flutter.plugin.**

# JNI entry points. Names must stay stable for the native side.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Play looks for EdgeToEdge.enable / enableEdgeToEdge by name. R8 was renaming
# that helper, so Console both missed the backward-compat call and listed its
# internal window-color calls as if they were app code.
-keep class androidx.activity.EdgeToEdge { *; }
-keep class androidx.activity.EdgeToEdgeKt { *; }
-keep class androidx.activity.EdgeToEdge* { *; }
-keep class com.vero265.app.MainActivity { *; }
