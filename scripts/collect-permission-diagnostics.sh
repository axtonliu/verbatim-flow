#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/apps/mac-client/dist/VerbatimFlow.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
RUNTIME_LOG="$HOME/Library/Logs/VerbatimFlow/runtime.log"

MINUTES="${1:-30}"
if ! [[ "$MINUTES" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 [minutes]" >&2
  exit 1
fi

OUT_DIR="$ROOT_DIR/tmp/diagnostics"
mkdir -p "$OUT_DIR"
STAMP="$(date +"%Y%m%d-%H%M%S")"
OUT_FILE="$OUT_DIR/permission-diagnostics-$STAMP.log"

{
  echo "# VerbatimFlow permission diagnostics"
  echo "generated_at_utc: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "user: $(whoami)"
  echo "cwd: $(pwd)"
  echo

  echo "## system"
  sw_vers || true
  uname -a || true
  echo

  echo "## active processes"
  pgrep -fal "VerbatimFlow|verbatim-flow" || echo "(none)"
  echo

  echo "## app bundle"
  if [[ -d "$APP_BUNDLE" ]]; then
    echo "bundle_path: $APP_BUNDLE"
    /usr/bin/codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 || true
    echo
    echo "Info.plist keys:"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c 'Print :NSSpeechRecognitionUsageDescription' "$INFO_PLIST" || true
    if /usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$INFO_PLIST" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$INFO_PLIST" || true
    else
      echo "LSUIElement: (missing)"
    fi
  else
    echo "bundle_missing: $APP_BUNDLE"
  fi
  echo

  echo "## tccd logs (last ${MINUTES}m)"
  /usr/bin/log show --style compact --info --debug --last "${MINUTES}m" --predicate 'process == "tccd" AND (eventMessage CONTAINS[c] "com.axtonliu.verbatimflow" OR eventMessage CONTAINS[c] "VerbatimFlow")' | tail -n 500 || true
  echo

  echo "## app runtime log tail"
  if [[ -f "$RUNTIME_LOG" ]]; then
    tail -n 300 "$RUNTIME_LOG" || true
  else
    echo "runtime_log_missing: $RUNTIME_LOG"
  fi
} > "$OUT_FILE"

echo "[ok] Diagnostic log saved: $OUT_FILE"
