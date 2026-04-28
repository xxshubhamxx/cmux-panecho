## Panecho build and verification

`Panecho` is the enterprise privacy-mode fork of `cmux`.

### Quick install

The shortest path is:

```bash
./scripts/install-panecho.sh
```

That script:

- loads `.env` automatically if present
- prefers a prebuilt `Panecho.app`, `.zip`, or `.dmg` if one is available
- can install from `PANECHO_DOWNLOAD_URL`, the current repo's `panecho-nightly` prerelease asset, or a full `Panecho` release asset on the current GitHub repo
- only falls back to a local source build when `xcodebuild` is already usable or when you pass `--build-from-source`
- copies `Panecho.app` into `/Applications` (or `~/Applications` when `/Applications` is not writable)
- opens the app

Once the fork publishes `panecho-nightly`, the default install path is just:

```bash
./scripts/install-panecho.sh
```

No local Xcode or Go toolchain is required for that published-build path.

For a remote one-liner without cloning first:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR-ORG/YOUR-PANECHO-FORK/main/scripts/install-panecho.sh | PANECHO_RELEASE_REPO=YOUR-ORG/YOUR-PANECHO-FORK bash
```

To force a source build:

```bash
./scripts/install-panecho.sh --build-from-source
```

### What privacy mode does

The `Config/PrivacyOverrides.xcconfig` overlay enables the `PRIVACY_MODE` compilation condition and renames the built app to `Panecho`.

When built with that overlay, the app hard-disables these outbound paths:

- PostHog analytics
- Sentry crash/error reporting
- Sparkle startup and update checks
- Runtime debug log upload (`CMUX_RUNTIME_DEBUG_*`)
- Browser search suggestion fetches
- React Grab CDN script fetches
- Automatic GitHub pull-request polling
- Feedback form uploads
- Stack Auth sign-in / session restore
- Cloud VM backend access
- Remote daemon GitHub manifest/binary downloads

### Build prerequisites

These apply to **source builds**, not prebuilt installs:

- Full Xcode installed at `/Applications/Xcode.app`
- `xcode-select` pointing at full Xcode
- For remote daemon local fallback in privacy mode:
  - either `go` installed locally, or
  - `CMUX_REMOTE_DAEMON_BINARY` pointing at a trusted local `cmuxd-remote` binary

### Local build

Unsigned local build:

```bash
./scripts/build-panecho.sh
```

Allow signing once identities are installed:

```bash
PANECHO_ALLOW_CODESIGN=1 ./scripts/build-panecho.sh
```

Pass through additional `xcodebuild` arguments after the script name:

```bash
./scripts/build-panecho.sh -configuration Debug
```

### Privacy-mode remote helper behavior

Panecho refuses to download `cmuxd-remote` from GitHub.

Instead it will use, in order:

1. A trusted explicit local binary from `CMUX_REMOTE_DAEMON_BINARY`
2. A bundled verified binary shipped inside a published `Panecho.app`
3. A previously cached verified binary
4. A local Go build fallback from `daemon/remote`

If none of those are available, remote-daemon bootstrap fails locally instead of making a network request.

In privacy mode, the Go fallback is forced to run offline (`GOPROXY=off`, `GOSUMDB=off`, `-mod=readonly`). That means the module cache must already be populated, or you must provide `CMUX_REMOTE_DAEMON_BINARY`.

Published `panecho-nightly` builds bundle the verified remote helper binaries for:

- `darwin-arm64`
- `darwin-amd64`
- `linux-arm64`
- `linux-amd64`

That preserves remote workspace bootstrap without re-enabling outbound downloads.

### Verification checklist

After full Xcode is installed, validate the hardened build with this sequence:

1. Build `Panecho` with `./scripts/build-panecho.sh`
2. Launch the built app under a clean macOS user profile or a clean app data state
3. Start `mitmproxy` or `mitmweb`
4. Exercise these flows without signing in:
   - app launch and idle
   - open local workspaces
   - embedded browser navigation to local/internal targets only
   - terminal usage
   - settings resets
5. Confirm there are no unexpected outbound requests for:
   - `sentry.io`
   - `posthog.com`
   - GitHub release/appcast URLs
   - search suggestion endpoints
   - `unpkg.com`
   - `api.stack-auth.com`
   - `cmux.com/api/feedback`
   - `api.cmux.sh`
   - `/api/vm`

### Current environment blockers

In the current workspace environment, final runtime verification is still blocked by:

- full Xcode not being installed
- `xcodebuild` being unavailable against Command Line Tools alone
- signing identities not being imported yet (`APPLE_CERT_PASSWORD` not set)
