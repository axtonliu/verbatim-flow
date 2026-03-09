#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/apps/mac-client"
APP_NAME="VerbatimFlow"
APP_BUNDLE="$NATIVE_DIR/dist/${APP_NAME}.app"
TEMP_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/verbatim-flow-build.XXXXXX")"
SIGNING_APP_BUNDLE="$TEMP_BUILD_DIR/${APP_NAME}.app"
EXECUTABLE_NAME="$APP_NAME"
ICON_FILE="$NATIVE_DIR/Resources/AppIcon.icns"
PYTHON_SCRIPTS_DIR="$NATIVE_DIR/python/scripts"
PYTHON_PACKAGE_DIR="$NATIVE_DIR/python/verbatim_flow"
APP_PYTHON_SCRIPTS_DIR="$APP_BUNDLE/Contents/Resources/python/scripts"
APP_PYTHON_PACKAGE_DIR="$APP_BUNDLE/Contents/Resources/python/verbatim_flow"
BUNDLE_ID="${VERBATIMFLOW_BUNDLE_ID:-com.verbatimflow.app}"
APP_VERSION="0.1.1"
APP_BUILD="2"

cleanup() {
  rm -rf "$TEMP_BUILD_DIR"
}
trap cleanup EXIT

cd "$NATIVE_DIR"

swift build -c release --product verbatim-flow --arch arm64 --arch x86_64

rm -rf "$SIGNING_APP_BUNDLE"
mkdir -p "$SIGNING_APP_BUNDLE/Contents/MacOS"
mkdir -p "$SIGNING_APP_BUNDLE/Contents/Resources"

# When building with --arch flags, SPM uses the Apple build system and places
# the universal binary under .build/apple/Products/Release/ instead of
# .build/release/.  Fall back to the latter for single-arch builds.
UNIVERSAL_BIN="$NATIVE_DIR/.build/apple/Products/Release/verbatim-flow"
SINGLE_ARCH_BIN="$NATIVE_DIR/.build/release/verbatim-flow"
if [[ -f "$UNIVERSAL_BIN" ]]; then
  cp -X "$UNIVERSAL_BIN" "$SIGNING_APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
else
  cp -X "$SINGLE_ARCH_BIN" "$SIGNING_APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
fi
chmod +x "$SIGNING_APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

if [[ "${VERBATIMFLOW_REGENERATE_ICON:-0}" == "1" || ! -f "$ICON_FILE" ]]; then
  "$ROOT_DIR/scripts/generate-app-icon.sh"
fi
if [[ -f "$ICON_FILE" ]]; then
  cp -X "$ICON_FILE" "$SIGNING_APP_BUNDLE/Contents/Resources/AppIcon.icns"
  xattr -c "$SIGNING_APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi
xattr -c "$SIGNING_APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME" 2>/dev/null || true

if [[ -d "$PYTHON_SCRIPTS_DIR" ]]; then
  mkdir -p "$SIGNING_APP_BUNDLE/Contents/Resources/python"
  ditto "$PYTHON_SCRIPTS_DIR" "$SIGNING_APP_BUNDLE/Contents/Resources/python/scripts"
else
  echo "[error] python scripts directory not found: $PYTHON_SCRIPTS_DIR" >&2
  exit 1
fi

if [[ -d "$PYTHON_PACKAGE_DIR" ]]; then
  ditto "$PYTHON_PACKAGE_DIR" "$SIGNING_APP_BUNDLE/Contents/Resources/python/verbatim_flow"
fi

cat > "$SIGNING_APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>VerbatimFlow</string>
  <key>CFBundleExecutable</key>
  <string>VerbatimFlow</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>VerbatimFlow</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>VerbatimFlow needs microphone access for speech transcription.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>VerbatimFlow needs speech recognition access to transcribe audio.</string>
</dict>
</plist>
PLIST

# Remove Finder metadata and apply ad-hoc signature with a stable
# designated requirement (bundle identifier based, not cdhash).
# This prevents Accessibility/Input Monitoring permissions from being
# invalidated on every rebuild.
xattr -cr "$SIGNING_APP_BUNDLE"
codesign \
  --force \
  --deep \
  --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$SIGNING_APP_BUNDLE"

# codesign can re-add FinderInfo with the invisible flag; strip it so the
# .app is visible when copied into a DMG or opened in Finder.
xattr -d com.apple.FinderInfo "$SIGNING_APP_BUNDLE" 2>/dev/null || true

rm -rf "$APP_BUNDLE"
ditto "$SIGNING_APP_BUNDLE" "$APP_BUNDLE"

echo "[info] signature requirement:"
codesign -d -r- "$SIGNING_APP_BUNDLE" 2>&1 | tail -n 1

echo "[ok] Built app bundle: $APP_BUNDLE"
echo "[hint] Launch with: open '$APP_BUNDLE'"
