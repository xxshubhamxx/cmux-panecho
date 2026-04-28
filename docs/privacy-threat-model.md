## Privacy Threat Model — Panecho (fork of cmux)

### Confirmed outbound calls

#### Default-on background or surprise outbound traffic

| Surface | Destination(s) | Trigger | Default state | Evidence |
| --- | --- | --- | --- | --- |
| Anonymous analytics | `https://us.i.posthog.com` | App launch, active timer, app activation, app termination flush | **On by default** | `Sources/PostHogAnalytics.swift`, `Sources/AppDelegate.swift` |
| Crash/error reporting | `https://*.ingest.us.sentry.io` | App launch initializes SDK; later breadcrumbs/errors/captures send through Sentry | **On by default** (gated by telemetry, which defaults on) | `Sources/AppDelegate.swift`, `Sources/SentryHelper.swift`, `Sources/GhosttyTerminalView.swift` |
| Auto-update checks | `https://github.com/manaflow-ai/cmux/releases/latest/download/appcast.xml` | Launch update probe plus scheduled background checks | **On by default** | `Resources/Info.plist`, `Sources/Update/UpdateController.swift`, `Sources/Update/UpdateDelegate.swift` |
| Sidebar PR polling | `https://api.github.com/repos/.../pulls` | Directory/branch changes and follow-up poll timer when PR sidebar tracking is active | **On by default** because PR display defaults on | `Sources/TabManager.swift`, `Sources/cmuxApp.swift`, `Sources/ContentView.swift` |
| React Grab CDN fetch | `https://unpkg.com/react-grab@<version>/dist/index.global.js` | Browser panel React Grab prefetch / injection path | **Potentially surprising by default** because prefetch is wired into browser panel setup | `Sources/Panels/ReactGrab.swift`, `Sources/Panels/BrowserPanel.swift` |
| Browser search suggestions | Google / DuckDuckGo / Bing / Kagi / Startpage suggestion APIs | Typing in the omnibar | **On by default** | `Sources/Panels/BrowserPanel.swift`, `Sources/Panels/BrowserPanelView.swift` |

#### Feature-driven outbound traffic

| Surface | Destination(s) | Trigger | Notes | Evidence |
| --- | --- | --- | --- | --- |
| Feedback upload | `https://cmux.com/api/feedback` | User submits feedback | App-owned backend; not acceptable for privacy-hardened enterprise mode | `Sources/ContentView.swift` |
| Auth / sign-in | `https://cmux.com`, `https://api.cmux.sh`, `https://api.stack-auth.com` | User sign-in / session / team lookups | Required for account/cloud features only | `Sources/Auth/AuthEnvironment.swift`, `Sources/Auth/AuthManager.swift` |
| Cloud VM control plane | `https://cmux.com`, `https://api.cmux.sh` under `/api/vm/*` | User invokes cloud VM features | Explicit cloud dependency | `Sources/Auth/AuthEnvironment.swift`, `Sources/Cloud/VMClient.swift`, `Sources/TerminalController.swift` |
| Remote helper manifest / binary download | GitHub release asset URLs under `https://github.com/<owner>/<repo>/releases/download/<tag>/...` | Remote daemon bootstrap when helper is missing or checksum fallback is needed | User-driven remote feature, but still app-initiated internet fetch | `Sources/Workspace.swift`, `scripts/build_remote_daemon_release_assets.sh` |
| Embedded browser navigation | Search engines, arbitrary user-opened sites | User opens browser tabs or navigates | Expected user traffic, not telemetry | `Sources/Panels/BrowserPanel.swift` |
| GitHub / docs / changelog / issue links | `github.com`, `cmux.com/docs`, `discord.gg`, etc. | User clicks help/release links | User-initiated UI links | `Sources/ContentView.swift`, `Sources/cmuxApp.swift`, `Sources/Update/UpdateViewModel.swift` |

### Suspected or conditional outbound traffic

| Surface | Status | Why it matters |
| --- | --- | --- |
| Ghostty crash reporting internals | **Not yet runtime-verified** | `ghostty/build.zig.zon` includes `pkg/sentry`; `ghostty/src/**` references `crash/main.zig` and `crash.sentry.thread_state`. The app currently uses a prebuilt `GhosttyKit.xcframework`, so source presence alone does not prove active runtime reporting. |
| Runtime debug log uploader | **Env-gated, not default** | `CmuxRuntimeDebugCapture` posts JSON to `baseURL/api/logs` only when `CMUX_RUNTIME_DEBUG_*` env vars are present. |
| Web backend telemetry packages | **Server-side / repo-side only for now** | `web/package.json` includes `posthog-js`, `@vercel/otel`, and OpenTelemetry packages, but those do not create macOS app traffic unless the app talks to the hosted backend endpoints. |
| Ghostty appcast/update sources in submodule | **Likely not part of the shipped cmux app path** | Ghostty macOS sources include their own update feed URLs, but the cmux app already wires its own Sparkle updater. Needs confirmation during build/runtime inspection, not assumed active. |

### Auto-update behavior

- `Resources/Info.plist` sets:
  - `SUEnableAutomaticChecks = true`
  - `SUFeedURL = https://github.com/manaflow-ai/cmux/releases/latest/download/appcast.xml`
  - `SUScheduledCheckInterval = 86400`
