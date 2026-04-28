#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_INSTALL_DIR="/Applications"
USER_INSTALL_DIR="$HOME/Applications"
DEFAULT_RELEASE_REPO="xxshubhamxx/cmux"
ZIP_SOURCE="${PANECHO_ZIP_SOURCE:-${PANECHO_ZIP_URL:-}}"
RELEASE_REPO="${PANECHO_RELEASE_REPO:-}"
RELEASE_TAG="${PANECHO_RELEASE_TAG:-}"
ASSET_NAME="${PANECHO_ASSET_NAME:-panecho-macos.zip}"
INSTALL_DIR="${PANECHO_INSTALL_DIR:-}"
SKIP_OPEN="${PANECHO_SKIP_OPEN:-0}"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-panecho-prebuilt.sh [options]

Install a prebuilt Panecho ZIP using only built-in macOS tools.
No Xcode, Homebrew, Python, Go, or GitHub CLI is required.

Options:
  --zip PATH_OR_URL     Install from a local panecho ZIP or direct ZIP URL
  --repo OWNER/REPO     GitHub repo that publishes the ZIP asset
  --tag TAG             Release tag to download (default: latest stable, then panecho-nightly fallback)
  --asset NAME          Release asset name (default: panecho-macos.zip)
  --install-dir DIR     Install into DIR instead of /Applications or ~/Applications
  --no-open             Do not launch Panecho after install
  -h, --help            Show this help text

Environment overrides:
  PANECHO_ZIP_SOURCE / PANECHO_ZIP_URL
  PANECHO_RELEASE_REPO
  PANECHO_RELEASE_TAG
  PANECHO_ASSET_NAME
  PANECHO_INSTALL_DIR
  PANECHO_SKIP_OPEN=1
EOF
}

error() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  local tool_name="$1"
  command -v "$tool_name" >/dev/null 2>&1 || error "$tool_name is required but was not found"
}

