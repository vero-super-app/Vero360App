# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase / Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Maps
-keep class com.google.android.apps.maps.** { *; }
-keep class com.google.maps.** { *; }

# Didit KYC SDK
-keep class com.didit.** { *; }
-keep class me.didit.** { *; }
-dontwarn com.didit.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
