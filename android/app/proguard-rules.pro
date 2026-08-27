# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google ML Kit — keep all text recognizer options (including CJK, Devanagari)
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.common.** { *; }

# Suppress R8 missing class warnings for optional ML Kit language modules
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.**

# Google Play Core (deferred components, split install — optional)
-dontwarn com.google.android.play.core.**

# Google Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Suppress informational notes (not real warnings) — targeted replacement for -ignorewarnings.
# -ignorewarnings was too broad: it hid genuine R8 class-stripping errors.
-dontnote **


# ── device_calendar + Gson ───────────────────────────────────────────────
# THE CAUSE OF THE "21 calendars, all null" BUG.
#
# device_calendar's Android side serialises its models with Gson, which
# derives JSON keys from FIELD NAMES by reflection. With minifyEnabled true,
# R8 renamed those fields, so the plugin emitted {"a":...,"b":...} and the
# Dart side's Calendar.fromJson — which looks up json['id'], json['name'] —
# got null for every field. The result: 21 calendars returned, every one of
# them "Unnamed calendar" with a null id, and no calendar selectable.
#
# It only ever reproduced in RELEASE builds, which is why the same code
# worked perfectly on the iOS simulator in debug.
-keep class com.builttoroam.devicecalendar.** { *; }
-keepclassmembers class com.builttoroam.devicecalendar.models.** { *; }

# Gson itself: generic signatures and annotated fields must survive, or the
# same class of failure appears in any other Gson-backed plugin.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class sun.misc.Unsafe { *; }
-dontwarn sun.misc.**
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Other plugins that marshal models across the platform channel by field
# name. Same failure mode, so keep them for the same reason.
-keep class co.quis.flutter_contacts.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