is_url() {
  [[ "$1" =~ ^https?:// ]]
}

infer_release_repo_from_git() {
  command -v git >/dev/null 2>&1 || return 1

  local remote_name
  local remote_url
  for remote_name in fork origin; do
    remote_url="$(git -C "$ROOT_DIR" remote get-url "$remote_name" 2>/dev/null || true)"
    [[ -n "$remote_url" ]] && break
  done
  [[ -n "$remote_url" ]] || return 1

  case "$remote_url" in
    https://github.com/*)
      remote_url="${remote_url#https://github.com/}"
      remote_url="${remote_url%.git}"
      ;;
    git@github.com:*)
      remote_url="${remote_url#git@github.com:}"
      remote_url="${remote_url%.git}"
      ;;
    *)
      return 1
      ;;
  esac

  [[ "$remote_url" == */* ]] || return 1
  printf '%s\n' "$remote_url"
}

resolve_release_repo() {
  if [[ -n "$RELEASE_REPO" ]]; then
    printf '%s\n' "$RELEASE_REPO"
    return 0
  fi

  local inferred_repo
  inferred_repo="$(infer_release_repo_from_git 2>/dev/null || true)"
  if [[ -n "$inferred_repo" ]]; then
    printf '%s\n' "$inferred_repo"
    return 0
  fi

  printf '%s\n' "$DEFAULT_RELEASE_REPO"
}

release_asset_urls() {
  local repo
  repo="$(resolve_release_repo)"

  if [[ -n "$RELEASE_TAG" ]]; then
    printf 'https://github.com/%s/releases/download/%s/%s\n' "$repo" "$RELEASE_TAG" "$ASSET_NAME"
    return 0
  fi

  printf 'https://github.com/%s/releases/latest/download/%s\n' "$repo" "$ASSET_NAME"
  printf 'https://github.com/%s/releases/download/panecho-nightly/%s\n' "$repo" "$ASSET_NAME"
}

resolve_install_dir() {
  if [[ -n "$INSTALL_DIR" ]]; then
    printf '%s\n' "$INSTALL_DIR"
    return 0
  fi

  if [[ -w "$DEFAULT_INSTALL_DIR" ]]; then
    printf '%s\n' "$DEFAULT_INSTALL_DIR"
  else
    printf '%s\n' "$USER_INSTALL_DIR"
  fi
}

download_if_needed() {
  local source="$1"
  local destination_path="$2"
  if ! is_url "$source"; then
    [[ -f "$source" ]] || error "ZIP source not found: $source"
    printf '%s\n' "$source"
    return 0
  fi

  echo "==> Downloading Panecho..." >&2
  curl -L --fail --silent --show-error "$source" -o "$destination_path"
  printf '%s\n' "$destination_path"
}

download_release_asset() {
  local destination_path="$1"
  local release_url

  while IFS= read -r release_url; do
    [[ -n "$release_url" ]] || continue
    echo "==> Downloading Panecho from $release_url..." >&2
    if curl -L --fail --silent --show-error "$release_url" -o "$destination_path"; then
      printf '%s\n' "$destination_path"
      return 0
    fi
  done < <(release_asset_urls)

  if [[ -n "$RELEASE_TAG" ]]; then
    error "unable to download release asset $ASSET_NAME from tag $RELEASE_TAG"
  fi
  error "unable to download release asset $ASSET_NAME from the latest Panecho release or panecho-nightly fallback"
}

extract_app_from_zip() {
  local zip_path="$1"
  local extract_dir="$2"
  mkdir -p "$extract_dir"
  ditto -xk "$zip_path" "$extract_dir"

  local app_path
  app_path="$(find "$extract_dir" -type d -name 'Panecho.app' -print -quit 2>/dev/null || true)"
  if [[ -z "$app_path" ]]; then
    app_path="$(find "$extract_dir" -type d -name '*.app' -print -quit 2>/dev/null || true)"
  fi

  [[ -n "$app_path" && -d "$app_path" ]] || error "no .app bundle was found inside $zip_path"
  printf '%s\n' "$app_path"
}

install_app_bundle() {
  local app_path="$1"
  local install_dir="$2"
  local destination="$install_dir/Panecho.app"

  mkdir -p "$install_dir"
  rm -rf "$destination"
  mv "$app_path" "$destination"

  echo "==> Installed Panecho to $destination"

  if [[ "$SKIP_OPEN" != "1" ]]; then
    open "$destination"
  fi
}

main() {
  [[ "$(uname -s)" == "Darwin" ]] || error "this installer only supports macOS"

  require_tool curl
  require_tool ditto
  require_tool find
  require_tool mktemp
  require_tool mv

  local install_dir
  install_dir="$(resolve_install_dir)"
  mkdir -p "$install_dir"

  local stage_dir
  stage_dir="$(mktemp -d "$install_dir/.panecho-install.XXXXXX")"
  trap 'rm -rf "$stage_dir"' EXIT

  local zip_path
  if [[ -n "$ZIP_SOURCE" ]]; then
    zip_path="$(download_if_needed "$ZIP_SOURCE" "$stage_dir/$ASSET_NAME")"
  else
    zip_path="$(download_release_asset "$stage_dir/$ASSET_NAME")"
  fi

  local app_path
  app_path="$(extract_app_from_zip "$zip_path" "$stage_dir/unpacked")"

  install_app_bundle "$app_path" "$install_dir"

  trap - EXIT
  rm -rf "$stage_dir"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip)
      [[ $# -ge 2 ]] || error "--zip requires a path or URL"
      ZIP_SOURCE="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || error "--repo requires OWNER/REPO"
      RELEASE_REPO="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || error "--tag requires a release tag"
      RELEASE_TAG="$2"
      shift 2
      ;;
    --asset)
      [[ $# -ge 2 ]] || error "--asset requires a file name"
      ASSET_NAME="$2"
      shift 2
      ;;
    --install-dir)
      [[ $# -ge 2 ]] || error "--install-dir requires a directory"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --no-open)
      SKIP_OPEN=1
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

main
