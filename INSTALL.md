## Install Panecho

The shortest path from this repo is:

```bash
./scripts/install-panecho.sh
```

By default, that script tries the simplest install path first:

1. install from `--source` or `PANECHO_APP_SOURCE`
2. install from `xxshubhamxx/cmux` latest `Panecho` release asset
3. fall back to the repo's rolling `panecho-nightly` asset if needed
4. only build from source if `--build-from-source` is explicit

That means once the fork's `panecho-nightly` workflow has published at least one build, the default install path is a single command with no local Xcode or Go requirement:

```bash
./scripts/install-panecho.sh
```

### Verified no-Xcode path for a CLT-only Mac

If `xcode-select -p` points at Command Line Tools instead of full Xcode, use a fork to let GitHub-hosted macOS build the app for you:

1. Push this repo (including `.github/workflows/panecho-nightly.yml`) to your fork's `main` branch.
2. Wait for the GitHub workflow to publish either a full `Panecho` release or the rolling `panecho-nightly` asset.
3. Install without building locally:

```bash
./scripts/install-panecho.sh
```

That path avoids both local full Xcode and a local Go toolchain. The workflow is verified for Apple Silicon and publishes an arm64 `Panecho.app` package for this machine class.

If you want the same experience without cloning the repo first, point the installer at your fork explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/xxshubhamxx/cmux/main/scripts/install-panecho.sh | bash
```

That one-liner targets `xxshubhamxx/cmux` by default and will use the latest full release when present, falling back to `panecho-nightly` automatically.

### Build from source only when needed

If you want to force a local source build, use:

```bash
./scripts/install-panecho.sh --build-from-source
```

That source-build path is the only mode that requires full Xcode.

When source-building, the script will:

1. load `.env` automatically if it exists
2. make sure full Xcode is selected
3. install `zig` and `go` with Homebrew if needed
4. run repo setup
5. build `Panecho`
6. copy `Panecho.app` into `/Applications` (or `~/Applications` if needed)
7. open the app

### Install from a local or remote artifact

Use a local app bundle, zip, dmg, or direct download URL:

```bash
./scripts/install-panecho.sh --source /path/to/Panecho.app
./scripts/install-panecho.sh --source /path/to/panecho-macos.dmg
./scripts/install-panecho.sh --source https://example.com/panecho-macos.dmg
```

Or set it once in your environment:

```bash
PANECHO_DOWNLOAD_URL=https://example.com/panecho-macos.dmg ./scripts/install-panecho.sh
```

If you want to target a different release tag in GitHub, override it explicitly:

```bash
PANECHO_RELEASE_TAG=panecho-nightly ./scripts/install-panecho.sh
```

### Optional: signed build

If you want a signed local build, fill in `.env` first and set:

```bash
PANECHO_ALLOW_CODESIGN=1
```

The install script automatically picks that up.

### Optional: skip opening the app after install

```bash
PANECHO_SKIP_OPEN=1 ./scripts/install-panecho.sh
```

### Optional: install somewhere else

```bash
PANECHO_INSTALL_DIR="$HOME/Apps" ./scripts/install-panecho.sh
```

### Current blocker on this machine

This workspace still cannot source-build the full app until full Xcode is installed.
The installer no longer assumes Xcode is required for every install, and published `panecho-nightly` builds do not require local Go for remote helper bootstrapping.
