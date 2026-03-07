# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Dio HTTP client
-keep class io.dio.** { *; }
-dontwarn io.dio.**

# SQLCipher
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# App Links (deep linking)
-keep class com.llfbandit.app_links.** { *; }

# Play Core (referenced by Flutter deferred components)
-dontwarn com.google.android.play.core.**

# Keep Dart annotations
-keepattributes *Annotation*

# Keep native methods
-keepclassmembers class * {
    native <methods>;
}
