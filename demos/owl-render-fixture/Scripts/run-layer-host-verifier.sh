#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HOST="${OWL_CHROMIUM_HOST:-$HOME/chromium/src/out/Release/Content Shell.app/Contents/MacOS/Content Shell}"
BRIDGE="${OWL_BRIDGE_PATH:-$HOME/chromium/src/out/Release/libowl_fresh_bridge.dylib}"
OUT_DIR="${OWL_LAYER_HOST_RENDER_OUT:-$ROOT_DIR/artifacts/layer-host-latest}"
CHROMIUM_OUT="$(cd "$(dirname "$BRIDGE")" && pwd)"

if [ ! -x "$HOST" ]; then
  echo "Missing Chromium host executable: $HOST" >&2
  exit 1
fi

if [ ! -f "$BRIDGE" ]; then
  echo "Missing OWL bridge dylib: $BRIDGE" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cd "$ROOT_DIR"
DYLD_LIBRARY_PATH="$CHROMIUM_OUT${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  swift run -c release OwlLayerHostVerifier \
    --chromium-host "$HOST" \
    --bridge "$BRIDGE" \
    --output-dir "$OUT_DIR"
