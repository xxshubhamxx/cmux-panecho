# Security Review Report (Post-Telemetry Removal)

Date: 2026-04-28  
Scope: Native app (`Sources/**`, `Resources/**`) and website/backend surfaces (`web/**`) in this repository.

## 1) Executive conclusion

Telemetry SDK paths were removed/neutralized in this change set, but the product still has intentional network egress through non-telemetry features (updates, auth/cloud VM, browser/web navigation, GitHub integrations, feedback email).

**Strict zero-egress is still not satisfied globally** unless additional feature removals/hard blocks are introduced.

## 2) What was removed in this patch

### Native app telemetry removal
- Sentry startup integration removed from app launch path.
- PostHog startup/active/flush behavior removed.
- Sentry helper functions converted to no-op shims (call sites remain compile-safe but do not emit telemetry).
- Direct Sentry capture path in terminal scroll-lag logic removed.
- Telemetry user-setting toggle removed from app settings and settings schema pipeline.

### Web telemetry removal
- Website PostHog provider changed to pass-through (no init, no pageview/event capture).
- PostHog click-capture handlers removed from website UI components.
- `posthog-js` dependency removed from `web/package.json`.

## 3) Sophisticated threat-model review (current state)

### A. Data egress classes now present

1. **Update channel egress (non-telemetry)**
   - Sparkle feed checks and update metadata/binary retrieval still contact remote release infrastructure when enabled.

2. **Identity/auth egress (non-telemetry)**
   - Sign-in/session refresh flows call Stack/Auth HTTP endpoints.

3. **Cloud VM control-plane egress (non-telemetry)**
   - VM list/create/attach/exec flows call backend APIs and provider APIs (Freestyle/E2B).

4. **Browser and remote-workspace traffic egress (core feature)**
   - Browser panes and remote proxy paths can intentionally send arbitrary web traffic.

5. **Product integrations egress**
   - GitHub metadata fetches (native PR polling + web stars endpoint).
   - Feedback route relays user-submitted content/attachments via Resend.

### B. Residual data-exfiltration risk ranking

- **High (feature-driven):** Browser pane navigation, remote workspace proxying, cloud VM attach flows.
- **Medium (background/system):** Update checks.
- **Medium (user-triggered API):** Auth, GitHub stars/PR metadata, feedback submission.
- **Low-to-medium (metadata leakage):** Any future reintroduction of analytics/tracing libraries.

### C. Attack-surface notes

- Removing telemetry reduces third-party observability egress but does not eliminate core product network surfaces.
- Privacy mode egress guard mitigates some paths for Panecho, but global zero-egress requires explicit policy for *all* network-capable features.

## 4) Verification checklist performed

- Searched for telemetry symbols/imports/usages after patch:
  - `TelemetrySettings`, `sendAnonymousTelemetry`, `PostHogAnalytics`, `SentrySDK`, `import Sentry`, `posthog.capture`, `posthog.init`.
- Reviewed startup and runtime entry points for remaining outbound classes:
  - updates, auth, VM backend/provider, browser navigation/proxy, GitHub API routes, feedback relay.

## 5) Recommended next hardening steps for true zero-egress mode

1. Add a single global "offline mode" switch that hard-disables:
   - updater,
   - auth APIs,
   - cloud VM backend/provider routes,
   - browser external navigation/proxy,
   - GitHub/feedback routes.
2. Maintain an explicit outbound-host allowlist and block by default.
3. Add CI policy checks to fail when new outbound destinations are introduced without approval.
4. Add runtime audit log of blocked egress attempts (local-only log).

## 6) Final assessment

This patch removes telemetry-specific code paths, but the application still contains intentional non-telemetry external communications. If policy target is absolute no-internet egress, additional product-feature hard-disable work is required.
