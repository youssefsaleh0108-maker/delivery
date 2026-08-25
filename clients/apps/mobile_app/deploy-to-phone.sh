#!/usr/bin/env bash
# Builds the app and installs it on the attached phone. Run after every change.
#
# --split-per-abi even for a single ABI: the split builds carry an ABI-derived versionCode (arm64
# is 2000 + the base), and the universal build carries the base. Installing a universal over a
# split therefore fails with INSTALL_FAILED_VERSION_DOWNGRADE, which reads like a broken APK and is
# only a numbering artefact. Staying on one shape avoids it entirely.
set -euo pipefail

ADB="${ADB:-/c/Users/Administrator/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
HOST="${PUBLIC_HOST:-94.72.112.156}"
APP="$(cd "$(dirname "$0")" && pwd)"

cd "$APP"

if ! "$ADB" devices | grep -qw device; then
  echo "No phone attached. Plug it in, unlock it, and accept the USB debugging prompt." >&2
  exit 1
fi

echo "Building against $HOST..."
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --dart-define=KEYCLOAK_ISSUER="http://${HOST}:8180/realms/delivery-platform" \
  --dart-define=API_BASE_URL="http://${HOST}:8100" \
  | grep -E 'Built|error' || true

APK=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
[ -f "$APK" ] || { echo "Build produced no APK at $APK" >&2; exit 1; }

echo "Installing..."
# -r keeps the existing data, so a tester does not lose their session on every fix.
"$ADB" install -r "$APK"

echo "Installed: $(stat -c %y "$APK" 2>/dev/null || date)"
