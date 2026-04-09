#!/bin/bash
# Build and install to both simulator and connected iPhone (if available)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR/ios"

SIMULATOR_ONLY=0
TAG=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --simulator-only|--sim-only)
            SIMULATOR_ONLY=1
            ;;
        --tag)
            TAG="$2"
            shift
            ;;
        --tag=*)
            TAG="${1#--tag=}"
            ;;
    esac
    shift
done

DERIVED_DATA_PATH="build"
if [ -n "$TAG" ]; then
    DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData/cmux-$TAG"
fi

# Tagged build identity
BUNDLE_ID="dev.cmux.app.dev"
APP_NAME="cmux DEV"
if [ -n "$TAG" ]; then
    SANITIZED_TAG=$(echo "$TAG" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/./g; s/^\.+//; s/\.+$//; s/\.+/./g')
    BUNDLE_ID="dev.cmux.app.dev.${SANITIZED_TAG}"
    APP_NAME="cmux DEV ${TAG}"
fi

# Discover wsPort from macOS daemon's .wsport file
WS_PORT=""
if [ -n "$TAG" ]; then
    TAG_SLUG=$(echo "$TAG" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')
    WSPORT_FILE="/tmp/cmux-debug-${TAG_SLUG}.wsport"
    if [ -f "$WSPORT_FILE" ]; then
        WS_PORT=$(cat "$WSPORT_FILE")
        echo "🔗 Found macOS daemon wsPort: $WS_PORT (from $WSPORT_FILE)"
    fi
fi

LOCAL_CONFIG_SOURCE="$PROJECT_DIR/ios/Sources/Config/LocalConfig.plist"

source "$SCRIPT_DIR/common.sh"

ensure_ghosttykit() {
    local ghostty_dir="$PROJECT_DIR/ghostty"
    local local_xcframework="$ghostty_dir/macos/GhosttyKit.xcframework"
    local local_sha_stamp="$local_xcframework/.ghostty_sha"
    local cache_root="${CMUX_GHOSTTYKIT_CACHE_DIR:-$HOME/.cache/cmux/ghosttykit}"
    local ghostty_sha
    ghostty_sha="$(git -C "$ghostty_dir" rev-parse HEAD)"
    local ghostty_short_sha
    ghostty_short_sha="$(git -C "$ghostty_dir" rev-parse --short HEAD)"
    local ghostty_base_version
    ghostty_base_version="$(awk -F'\"' '/.version = / { print $2; exit }' "$ghostty_dir/build.zig.zon")"
    local ghostty_version_string="${ghostty_base_version}+${ghostty_short_sha}"
    local cache_dir="$cache_root/$ghostty_sha"
    local cache_xcframework="$cache_dir/GhosttyKit.xcframework"
    local link_path="$PROJECT_DIR/GhosttyKit.xcframework"

    mkdir -p "$cache_root"

    if [ ! -d "$cache_xcframework" ]; then
        local local_sha=""
        if [ -f "$local_sha_stamp" ]; then
            local_sha="$(cat "$local_sha_stamp")"
        fi

        if [ ! -d "$local_xcframework" ] || [ "$local_sha" != "$ghostty_sha" ]; then
            echo "🔧 Building GhosttyKit.xcframework for ghostty $ghostty_sha..."
            (
                cd "$ghostty_dir"
                zig build \
                    -Demit-xcframework=true \
                    -Doptimize=ReleaseFast \
                    -Dversion-string="$ghostty_version_string"
            )
            echo "$ghostty_sha" > "$local_sha_stamp"
        else
            echo "🔧 Reusing local GhosttyKit.xcframework for ghostty $ghostty_sha..."
        fi

        if [ ! -d "$local_xcframework" ]; then
            echo "GhosttyKit.xcframework missing at $local_xcframework" >&2
            exit 1
        fi

        local tmp_dir
        tmp_dir="$(mktemp -d "$cache_root/.ghosttykit-tmp.XXXXXX")"
        mkdir -p "$cache_dir"
        cp -R "$local_xcframework" "$tmp_dir/GhosttyKit.xcframework"
        rm -rf "$cache_xcframework"
        mv "$tmp_dir/GhosttyKit.xcframework" "$cache_xcframework"
        rmdir "$tmp_dir"
        echo "🔧 Cached GhosttyKit.xcframework at $cache_xcframework"
    fi

    if [ "$(readlink "$link_path" 2>/dev/null || true)" != "$cache_xcframework" ]; then
        echo "🔧 Linking GhosttyKit.xcframework -> $cache_xcframework"
        ln -sfn "$cache_xcframework" "$link_path"
    fi
}

ensure_ghosttykit

xcodegen generate

# Build for simulator
echo "🖥️  Building for simulator..."
EXTRA_SETTINGS=()
if [ "$BUNDLE_ID" != "dev.cmux.app.dev" ]; then
    EXTRA_SETTINGS+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID")
    EXTRA_SETTINGS+=("INFOPLIST_KEY_CFBundleDisplayName=$APP_NAME")
fi
xcodebuild -scheme cmux -sdk iphonesimulator -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "${EXTRA_SETTINGS[@]}" \
    -quiet

SIM_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/cmux DEV.app"
copy_local_config_if_present "$SIM_APP_PATH" "$LOCAL_CONFIG_SOURCE"

# Embed wsPort if discovered
if [ -n "$WS_PORT" ] && [ -d "$SIM_APP_PATH" ]; then
    printf '%s' "$WS_PORT" > "$SIM_APP_PATH/debug-ws-port"
fi

echo "📲 Installing on simulator(s)..."
# Install and launch on ALL booted simulators
BOOTED_SIMS=$(xcrun simctl list devices | grep "Booted" | grep -oE '[A-F0-9-]{36}')
if [ -n "$BOOTED_SIMS" ]; then
    for SIM_ID in $BOOTED_SIMS; do
        SIM_NAME=$(xcrun simctl list devices | grep "$SIM_ID" | sed 's/ (.*//')
        echo "  → $SIM_NAME"
        xcrun simctl install "$SIM_ID" "$SIM_APP_PATH" 2>/dev/null || true
        xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
    done
else
    echo "  ⚠️  No booted simulators found"
fi

if [ "$SIMULATOR_ONLY" -eq 1 ]; then
    echo "✅ Done! (simulator only)"
    exit 0
fi

# Check for connected device (may appear as "offline" if the phone is locked/untrusted).
DEVICE_ID=$(xcrun xctrace list devices 2>&1 | awk '
    /^== Devices ==/ { in_devices = 1; next }
    /^==/ { in_devices = 0 }
    in_devices { print }
' | grep -E "iPhone.*\\([0-9]+\\.[0-9]+(\\.[0-9]+)?\\)" | head -1 | grep -oE '\([A-F0-9-]+\)' | tr -d '()')

if [ -n "$DEVICE_ID" ]; then
    DEVICE_NAME=$(xcrun xctrace list devices 2>&1 | grep "$DEVICE_ID" | sed 's/ ([0-9].*//')
    echo "📱 Building for $DEVICE_NAME..."

    xcodebuild -scheme cmux -configuration Debug \
        -destination "id=$DEVICE_ID" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        "${EXTRA_SETTINGS[@]}" \
        -allowProvisioningUpdates \
        -allowProvisioningDeviceRegistration \
        -quiet

    DEVICE_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/cmux DEV.app"
    copy_local_config_if_present "$DEVICE_APP_PATH" "$LOCAL_CONFIG_SOURCE"
    rewrite_localhost_for_device "$DEVICE_APP_PATH/LocalConfig.plist"
    embed_debug_relay_for_device "$DEVICE_APP_PATH"

    # Embed wsPort if discovered
    if [ -n "$WS_PORT" ] && [ -d "$DEVICE_APP_PATH" ]; then
        printf '%s' "$WS_PORT" > "$DEVICE_APP_PATH/debug-ws-port"
    fi

    echo "📲 Installing on device..."
    xcrun devicectl device install app --device "$DEVICE_ID" "$DEVICE_APP_PATH"

    echo "🚀 Launching on device..."
    if ! xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"; then
        echo "⚠️  Could not launch app. If the device is locked, unlock it and open cmux manually."
    fi
else
    OFFLINE_DEVICE_ID=$(xcrun xctrace list devices 2>&1 | awk '
        /^== Devices Offline ==/ { in_devices = 1; next }
        /^==/ { in_devices = 0 }
        in_devices { print }
    ' | grep -E "iPhone.*\\([0-9]+\\.[0-9]+(\\.[0-9]+)?\\)" | head -1 | grep -oE '\([A-F0-9-]+\)' | tr -d '()')

    if [ -n "$OFFLINE_DEVICE_ID" ]; then
        OFFLINE_DEVICE_NAME=$(xcrun xctrace list devices 2>&1 | grep "$OFFLINE_DEVICE_ID" | sed 's/ ([0-9].*//')
        echo "⚠️  Found $OFFLINE_DEVICE_NAME, but it is currently unavailable/offline."
        echo "   Unlock the device and make sure it is trusted, then re-run this script."
    else
        echo "ℹ️  No iPhone connected, skipping device install"
    fi
fi

echo "✅ Done!"
