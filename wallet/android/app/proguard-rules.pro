# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep Flutter secure storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep local_auth
-keep class androidx.biometric.** { *; }

# Prevent stripping crypto classes
-keep class javax.crypto.** { *; }
-keep class java.security.** { *; }
