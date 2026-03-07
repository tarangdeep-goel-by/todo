# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Play Core (referenced by Flutter deferred components)
-dontwarn com.google.android.play.core.**

# Keep Dart annotations
-keepattributes *Annotation*
