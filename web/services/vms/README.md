# Cloud VMs service

Backend for `cmux vm new/ls/rm/exec/attach` and the upcoming sidebar Cloud button. Stack Auth gated, manaflow-owned provider keys (no BYO). Freestyle and E2B prefer `cmuxd-remote` WebSocket PTY with a short-lived one-use lease; older Freestyle VMs can fall back to its SSH gateway.

## Layout

```text
services/vms/
  drivers/
    types.ts       VMProvider interface, shared types, errors
    e2b.ts         E2BProvider — real driver over @e2b SDK
    freestyle.ts   FreestyleProvider — real driver over @freestyle/sdk
    index.ts       getProvider / defaultProviderId
  actors/
    vm.ts          One per VM. Tracks connection count for idle-pause.
    userVms.ts     Coordinator per Stack Auth user. Lists/creates/forgets VMs.
  registry.ts      RivetKit setup({ use: { vmActor, userVmsActor } })
  routeHelpers.ts  Shared REST helpers: bearer parsing, server-controlled Rivet
                   base URL, ownership checks, signed actor handles.
  rivetSecurity.ts Internal Rivet gateway header, signed actor params, deploy checks.
  auth.ts          verifyRequest / unauthorized — Stack Auth bearer verification
```

## HTTP surface

- `/api/vm` — authenticated REST facade: `GET` (list) / `POST` (create).
- `/api/vm/:id` — authenticated REST facade: `DELETE` (destroy).
- `/api/vm/:id/exec` — authenticated REST facade: `POST` (run a command).
- `/api/vm/:id/attach-endpoint` — authenticated REST facade: `POST` (mint PTY/RPC attach leases).
- `/api/vm/:id/ssh-endpoint` — authenticated REST facade: `POST` (legacy Freestyle SSH attach).
- `/api/rivet/metadata` and raw actor action paths are server-internal. They require the
  `x-cmux-rivet-internal` header and actor calls also require signed connection params scoped to
  the Stack Auth user. This prevents a public Rivet token or client-chosen actor key from becoming
  enough to list, create, or attach someone else's VM.
- `/api/rivet/start` is the only public Rivet route. Rivet Cloud calls it in serverless mode, and
  production must set `RIVET_ENDPOINT` (or `RIVET_TOKEN` + `RIVET_NAMESPACE`) so RivetKit validates
  the caller as the trusted engine.

All endpoints verify `Authorization: Bearer <stack access token>` plus `X-Stack-Refresh-Token:
<refresh>` from the Mac client (matches the tokens the Mac app stashes in keychain after
`cmux auth login`). Browsers going through `/handler/*` hit the same functions via the Stack
Auth cookie path.

## Authentication model

The VM service has three separate trust boundaries:

1. Native/client boundary. Public callers only use `/api/vm/*`. These routes call Stack Auth first,
   return `401` before provisioning when the caller is unauthenticated, and check the coordinator
   actor's user-owned VM list before `delete`, `exec`, `attach`, or legacy SSH endpoint minting.
2. Server-to-Rivet boundary. The REST routes call Rivet with `x-cmux-rivet-internal:
   CMUX_RIVET_INTERNAL_SECRET`. Raw `/api/rivet/*` requests without that header are rejected. This
   keeps a user from bypassing REST ownership checks with a direct Rivet client and a guessed actor
   key.
3. Actor boundary. Actor handles include HMAC-signed params from `makeActorAuthParams(userId)`.
   `userVmsActor` requires those params to match its actor key. `vmActor` requires them to match
   `c.state.userId`. This protects deployed Rivet actor actions even if a raw actor endpoint is
   reachable.

`GET /api/rivet/start` is intentionally excluded from the shared-secret header because Rivet Cloud
calls it in serverless mode. In deployed envs it refuses to run unless `RIVET_ENDPOINT` or
`RIVET_TOKEN` + `RIVET_NAMESPACE` is configured, so the public start route is still tied to the
trusted Rivet engine.

The auth regression tests live in `web/tests`:

- `vm-route-auth.test.ts` verifies unauthenticated `POST /api/vm` returns `401` before a Rivet
  client or provider provisioning path can run.
- `vm-rivet-security.test.ts` verifies raw Rivet header checks, signed actor params, and the
  deployed `/api/rivet/start` private-endpoint requirement.

## Env

See `web/.env.example`. The VM-specific vars:

- `E2B_API_KEY` — manaflow's key, used by E2BProvider.
- `FREESTYLE_API_KEY` — manaflow's key, used by FreestyleProvider.
- `E2B_CMUXD_WS_TEMPLATE` — E2B template alias/name for interactive WebSocket PTY sandboxes.
  Produced by `web/scripts/build-cloud-vm-images.ts`.
- `E2B_SANDBOX_TEMPLATE` — legacy scratch template. Pass explicitly with `--image` if needed.
- `FREESTYLE_SANDBOX_SNAPSHOT` — Freestyle snapshot id for `vm new` / `vm attach`. Produced by
  `web/scripts/build-cloud-vm-images.ts`.
- `CMUX_VM_DEFAULT_PROVIDER` — `freestyle` (default) or `e2b`.
- `CMUX_RIVET_INTERNAL_SECRET` — server-only HMAC secret for raw Rivet gateway access and signed
  actor params. Required in previews and production.
- `RIVET_ENDPOINT` — private Rivet Cloud endpoint with `sk_` token. Required for deployed
  serverless RivetKit.