- `Sources/Update/UpdateController.swift` reinforces update behavior at runtime and starts a launch probe plus recurring checks.
- Conclusion: auto-update is **active by design** and must be hard-disabled for enterprise privacy mode.

### Crash reporters and analytics

- **Sentry**
  - Started from `AppDelegate.applicationDidFinishLaunching`.
  - DSN is hardcoded in `Sources/AppDelegate.swift`.
  - Helper functions in `Sources/SentryHelper.swift` are called from multiple UI/runtime paths.
  - `Sources/GhosttyTerminalView.swift` also contains a direct `SentrySDK.capture(...)` path for scroll lag, still gated by telemetry.
- **PostHog**
  - Hardcoded host and API key in `Sources/PostHogAnalytics.swift`.
  - Tracks daily/hourly active usage and flushes events during runtime / termination.
- Conclusion: both crash/analytics surfaces are **default-on today** because `TelemetrySettings.defaultSendAnonymousTelemetry = true`.

### iCloud / CloudKit / push notification status

- No active `CloudKit`, `CKContainer`, or `NSUbiquitousKeyValueStore` usage was found in app sources.
- Checked-in entitlements do **not** include iCloud container keys.
- `UNUserNotificationCenter` exists for local notifications, but the scan did not show real APNs registration / remote push token plumbing.
- Conclusion: there is **no current evidence of iCloud sync or remote push infrastructure** in the macOS app.

### Third-party SDKs and remote dependencies of concern

- **Sparkle** — auto-update framework, active.
- **Sentry** — crash/error reporting, active.
- **PostHog** — analytics, active.
- **Stack Auth** — auth/session backend dependency, active when auth is used.
- **React Grab via unpkg** — runtime CDN dependency, active through browser-panel feature wiring.
- **GitHub API** — used for automatic PR metadata polling, active by default when sidebar PRs are shown.

### Ghostty activity

- The checked-in Ghostty source tree includes crash-reporting-related code and packages.
- The shipped cmux setup path downloads a prebuilt `GhosttyKit.xcframework`, so the exact privacy posture of the embedded binary must be treated as a verification item.
- Separately, cmux’s own Swift layer around Ghostty contains a direct Sentry capture path for scroll-lag warnings, but it is still gated by `TelemetrySettings.enabledForCurrentLaunch`.

### Daemon / remote activity

- `daemon/remote` is a Go remote helper, not Zig.
- `Sources/Workspace.swift` can:
  - upload / start `cmuxd-remote` over SSH,
  - talk over SSH stdio, WebSocket PTY, and local socket forward paths,
  - fetch a release-manifest / release-binary from GitHub when the helper is missing,
  - fall back to a **local Go build** when `CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1` is set.
- Interpretation:
  - SSH / WebSocket / loopback transport itself is a user-invoked product feature.
  - The helper **download path** is still outbound internet traffic initiated by the app and should be replaced or suppressed in privacy mode.

### Cloud VM backend

- `AuthEnvironment` resolves production defaults to:
  - `websiteOrigin = https://cmux.com`
  - `apiBaseURL = https://api.cmux.sh`
  - `vmAPIBaseURL = https://cmux.com` (VM routes under `/api/vm`)
  - `stackBaseURL = https://api.stack-auth.com`
- `VMClient` implements list/create/destroy/exec/attach/ssh for cloud VMs.
- `TerminalController` exposes those VM operations into the app’s command surface.
- Conclusion: cloud VM support is a real backend dependency and must be disabled or hard-gated for privacy-safe enterprise builds.

### Entitlements risk review

Confirmed entitlements include:

- `com.apple.security.cs.disable-library-validation`
- `com.apple.security.cs.allow-unsigned-executable-memory`
- `com.apple.security.cs.allow-jit`
- `com.apple.developer.web-browser.public-key-credential`
- camera and microphone access
- Apple Events automation

Confirmed absent from checked-in entitlements:

- iCloud container entitlements
- `com.apple.security.network.client`
- `com.apple.security.network.server`

Interpretation:

- The current entitlement set is **powerful** and broader than a minimal enterprise posture, especially around JIT / unsigned executable memory / Apple Events.
- It does **not** itself prove data exfiltration, but it increases the attack surface and should be reviewed alongside privacy mode and signing hardening.

### Verdict

`cmux` is **not enterprise-acceptable as-is** for a strict data-privacy review.

The repo contains multiple concrete outbound paths that violate a “no unexpected phone-home” requirement, including:

- PostHog analytics
- Sentry crash/error reporting
- Sparkle update checks
- automatic GitHub PR polling
- React Grab CDN fetches
- default-on browser autosuggest calls
- app-owned feedback/auth/cloud backend calls

The least-conflict hardening direction is:

1. add a compile-time privacy mode / xcconfig overlay,
2. force telemetry and crash reporting permanently off,
3. disable Sparkle entirely,
4. disable app-owned cloud/auth/feedback paths with graceful UI fallbacks,
5. disable or localize surprise network conveniences (PR polling, React Grab CDN fetch, autosuggest),
6. switch remote daemon bootstrap to a local-build / bundled path so remote features do not fetch helper binaries from the internet.
