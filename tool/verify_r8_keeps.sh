#!/usr/bin/env bash
# Verifies that R8 has NOT renamed the fields device_calendar marshals by name.
#
# This exists because that failure shipped. Gson populates Calendar's fields by
# name; R8 renamed them; the calendar list came back empty on release builds
# only, and no simulator, debug build or widget test could reproduce it. The
# keep rules in proguard-rules.pro are the fix — this asserts they still work
# against the artefact that actually ships.
#
# Instrumentation cannot cover this: integration_test is a dev_dependency and
# Flutter excludes dev dependencies from release variants, so an androidTest
# build cannot run against the minified APK. Reading the dex is both stronger
# and cheaper.
#
# Usage:  tool/verify_r8_keeps.sh [path/to/app-release.apk]
set -euo pipefail

APK="${1:-build/app/outputs/flutter-apk/app-release.apk}"
SDK="${ANDROID_HOME:-/usr/local/share/android-commandlinetools}"

[ -f "$APK" ] || { echo "FAIL: no APK at $APK — run 'flutter build apk --release' first"; exit 1; }

DEXDUMP=$(ls "$SDK"/build-tools/*/dexdump 2>/dev/null | head -1)
[ -n "$DEXDUMP" ] || { echo "FAIL: dexdump not found under $SDK/build-tools"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
unzip -qo "$APK" 'classes*.dex' -d "$WORK"
for d in "$WORK"/classes*.dex; do "$DEXDUMP" "$d" 2>/dev/null; done > "$WORK/all.txt"

CLASS="Lcom/builttoroam/devicecalendar/models/Calendar;"
REQUIRED=(accountName accountType color id isDefault isReadOnly name ownerAccount)

BLOCK=$(grep -A60 "Class descriptor.*$CLASS" "$WORK/all.txt" || true)
[ -n "$BLOCK" ] || { echo "FAIL: $CLASS not found in the APK at all — the keep rule for com.builttoroam.devicecalendar is missing."; exit 1; }

missing=()
for f in "${REQUIRED[@]}"; do
  echo "$BLOCK" | grep -q "name          : '$f'" || missing+=("$f")
done

if [ ${#missing[@]} -ne 0 ]; then
  echo "FAIL: R8 renamed these Calendar fields: ${missing[*]}"
  echo "      Gson populates them by name, so the calendar list will come back"
  echo "      empty on release builds. Check android/app/proguard-rules.pro."
  exit 1
fi

echo "OK: all ${#REQUIRED[@]} device_calendar Calendar fields survive R8 unobfuscated."
echo "    ($APK)"
