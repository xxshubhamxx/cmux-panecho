#!/bin/sh
set -eu

log() {
  printf '%s\n' "$*" >&2
}

resolve_codesign_identity() {
  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$EXPANDED_CODE_SIGN_IDENTITY"
    return 0
  fi
  printf '%s\n' -
}

codesign_item() {
  path="$1"
  identifier="${2:-}"
  sign_identity="$(resolve_codesign_identity)"

  if [ ! -e "$path" ]; then
    return 0
  fi

  /usr/bin/codesign --remove-signature "$path" >/dev/null 2>&1 || true

  set -- /usr/bin/codesign --force --sign "$sign_identity" --timestamp=none
  if [ -n "$identifier" ]; then
    set -- "$@" --identifier "$identifier"
  fi
  "$@" "$path"
}

helper_bundle_name() {
  source_name="$1"
  case "$source_name" in
    "cefclient Helper.app")
      printf '%s Helper.app\n' "$EXECUTABLE_NAME"
      ;;
    "cefclient Helper (Alerts).app")
      printf '%s Helper (Alerts).app\n' "$EXECUTABLE_NAME"
      ;;
    "cefclient Helper (GPU).app")
      printf '%s Helper (GPU).app\n' "$EXECUTABLE_NAME"
      ;;
    "cefclient Helper (Plugin).app")
      printf '%s Helper (Plugin).app\n' "$EXECUTABLE_NAME"
      ;;
    "cefclient Helper (Renderer).app")
      printf '%s Helper (Renderer).app\n' "$EXECUTABLE_NAME"
      ;;
    *)
      printf '%s\n' "$source_name"
      ;;
  esac
}

helper_bundle_identifier() {
  helper_name="$1"
  case "$helper_name" in
    *" (Plugin).app")
      printf '%s.helper.plugin\n' "$PRODUCT_BUNDLE_IDENTIFIER"
      ;;
    *" (Renderer).app")
      printf '%s.helper.renderer\n' "$PRODUCT_BUNDLE_IDENTIFIER"
      ;;
    *" (Alerts).app")
      printf '%s.helper.alerts\n' "$PRODUCT_BUNDLE_IDENTIFIER"
      ;;
    *)
      printf '%s.helper\n' "$PRODUCT_BUNDLE_IDENTIFIER"
      ;;
  esac
}

plist_set() {
  plist_path="$1"
  key="$2"
  type="$3"
  value="$4"

  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist_path" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$plist_path" >/dev/null 2>&1 \
    || true
}

slugify_identifier_component() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/./g; s/^\.+//; s/\.+$//; s/\.\.+/./g'
}

if [ "${CMUX_CEF_DISABLE_PACKAGING:-0}" = "1" ]; then
  log "CEF packaging disabled by CMUX_CEF_DISABLE_PACKAGING=1"
  exit 0
fi

APP_CONTENTS_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}"
APP_FRAMEWORKS_DIR="${APP_CONTENTS_DIR}/Frameworks"
CEF_RUNTIME_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/CEFRuntime"
CEF_MANIFEST_PATH="${CEF_RUNTIME_DIR}/runtime-manifest.json"

mkdir -p "$APP_FRAMEWORKS_DIR"
mkdir -p "$CEF_RUNTIME_DIR"

rm -rf "$APP_FRAMEWORKS_DIR/Chromium Embedded Framework.framework"
find "$APP_FRAMEWORKS_DIR" -maxdepth 1 -type d -name '*Helper*.app' -exec rm -rf {} +
rm -rf "$CEF_RUNTIME_DIR/Frameworks"

resolve_bundle_framework_dir() {
  bundle="$1"
  if [ -d "$bundle/Contents/Frameworks" ]; then
    printf '%s\n' "$bundle/Contents/Frameworks"
    return 0
  fi
  return 1
}

resolve_framework_dir() {
  root="$1"

  if [ -d "$root/Chromium Embedded Framework.framework" ]; then
    printf '%s\n' "$root"
    return 0
  fi

  if [ -d "$root/Release/Chromium Embedded Framework.framework" ]; then
    printf '%s\n' "$root/Release"
    return 0
  fi

  if [ -d "$root/Contents/Frameworks/Chromium Embedded Framework.framework" ]; then
    printf '%s\n' "$root/Contents/Frameworks"
    return 0
  fi

  return 1
}

SOURCE_FRAMEWORKS_DIR=""
SOURCE_DESCRIPTION=""

if [ -n "${CMUX_CEF_APP_BUNDLE:-}" ] && [ -d "${CMUX_CEF_APP_BUNDLE}" ]; then
  SOURCE_FRAMEWORKS_DIR="$(resolve_bundle_framework_dir "${CMUX_CEF_APP_BUNDLE}" || true)"
  SOURCE_DESCRIPTION="env:CMUX_CEF_APP_BUNDLE"
fi

if [ -z "$SOURCE_FRAMEWORKS_DIR" ] && [ -n "${CMUX_CEF_FRAMEWORK_DIR:-}" ] && [ -d "${CMUX_CEF_FRAMEWORK_DIR}" ]; then
  SOURCE_FRAMEWORKS_DIR="$(resolve_framework_dir "${CMUX_CEF_FRAMEWORK_DIR}" || true)"
  SOURCE_DESCRIPTION="env:CMUX_CEF_FRAMEWORK_DIR"
fi

