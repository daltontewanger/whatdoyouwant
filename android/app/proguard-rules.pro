# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Preserve Firebase classes (Analytics, Auth, Firestore, etc.)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep annotations (often used by Firebase & JSON libraries)
-keepattributes *Annotation*

# Keep serialized names (for JSON parsing if needed)
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Optional: Log warning if anything gets removed unexpectedly
-dontwarn io.flutter.embedding.**
-dontwarn com.google.firebase.**
