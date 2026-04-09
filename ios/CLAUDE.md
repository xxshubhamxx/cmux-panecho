# cmux iOS App

## Build Configs
| Config | Bundle ID | App Name | Signing |
|--------|-----------|----------|---------|
| Debug | `dev.cmux.app.dev` | cmux DEV | Automatic |
| Nightly | `com.cmuxterm.app.nightly` | cmux NIGHTLY | Automatic |
| Release | `com.cmuxterm.app` | cmux | Manual |

## Development
```bash
./scripts/reload.sh   # Build & install to simulator + iPhone (if connected)
./scripts/device.sh   # Build & install to connected iPhone only
```

Always run `./scripts/reload.sh` after making code changes to reload the app.

## Living Spec
- `docs/terminal-sidebar-living-spec.md` tracks the sidebar terminal migration plan.
- Keep this document updated as implementation status changes.

## TestFlight
```bash
./scripts/testflight.sh  # Auto-increments build number, archives, uploads
```

Build numbers in `project.yml` (`CURRENT_PROJECT_VERSION`). Limit: 100 per version.

## Notes
- **Dev shortcut**: Enter `42` as email to auto-login (DEBUG only, needs test user in Stack Auth)
- **Encryption**: `ITSAppUsesNonExemptEncryption: false` set in project.yml
