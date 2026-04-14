#!/usr/bin/env bash
# Idempotently install scripts/cmux-clang-wrapper.sh as a custom Xcode
# toolchain so that xcodebuild routes its `clang -v -E -dM -x c -c /dev/null`
# spec discovery probe through the wrapper.
#
# See scripts/cmux-clang-wrapper.sh for the underlying SwiftBuild deadlock
# this works around. reload.sh calls this script and then sets
#   TOOLCHAINS=com.cmux.clang-wrapper
# before invoking xcodebuild. Once installed the toolchain bundle is reused
# across runs and across concurrent builds.
#
# This script is intentionally fast: it only does work when the wrapper file,
# Info.plist, or mirrored Xcode toolchain source changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_WRAPPER="$SCRIPT_DIR/cmux-clang-wrapper.sh"

if [[ ! -x "$SOURCE_WRAPPER" ]]; then
  echo "install-clang-wrapper: missing $SOURCE_WRAPPER" >&2
  exit 1
fi

# Resolve the active Xcode toolchain whose binaries we will mirror via
# symlinks. Honoring DEVELOPER_DIR matches what `xcrun` and xcodebuild see.
DEVELOPER_DIR_RESOLVED="${DEVELOPER_DIR:-}"
if [[ -z "$DEVELOPER_DIR_RESOLVED" ]]; then
  DEVELOPER_DIR_RESOLVED="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
fi
if [[ -z "$DEVELOPER_DIR_RESOLVED" ]]; then
  DEVELOPER_DIR_RESOLVED="/Applications/Xcode.app/Contents/Developer"
fi
if [[ ! -d "$DEVELOPER_DIR_RESOLVED" ]]; then
  echo "install-clang-wrapper: cannot find developer dir $DEVELOPER_DIR_RESOLVED" >&2
  exit 1
fi
DEVELOPER_DIR_RESOLVED="$(cd "$DEVELOPER_DIR_RESOLVED" && pwd -P)"
XCODE_DEFAULT_BIN="$DEVELOPER_DIR_RESOLVED/Toolchains/XcodeDefault.xctoolchain/usr/bin"

if [[ ! -d "$XCODE_DEFAULT_BIN" ]]; then
  echo "install-clang-wrapper: cannot find $XCODE_DEFAULT_BIN" >&2
  exit 1
fi

TOOLCHAIN_ID="com.cmux.clang-wrapper"
TOOLCHAIN_NAME="cmux clang wrapper"
TOOLCHAIN_DIR="$HOME/Library/Developer/Toolchains/cmux-clang-wrapper.xctoolchain"
TOOLCHAIN_USR="$TOOLCHAIN_DIR/usr"
TOOLCHAIN_BIN="$TOOLCHAIN_USR/bin"
TOOLCHAIN_PLIST="$TOOLCHAIN_DIR/Info.plist"
WRAPPED_CLANG="$TOOLCHAIN_BIN/clang"
XCODE_DEFAULT_USR="$DEVELOPER_DIR_RESOLVED/Toolchains/XcodeDefault.xctoolchain/usr"
TOOLCHAIN_BIN_SOURCE_FILE="$TOOLCHAIN_DIR/.xcode-default-bin-source"

mkdir -p "$TOOLCHAIN_BIN"

# Symlink usr/{include,lib,libexec,share} as whole-directory pointers back
# to XcodeDefault so SwiftBuild can find libclang.dylib, docc/features.json,
# and the rest of the toolchain payload. Only usr/bin needs per-file
# treatment because we override clang there.
for sub in include lib libexec share; do
  src_sub="$XCODE_DEFAULT_USR/$sub"
  dest_sub="$TOOLCHAIN_USR/$sub"
  [[ -e "$src_sub" ]] || continue
  if [[ -L "$dest_sub" ]]; then
    current="$(/usr/bin/readlink "$dest_sub" || true)"
    if [[ "$current" == "$src_sub" ]]; then
      continue
    fi
    rm -f "$dest_sub"
  elif [[ -e "$dest_sub" ]]; then
    rm -rf "$dest_sub"
  fi
  ln -s "$src_sub" "$dest_sub"
done

# Write Info.plist if missing or different.
desired_plist=$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>$TOOLCHAIN_ID</string>
	<key>CompatibilityVersion</key>
	<integer>2</integer>
	<key>DisplayName</key>
	<string>$TOOLCHAIN_NAME</string>
	<key>ShortDisplayName</key>
	<string>cmux clang</string>
	<key>Version</key>
	<string>1.0.0</string>
</dict>
</plist>
EOF
)
if [[ ! -f "$TOOLCHAIN_PLIST" ]] || [[ "$(cat "$TOOLCHAIN_PLIST")" != "$desired_plist" ]]; then
  printf '%s\n' "$desired_plist" > "$TOOLCHAIN_PLIST"
fi

# Mirror every binary from XcodeDefault as a symlink, except clang itself
# which we replace with our wrapper. Skip work if the symlink set already
# matches the active Xcode selection.
need_relink=0
xcode_count=$(/bin/ls -1 "$XCODE_DEFAULT_BIN" | /usr/bin/wc -l | tr -d ' ')
toolchain_count=$(/bin/ls -1 "$TOOLCHAIN_BIN" 2>/dev/null | /usr/bin/wc -l | tr -d ' ')
if [[ "$xcode_count" != "$toolchain_count" ]]; then
  need_relink=1
fi
if [[ $need_relink -eq 0 ]]; then
  current_bin_source="$(cat "$TOOLCHAIN_BIN_SOURCE_FILE" 2>/dev/null || true)"
  if [[ "$current_bin_source" != "$XCODE_DEFAULT_BIN" ]]; then
    need_relink=1
  fi
fi

if [[ $need_relink -eq 1 ]]; then
  # Re-create the symlink farm from scratch so switching Xcode versions or
  # renaming tools cannot leave stale links behind.
  /usr/bin/find "$TOOLCHAIN_BIN" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  for src in "$XCODE_DEFAULT_BIN"/*; do
    name="$(basename "$src")"
    if [[ "$name" == "clang" ]]; then
      continue
    fi
    dest="$TOOLCHAIN_BIN/$name"
    ln -s "$src" "$dest"
  done
  printf '%s\n' "$XCODE_DEFAULT_BIN" > "$TOOLCHAIN_BIN_SOURCE_FILE"
fi

# Install or refresh the clang wrapper. Compare bytes to avoid touching
# the file when nothing changed (keeps mtimes stable for incremental
# builds).
install_wrapper=1
if [[ -f "$WRAPPED_CLANG" ]] && /usr/bin/cmp -s "$SOURCE_WRAPPER" "$WRAPPED_CLANG"; then
  install_wrapper=0
fi
if [[ $install_wrapper -eq 1 ]]; then
  /bin/cp "$SOURCE_WRAPPER" "$WRAPPED_CLANG"
  /bin/chmod +x "$WRAPPED_CLANG"
fi

printf '%s\n' "$TOOLCHAIN_ID"
