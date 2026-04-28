# PR #2 Merge Resolution — PostHogAnalytics.swift

The original PR `panecho-install-build` deleted `Sources/PostHogAnalytics.swift`
outright. During the merge of `origin/main` into the PR branch the file was
restored. This was deliberate — not silent.

## Why the file is kept (origin/main approach)

The fork supports two build configurations:

1. **Default cmux build** — `Sources/AppDelegate.swift` calls
   `PostHogAnalytics.shared.startIfNeeded()` / `.trackActive(...)` / `.flush()`
   and `cmuxTests/GhosttyConfigTests.swift` exercises
   `PostHogAnalytics.dailyActiveProperties` / `superProperties` /
   `hourlyActiveProperties` / `shouldFlushAfterCapture`. Removing the type
   breaks the build and the test suite.

2. **Panecho privacy build** (`PRIVACY_MODE` set via
   `Config/PrivacyOverrides.xcconfig`) — `PostHogAnalytics.swift` resolves to a
   no-op stub (`#if PRIVACY_MODE` branch). Three independent layers prevent
   any network egress:

   - **Compile-time stub** — every public method (`startIfNeeded`,
     `trackActive`, `trackDailyActive`, `trackHourlyActive`, `flush`) returns
     immediately. The PostHog SDK is not imported.
   - **Framework strip at stage time** — commit `0a07e7e8` removes the PostHog
     XCFramework from `GhosttyTabs.xcodeproj/project.pbxproj` and
     `scripts/stage-panecho-app.sh` so the binary cannot link against it.
   - **Runtime telemetry gate** — `TelemetrySettings.enabledForCurrentLaunch`
     short-circuits to `false` when `PrivacyMode.isEnabled`, so all call sites
     in `AppDelegate.swift` skip the (already-stub) calls.

## Net effect

For Panecho users: identical to deletion. No PostHog code executes, no
PostHog framework ships, no telemetry network call is made. For maintainers
keeping parity with upstream cmux: the dual-build remains intact.

This document exists so the divergence from the PR's literal "delete file"
intent is auditable. The privacy guarantee is preserved.
