#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/apps/mac-client"
APP_NAME="VerbatimFlow"
APP_BUNDLE="$NATIVE_DIR/dist/${APP_NAME}.app"
EXECUTABLE_NAME="$APP_NAME"
ICON_FILE="$NATIVE_DIR/Resources/AppIcon.icns"
PYTHON_SCRIPTS_DIR="$NATIVE_DIR/python/scripts"
PYTHON_PACKAGE_DIR="$NATIVE_DIR/python/verbatim_flow"
APP_PYTHON_SCRIPTS_DIR="$APP_BUNDLE/Contents/Resources/python/scripts"
APP_PYTHON_PACKAGE_DIR="$APP_BUNDLE/Contents/Resources/python/verbatim_flow"
BUNDLE_ID="${VERBATIMFLOW_BUNDLE_ID:-com.verbatimflow.app}"

cd "$NATIVE_DIR"

swift build -c release --product verbatim-flow --arch arm64 --arch x86_64

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# When building with --arch flags, SPM uses the Apple build system and places
# the universal binary under .build/apple/Products/Release/ instead of
# .build/release/.  Fall back to the latter for single-arch builds.
UNIVERSAL_BIN="$NATIVE_DIR/.build/apple/Products/Release/verbatim-flow"
SINGLE_ARCH_BIN="$NATIVE_DIR/.build/release/verbatim-flow"
if [[ -f "$UNIVERSAL_BIN" ]]; then
  cp "$UNIVERSAL_BIN" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
else
  cp "$SINGLE_ARCH_BIN" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
fi
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

if [[ "${VERBATIMFLOW_REGENERATE_ICON:-0}" == "1" || ! -f "$ICON_FILE" ]]; then
  "$ROOT_DIR/scripts/generate-app-icon.sh"
fi
if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

if [[ -d "$PYTHON_SCRIPTS_DIR" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/Resources/python"
  ditto "$PYTHON_SCRIPTS_DIR" "$APP_PYTHON_SCRIPTS_DIR"
else
  echo "[error] python scripts directory not found: $PYTHON_SCRIPTS_DIR" >&2
  exit 1
fi

if [[ -d "$PYTHON_PACKAGE_DIR" ]]; then
  ditto "$PYTHON_PACKAGE_DIR" "$APP_PYTHON_PACKAGE_DIR"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
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
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
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
xattr -cr "$APP_BUNDLE"
codesign \
  --force \
  --deep \
  --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP_BUNDLE"

# codesign can re-add FinderInfo with the invisible flag; strip it so the
# .app is visible when copied into a DMG or opened in Finder.
xattr -d com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true

echo "[info] signature requirement:"
codesign -d -r- "$APP_BUNDLE" 2>&1 | tail -n 1

echo "[ok] Built app bundle: $APP_BUNDLE"
echo "[hint] Launch with: open '$APP_BUNDLE'"
