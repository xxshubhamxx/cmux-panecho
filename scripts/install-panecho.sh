#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
DEFAULT_INSTALL_DIR="/Applications"
USER_INSTALL_DIR="$HOME/Applications"
BUILD_FROM_SOURCE=0
EXPLICIT_SOURCE=""

usage() {
  cat <<'EOF'
Usage: ./scripts/install-panecho.sh [options] [-- build-args...]

Options:
  --build-from-source   Force a local source build before installing
  --source PATH_OR_URL  Install from a local Panecho.app/.dmg/.zip or a downloadable URL
  -h, --help            Show this help text

Without --build-from-source, the installer tries this order:
  1. --source / PANECHO_APP_SOURCE
  2. an existing local Panecho.app build
  3. a release asset discovered from PANECHO_DOWNLOAD_URL
  4. the current repo's panecho-nightly prerelease asset
  5. the current repo's latest full release asset
  6. a local source build, but only if xcodebuild is already usable
EOF
}

BUILD_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-from-source)
      BUILD_FROM_SOURCE=1
      shift
      ;;
    --source)
      if [[ $# -lt 2 ]]; then
        echo "error: --source requires a path or URL" >&2
        exit 1
      fi
      EXPLICIT_SOURCE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      BUILD_ARGS=("$@")
      break
      ;;
    *)
      BUILD_ARGS+=("$1")
      shift
      ;;
  esac
done

load_env_file() {
  local env_file="$ROOT_DIR/.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

is_url() {
  [[ "$1" =~ ^https?:// ]]
}

usable_xcodebuild() {
  command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1
}

ensure_full_xcode() {
  if [[ ! -d "/Applications/Xcode.app" ]]; then
    cat >&2 <<'EOF'
error: building Panecho from source requires full Xcode.
Install Xcode from the App Store, then rerun ./scripts/install-panecho.sh --build-from-source.
EOF
    exit 1
  fi

  if command -v xcode-select >/dev/null 2>&1; then
    local current_dir
    current_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$current_dir" != "$EXPECTED_DEVELOPER_DIR" ]]; then
      echo "==> Selecting full Xcode..."
      sudo xcode-select --switch "$EXPECTED_DEVELOPER_DIR"
    fi
  fi

  if ! xcodebuild -version >/dev/null 2>&1; then
    echo "==> Finishing first-launch Xcode setup..."
    sudo xcodebuild -runFirstLaunch
  fi

  xcodebuild -version >/dev/null 2>&1
}

ensure_brew_formula() {
  local command_name="$1"
  local formula_name="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    cat >&2 <<EOF
error: $command_name is required but Homebrew is not installed.
Install Homebrew, then rerun ./scripts/install-panecho.sh.
EOF
    exit 1
  fi

  echo "==> Installing $formula_name..."
  brew install "$formula_name"
}

resolve_install_dir() {
  if [[ -n "${PANECHO_INSTALL_DIR:-}" ]]; then
    printf '%s\n' "$PANECHO_INSTALL_DIR"
    return
  fi

  if [[ -w "$DEFAULT_INSTALL_DIR" ]]; then
    printf '%s\n' "$DEFAULT_INSTALL_DIR"
  else
    printf '%s\n' "$USER_INSTALL_DIR"
  fi
}

install_app_bundle() {
  local app_path="$1"
  local install_dir="$2"
  local destination

  destination="$install_dir/Panecho.app"

  mkdir -p "$install_dir"
  rm -rf "$destination"
  ditto "$app_path" "$destination"

  echo "==> Installed Panecho to $destination"

  if [[ "${PANECHO_SKIP_OPEN:-0}" != "1" ]]; then
    open "$destination"
  fi
}

download_to_temp() {
  local source_url="$1"
  local suffix="${source_url##*/}"
  local temp_path
  temp_path="$(mktemp "${TMPDIR:-/tmp}/panecho-download.XXXXXX.${suffix##*.}")"
  curl -L --fail --silent --show-error "$source_url" -o "$temp_path"
  printf '%s\n' "$temp_path"
}

find_local_app_build() {
  local configuration="${PANECHO_CONFIGURATION:-Release}"
  local derived_data_path="${PANECHO_DERIVED_DATA_PATH:-$ROOT_DIR/build/panecho-derived-data}"
  local built_app_path="$derived_data_path/Build/Products/$configuration/Panecho.app"
  if [[ -d "$built_app_path" ]]; then
    printf '%s\n' "$built_app_path"
    return 0
  fi

  find "$ROOT_DIR/build" -type d -name 'Panecho.app' -print -quit 2>/dev/null || true
}

github_repo_from_origin() {
  local remote_url
  remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$remote_url" ]]; then
    return 1
  fi
  python3 - "$remote_url" <<'PY'
import re, sys
url = sys.argv[1].strip()
patterns = [
    r'^https://github\.com/([^/]+)/([^/.]+?)(?:\.git)?$',
    r'^git@github\.com:([^/]+)/([^/.]+?)(?:\.git)?$',
]
for pattern in patterns:
    m = re.match(pattern, url)
    if m:
        print(f"{m.group(1)}/{m.group(2)}")
        raise SystemExit(0)
raise SystemExit(1)
PY
}

discover_release_asset_url() {
  if [[ -n "${PANECHO_DOWNLOAD_URL:-}" ]]; then
    printf '%s\n' "$PANECHO_DOWNLOAD_URL"
    return 0
  fi

  local repo
  repo="${PANECHO_RELEASE_REPO:-$(github_repo_from_origin 2>/dev/null || true)}"
  if [[ -z "$repo" ]]; then
    return 1
  fi

  local release_tag
  release_tag="${PANECHO_RELEASE_TAG:-panecho-nightly}"

  if python3 - "$repo" "$release_tag" <<'PY'
import json, re, sys, urllib.request
repo = sys.argv[1]
tag = sys.argv[2]
url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "panecho-installer"})
try:
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.load(response)
except Exception:
    raise SystemExit(1)

asset_pattern = re.compile(r'^panecho.*\.(dmg|zip)$', re.IGNORECASE)
for asset in payload.get("assets", []):
    name = asset.get("name", "")
    if asset_pattern.match(name):
        print(asset.get("browser_download_url", ""))
        raise SystemExit(0)
raise SystemExit(1)
PY
  then
    return 0
  fi

  python3 - "$repo" <<'PY'
import json, re, sys, urllib.request
repo = sys.argv[1]
url = f"https://api.github.com/repos/{repo}/releases/latest"
request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "panecho-installer"})
try:
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.load(response)
except Exception:
    raise SystemExit(1)

asset_pattern = re.compile(r'^panecho.*\.(dmg|zip)$', re.IGNORECASE)
for asset in payload.get("assets", []):
    name = asset.get("name", "")
    if asset_pattern.match(name):
        print(asset.get("browser_download_url", ""))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

resolve_install_source() {
  if [[ -n "$EXPLICIT_SOURCE" ]]; then
    printf '%s\n' "$EXPLICIT_SOURCE"
    return 0
  fi

  if [[ -n "${PANECHO_APP_SOURCE:-}" ]]; then
    printf '%s\n' "$PANECHO_APP_SOURCE"
    return 0
  fi

  local local_build
  local_build="$(find_local_app_build)"
  if [[ -n "$local_build" ]]; then
    printf '%s\n' "$local_build"
    return 0
  fi

  discover_release_asset_url 2>/dev/null || true
}

extract_app_from_zip() {
  local zip_path="$1"
  local extract_dir
  extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/panecho-zip.XXXXXX")"
  ditto -xk "$zip_path" "$extract_dir"
  find "$extract_dir" -type d -name 'Panecho.app' -print -quit 2>/dev/null \
    || find "$extract_dir" -type d -name '*.app' -print -quit 2>/dev/null
}

extract_app_from_dmg() {
  local dmg_path="$1"
  local mount_dir
  mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/panecho-dmg.XXXXXX")"
  local device
  device="$(hdiutil attach "$dmg_path" -nobrowse -readonly -mountpoint "$mount_dir" 2>/dev/null | awk 'NR==1 {print $1}')"
  if [[ -z "$device" ]]; then
    rm -rf "$mount_dir"
    return 1
  fi
  local app_path
  app_path="$(find "$mount_dir" -type d -name 'Panecho.app' -print -quit 2>/dev/null \
    || find "$mount_dir" -type d -name '*.app' -print -quit 2>/dev/null)"
  if [[ -z "$app_path" ]]; then
    hdiutil detach "$device" -quiet >/dev/null 2>&1 || true
    rm -rf "$mount_dir"
    return 1
  fi
  local staged_dir
  staged_dir="$(mktemp -d "${TMPDIR:-/tmp}/panecho-app.XXXXXX")"
  ditto "$app_path" "$staged_dir/Panecho.app"
  hdiutil detach "$device" -quiet >/dev/null 2>&1 || true
  rm -rf "$mount_dir"
  printf '%s\n' "$staged_dir/Panecho.app"
}

install_from_source() {
  local source="$1"
  local install_dir="$2"
  local local_source="$source"

  if is_url "$source"; then
    echo "==> Downloading Panecho..."
    local_source="$(download_to_temp "$source")"
  fi

  if [[ -d "$local_source" && "$local_source" == *.app ]]; then
    install_app_bundle "$local_source" "$install_dir"
    return 0
  fi

  if [[ -f "$local_source" && "$local_source" == *.zip ]]; then
    local app_path
    app_path="$(extract_app_from_zip "$local_source")"
    if [[ -n "$app_path" && -d "$app_path" ]]; then
      install_app_bundle "$app_path" "$install_dir"
      return 0
    fi
  fi

  if [[ -f "$local_source" && "$local_source" == *.dmg ]]; then
    local app_path
    app_path="$(extract_app_from_dmg "$local_source")"
    if [[ -n "$app_path" && -d "$app_path" ]]; then
      install_app_bundle "$app_path" "$install_dir"
      return 0
    fi
  fi

  echo "error: could not install Panecho from $source" >&2
  echo "Supported sources: Panecho.app, .zip, .dmg, or a direct download URL." >&2
  exit 1
}

build_and_install_from_source() {
  ensure_full_xcode
  ensure_brew_formula zig zig
  ensure_brew_formula go go

  echo "==> Running setup..."
  ./scripts/setup.sh

  echo "==> Building Panecho..."
  ./scripts/build-panecho.sh "${BUILD_ARGS[@]}"

  local built_app_path
  built_app_path="$(find_local_app_build)"
  if [[ -z "$built_app_path" || ! -d "$built_app_path" ]]; then
    echo "error: build finished but no Panecho.app was found" >&2
    exit 1
  fi

  local install_dir
  install_dir="$(resolve_install_dir)"
  install_app_bundle "$built_app_path" "$install_dir"
}

main() {
  cd "$ROOT_DIR"
  load_env_file
  if [[ "$BUILD_FROM_SOURCE" == "1" ]]; then
    build_and_install_from_source
    return
  fi

  local install_source
  install_source="$(resolve_install_source)"
  if [[ -n "$install_source" ]]; then
    local install_dir
    install_dir="$(resolve_install_dir)"
    install_from_source "$install_source" "$install_dir"
    return
  fi

  if usable_xcodebuild; then
    build_and_install_from_source
    return
  fi

  cat >&2 <<'EOF'
error: no prebuilt Panecho app was found to install.

Tried:
  - PANECHO_APP_SOURCE / --source
  - an existing local Panecho.app build
  - a Panecho .dmg/.zip release asset from PANECHO_DOWNLOAD_URL
  - the current GitHub repo's panecho-nightly prerelease asset
  - the current GitHub repo's latest full release asset

Next steps:
  - publish a Panecho .dmg or .zip and set PANECHO_DOWNLOAD_URL, or
  - run ./scripts/install-panecho.sh --build-from-source on a machine with full Xcode
EOF
  exit 1
}

main
