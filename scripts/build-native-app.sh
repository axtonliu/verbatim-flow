#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/apps/mac-client"
APP_NAME="VerbatimFlow"
APP_BUNDLE="$NATIVE_DIR/dist/${APP_NAME}.app"
EXECUTABLE_NAME="$APP_NAME"

cd "$NATIVE_DIR"

swift build -c release --product verbatim-flow

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$NATIVE_DIR/.build/release/verbatim-flow" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
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
  <key>CFBundleIdentifier</key>
  <string>com.axtonliu.verbatimflow</string>
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

# Remove Finder metadata and apply deterministic ad-hoc signature
# so TCC can consistently identify this bundle.
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - --identifier "com.axtonliu.verbatimflow" "$APP_BUNDLE"

echo "[ok] Built app bundle: $APP_BUNDLE"
echo "[hint] Launch with: open '$APP_BUNDLE'"
