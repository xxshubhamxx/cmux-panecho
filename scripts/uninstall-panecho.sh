#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Panecho.app"
BUNDLE_ID="${PANECHO_BUNDLE_ID:-io.panecho.app}"
INSTALL_DIR="${PANECHO_INSTALL_DIR:-}"
REMOVE_USER_DATA="${PANECHO_REMOVE_USER_DATA:-0}"
REMOVED_ANYTHING=0

usage() {
  cat <<'EOF'
Usage: ./scripts/uninstall-panecho.sh [options]

Remove Panecho.app from macOS.
By default, this removes the app bundle only and keeps user data.

Options:
  --install-dir DIR      Remove Panecho.app from DIR only
  --remove-user-data     Also remove user data, preferences, caches, and saved state
  -h, --help             Show this help text

Environment overrides:
  PANECHO_INSTALL_DIR
  PANECHO_BUNDLE_ID
  PANECHO_REMOVE_USER_DATA=1
EOF
}

error() {
  echo "error: $*" >&2
  exit 1
}

remove_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    rm -rf "$path"
    echo "==> Removed $path"
    REMOVED_ANYTHING=1
  fi
}

quit_app_if_running() {
  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'tell application "Panecho" to quit' >/dev/null 2>&1 || true
  fi
}

remove_app_bundle() {
  if [[ -n "$INSTALL_DIR" ]]; then
    remove_path "$INSTALL_DIR/$APP_NAME"
    return 0
  fi

  remove_path "/Applications/$APP_NAME"
  remove_path "$HOME/Applications/$APP_NAME"
}

remove_user_data() {
  local data_paths=(
    "$HOME/Library/Application Support/Panecho"
    "$HOME/Library/Application Support/$BUNDLE_ID"
    "$HOME/Library/Caches/$BUNDLE_ID"
    "$HOME/Library/HTTPStorages/$BUNDLE_ID"
    "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
    "$HOME/Library/WebKit/$BUNDLE_ID"
  )

  local path
  for path in "${data_paths[@]}"; do
    remove_path "$path"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      [[ $# -ge 2 ]] || error "--install-dir requires a directory"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --remove-user-data)
      REMOVE_USER_DATA=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "unknown argument: $1"
      ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || error "this uninstaller only supports macOS"

quit_app_if_running
remove_app_bundle

if [[ "$REMOVE_USER_DATA" == "1" ]]; then
  remove_user_data
fi

if [[ "$REMOVED_ANYTHING" != "1" ]]; then
  echo "==> Panecho was not found in /Applications or ~/Applications"
else
  if [[ "$REMOVE_USER_DATA" == "1" ]]; then
    echo "==> Panecho and its local user data have been removed"
  else
    echo "==> Panecho has been removed (user data was preserved)"
  fi
fi
