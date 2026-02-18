#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_CLIENT_DIR="$ROOT_DIR/apps/mac-client"

cd "$NATIVE_CLIENT_DIR"
exec swift run verbatim-flow "$@"
