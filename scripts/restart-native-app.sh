#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/apps/mac-client/dist/VerbatimFlow.app"

pkill -f "VerbatimFlow.app/Contents/MacOS/VerbatimFlow" || true
pkill -f "swift run verbatim-flow" || true

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "[error] app bundle missing: $APP_BUNDLE" >&2
  echo "[hint] run ./scripts/build-native-app.sh first" >&2
  exit 1
fi

open "$APP_BUNDLE"
echo "[ok] restarted: $APP_BUNDLE"