- `RIVET_PUBLIC_ENDPOINT` — public Rivet Cloud endpoint with `pk_` token. Needed if the Rivet
  metadata flow is used by a client or the selected deployment tooling expects it.
- `RIVET_RUNNER_VERSION` — monotonically increasing deployment version, for graceful actor upgrades.

## Deployment

Local dev uses RivetKit's local runtime through the same `/api/rivet/*` route. Production should use
Rivet Cloud serverless behind Vercel:

1. Deploy the Next app to Vercel with the catch-all route at `web/app/api/rivet/[...path]/route.ts`.
2. Configure a Rivet namespace per environment: production gets a stable namespace, previews get
   isolated namespaces via Rivet's `preview-namespace-action`.
3. Set Vercel env:
   - provider keys: `E2B_API_KEY`, `FREESTYLE_API_KEY`
   - image ids: `E2B_CMUXD_WS_TEMPLATE`, `FREESTYLE_SANDBOX_SNAPSHOT`
   - auth: Stack Auth vars plus `CMUX_RIVET_INTERNAL_SECRET`
   - Rivet: `RIVET_ENDPOINT`, `RIVET_PUBLIC_ENDPOINT`, `RIVET_RUNNER_VERSION`
   - telemetry: Axiom/OTel exporter vars
4. Disable or bypass Vercel Deployment Protection for Rivet engine requests to `/api/rivet/start`,
   using the Vercel bypass header configured in the Rivet provider if previews are protected.

## Usage, limits, and pricing

This PR records operational spans and authenticated ownership, but it should not be the billing PR.
Usage tracking should be a follow-up with a persistent ledger keyed by Stack user id:

- VM lifecycle events: create, destroy, pause, resume, provider, image, createdAt, destroyedAt.
- Attach events: PTY lease minted, RPC lease minted/reused, transport, provider.
- Exec events: count, timeout, exit code, duration.
- Cost rollups: active VM wall time by provider/image, attach count, exec count, snapshot count.

Initial rate limits can be conservative until billing is live:

- free users: small concurrent VM cap, daily create cap, short max runtime
- paid users: higher concurrent cap, higher daily create cap, longer max runtime
- global provider guardrails: cap creates/minute and concurrent provisioning per provider

Implement limits before each paid provider call, then record the accepted operation in the ledger
with the idempotency key so retries do not double count.

## Provider matrix

| Verb                        | Freestyle | E2B            |
|-----------------------------|-----------|----------------|
| `cmux vm new` (shell)       | ✓         | ✓              |
| `cmux vm new --workspace`   | ✓         | ✓              |
| `cmux vm new --detach`      | ✓         | ✓              |
| `cmux vm attach <id>`       | ✓         | ✓              |
| `cmux vm exec <id> -- ...`  | ✓         | ✓              |
| `cmux vm ls / rm`           | ✓         | ✓              |

E2B interactive paths require a cmuxd WebSocket PTY image. The backend writes only a hash of the
attach token into `/tmp/cmux/attach-lease.json`; the raw token is returned once to the Mac client.

## Lifecycle

- `userVmsActor.create({ image, provider })` provisions the provider VM, spawns `vmActor(providerVmId)`
  with input, appends to the user's list, returns `{ id, provider, image }`.
- `vmActor.createState` stores the provider id, Stack user id, image, and lifecycle state.
- A client WebSocket connection keeps `c.conns.size >= 1`. Disconnecting schedules `autoPause`
  10 minutes out.
- `autoPause` re-checks `c.conns.size` first, so a reconnect race is a no-op. If still zero,
  it calls `driver.pause()`.
- `vmActor.remove` calls `driver.destroy()` then `c.destroy()`. `userVmsActor.forget(id)`
  removes the id from the coordinator.

## Rivet responsibilities

Rivet is not currently used for user-facing realtime UI. The WebSocket PTY and browser proxy paths
talk to `cmuxd-remote` inside the provider VM through E2B/Freestyle networking after the REST
handshake mints short-lived leases.

Today Rivet provides the stateful control plane:

- one `userVmsActor` per Stack user for owned VM listing, idempotent creates, and coordinator state
- one `vmActor` per provider VM for lifecycle operations, credentials, exec, attach endpoint minting,
  snapshots, and cleanup
- serialized per-actor actions so duplicate create/delete/credential-mint races have one owner

This is convenient, but not strictly necessary for the first version. If we do not use Rivet for
realtime subscriptions or long-running workflows soon, most logic could move into Vercel route
handlers backed by a persistent database table for users, VMs, leases, usage ledger rows, and
idempotency keys. That version would still need a separate background cleanup path for orphaned VMs
and expired leases. Rivet is most justified if we keep per-VM lifecycle coordination in actors or add
live VM status/progress subscriptions.

## Next steps

- Keep Freestyle SSH and E2B WebSocket attach paths sharing the same `POST /api/vm/:id/attach-endpoint`
  contract.
- Add `/api/vm/:id/pause`, `/api/vm/:id/resume`, `/api/vm/:id/snapshot` REST wrappers once Swift
  client wants them.

See `plans/task-cmux-vm-cloud/cloud-vms-and-per-surface-ssh.md` for the full roadmap and
`plans/task-cmux-vm-cloud/cli-vm-new-shell-and-workspace.md` for the latest CLI shape.
