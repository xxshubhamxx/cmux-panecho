#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HOST="${OWL_CHROMIUM_HOST:-$HOME/chromium/src/out/Release/Content Shell.app/Contents/MacOS/Content Shell}"
BRIDGE="${OWL_BRIDGE_PATH:-$HOME/chromium/src/out/Release/libowl_fresh_bridge.dylib}"
OUT_DIR="${OWL_LAYER_HOST_RENDER_OUT:-$ROOT_DIR/artifacts/layer-host-gui-latest}"
TIMEOUT="${OWL_LAYER_HOST_TIMEOUT:-45}"
WAIT_SECONDS="${OWL_LAYER_HOST_WAIT_SECONDS:-140}"
CHROMIUM_OUT="$(cd "$(dirname "$BRIDGE")" && pwd)"
LABEL="com.manaflow.owllayerreal.$$"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STDOUT_LOG="/tmp/owl-layer-real-$$.out"
STDERR_LOG="/tmp/owl-layer-real-$$.err"
UID_VALUE="$(id -u)"
APP_DIR="/tmp/OwlLayerHostVerifier-$LABEL.app"

if [ ! -x "$HOST" ]; then
  echo "Missing Chromium host executable: $HOST" >&2
  exit 1
fi

if [ ! -f "$BRIDGE" ]; then
  echo "Missing OWL bridge dylib: $BRIDGE" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$HOME/Library/LaunchAgents"
rm -f "$STDOUT_LOG" "$STDERR_LOG"

cd "$ROOT_DIR"
swift build -c release --product OwlLayerHostVerifier

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$ROOT_DIR/.build/release/OwlLayerHostVerifier" "$APP_DIR/Contents/MacOS/OwlLayerHostVerifier"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>OwlLayerHostVerifier</string>
  <key>CFBundleIdentifier</key><string>com.manaflow.OwlLayerHostVerifier.run$$</string>
  <key>CFBundleName</key><string>OwlLayerHostVerifier</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSEnvironment</key>
  <dict>
    <key>DYLD_LIBRARY_PATH</key><string>$CHROMIUM_OUT</string>
  </dict>
</dict>
</plist>
PLIST

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-W</string>
    <string>$APP_DIR</string>
    <string>--args</string>
    <string>--chromium-host</string>
    <string>$HOST</string>
    <string>--bridge</string>
    <string>$BRIDGE</string>
    <string>--output-dir</string>
    <string>$OUT_DIR</string>
    <string>--timeout</string>
    <string>$TIMEOUT</string>
PLIST

if [ "${OWL_LAYER_HOST_SKIP_EXAMPLE:-}" = "1" ]; then
  cat >> "$PLIST" <<PLIST
    <string>--skip-example</string>
PLIST
fi
if [ "${OWL_LAYER_HOST_SKIP_CANVAS:-}" = "1" ]; then
  cat >> "$PLIST" <<PLIST
    <string>--skip-canvas</string>
PLIST
fi

cat >> "$PLIST" <<PLIST
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$STDOUT_LOG</string>
  <key>StandardErrorPath</key><string>$STDERR_LOG</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID_VALUE/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_VALUE" "$PLIST"
for ((i = 0; i < WAIT_SECONDS; i++)); do
  if [ -f "$OUT_DIR/summary.json" ]; then
    break
  fi
  sleep 1
done
launchctl bootout "gui/$UID_VALUE/$LABEL" 2>/dev/null || true

echo "== stdout =="
cat "$STDOUT_LOG" 2>/dev/null || true
echo "== stderr =="
cat "$STDERR_LOG" 2>/dev/null || true

if [ ! -f "$OUT_DIR/summary.json" ]; then
  echo "Missing summary in $OUT_DIR" >&2
  exit 1
fi

echo "Artifacts: $OUT_DIR"