if [ -z "$SOURCE_FRAMEWORKS_DIR" ] && [ -n "${CMUX_CEF_SDK_ROOT:-}" ] && [ -d "${CMUX_CEF_SDK_ROOT}" ]; then
  SOURCE_FRAMEWORKS_DIR="$(resolve_framework_dir "${CMUX_CEF_SDK_ROOT}" || true)"
  SOURCE_DESCRIPTION="env:CMUX_CEF_SDK_ROOT"
fi

DEFAULT_CLIENT_BUNDLE="$HOME/Library/Caches/cmux-cef-probe/cef_binary_146.0.5+g4db0d88+chromium-146.0.7680.65_macosarm64_beta_client/Release/cefclient.app"
if [ -z "$SOURCE_FRAMEWORKS_DIR" ] && [ -d "$DEFAULT_CLIENT_BUNDLE" ]; then
  SOURCE_FRAMEWORKS_DIR="$(resolve_bundle_framework_dir "$DEFAULT_CLIENT_BUNDLE" || true)"
  SOURCE_DESCRIPTION="cache:cmux-cef-probe"
fi

DEFAULT_SDK_ROOT="/tmp/cef-sdk/cef_binary_146.0.5+g4db0d88+chromium-146.0.7680.65_macosarm64_beta_minimal"
if [ -z "$SOURCE_FRAMEWORKS_DIR" ] && [ -d "$DEFAULT_SDK_ROOT" ]; then
  SOURCE_FRAMEWORKS_DIR="$(resolve_framework_dir "$DEFAULT_SDK_ROOT" || true)"
  SOURCE_DESCRIPTION="cache:/tmp/cef-sdk"
fi

if [ -z "$SOURCE_FRAMEWORKS_DIR" ]; then
  log "CEF packaging skipped, no runtime source found"
  exit 0
fi

FRAMEWORK_SRC="$SOURCE_FRAMEWORKS_DIR/Chromium Embedded Framework.framework"
if [ ! -d "$FRAMEWORK_SRC" ]; then
  log "CEF packaging skipped, missing framework at $FRAMEWORK_SRC"
  exit 0
fi

FRAMEWORK_DEST="$APP_FRAMEWORKS_DIR/Chromium Embedded Framework.framework"
FRAMEWORK_VERSION_DIR="$FRAMEWORK_DEST/Versions/A"
mkdir -p "$FRAMEWORK_VERSION_DIR"

rsync -a "$FRAMEWORK_SRC/" "$FRAMEWORK_VERSION_DIR/"
rm -rf "$FRAMEWORK_VERSION_DIR/_CodeSignature"

ln -sfn A "$FRAMEWORK_DEST/Versions/Current"
ln -sfn "Versions/Current/Chromium Embedded Framework" "$FRAMEWORK_DEST/Chromium Embedded Framework"
ln -sfn "Versions/Current/Libraries" "$FRAMEWORK_DEST/Libraries"
ln -sfn "Versions/Current/Resources" "$FRAMEWORK_DEST/Resources"
log "CEF packaging copied framework from $SOURCE_DESCRIPTION"
codesign_item "$FRAMEWORK_DEST" "org.cef.framework"

find "$SOURCE_FRAMEWORKS_DIR" -maxdepth 1 -type d -name '*Helper*.app' | while IFS= read -r helper_app; do
  source_name="$(basename "$helper_app")"
  dest_name="$(helper_bundle_name "$source_name")"
  dest_app="$APP_FRAMEWORKS_DIR/$dest_name"
  rsync -a "$helper_app/" "$dest_app/"

  info_plist="$dest_app/Contents/Info.plist"
  old_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist" 2>/dev/null || true)"
  new_executable="${dest_name%.app}"
  if [ -n "$old_executable" ] && [ "$old_executable" != "$new_executable" ] && [ -f "$dest_app/Contents/MacOS/$old_executable" ]; then
    mv "$dest_app/Contents/MacOS/$old_executable" "$dest_app/Contents/MacOS/$new_executable"
  fi

  plist_set "$info_plist" CFBundleExecutable string "$new_executable"
  plist_set "$info_plist" CFBundleName string "$new_executable"
  plist_set "$info_plist" CFBundleDisplayName string "$new_executable"
  helper_identifier="$(helper_bundle_identifier "$dest_name")"
  plist_set "$info_plist" CFBundleIdentifier string "$helper_identifier"

  codesign_item "$dest_app" "$helper_identifier"

  log "CEF packaging copied helper $source_name -> $dest_name"
done

HELPER_JSON="$(
  find "$APP_FRAMEWORKS_DIR" -maxdepth 1 -type d -name '*Helper*.app' -exec basename {} \; \
    | sort \
    | awk 'BEGIN { first = 1; printf "[" } NF { if (!first) printf ","; first = 0; gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "\"../Frameworks/%s\"", $0 } END { printf "]" }'
)"
cat > "$CEF_MANIFEST_PATH" <<EOF
{
  "sourceDescription": "$(printf '%s' "$SOURCE_DESCRIPTION" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "frameworkRelativePath": "../Frameworks/Chromium Embedded Framework.framework",
  "helperRelativePaths": ${HELPER_JSON}
}
EOF
log "CEF packaging wrote manifest"

if [ -f "$APP_CONTENTS_DIR/Info.plist" ]; then
  /usr/libexec/PlistBuddy -c "Set :CMUXCEFSource ${SOURCE_DESCRIPTION}" "$APP_CONTENTS_DIR/Info.plist" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add :CMUXCEFSource string ${SOURCE_DESCRIPTION}" "$APP_CONTENTS_DIR/Info.plist" >/dev/null 2>&1 \
    || true
fi
