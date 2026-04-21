import { createClient, type Client } from "rivetkit/client";
import type { Registry } from "./registry";

/** Bearer + refresh token pair the mac app stashes in keychain. */
export type StackBearer = { accessToken: string; refreshToken: string };

/**
 * Gate for `/api/rivet/*`. Our REST routes already authenticate and do ownership checks;
 * Rivet's catch-all then proxies into the actor system. Without a shared secret, any
 * authenticated user could point a raw RivetKit client at `/api/rivet/*` and call
 * `userVmsActor.getOrCreate([otherUserId]).list()` — the key is client-chosen, so auth
 * alone is not enough. With this header, the catch-all drops unauthenticated (i.e. non-
 * REST-originated) traffic before it reaches any actor. The REST layer supplies the value;
 * external clients cannot forge it.
 */
export const RIVET_INTERNAL_HEADER = "x-cmux-rivet-internal";

/**
 * Read the internal secret lazily so tests can override via process.env before the module
 * is loaded. In production we require the caller to set it explicitly so we don't degrade
 * into "any authenticated request is trusted".
 */
/**
 * Process-local fallback secret. Generated once at module load so local dev doesn't
 * require setting CMUX_RIVET_INTERNAL_SECRET, but unpredictable across restarts and per
 * process — an attacker with source-read can no longer spoof the header via a hardcoded
 * string on a shared staging box. Replaced by the real env value as soon as one is set.
 */
const DEV_FALLBACK_SECRET: string = (() => {
  // Lazy import so we don't pay the crypto cost on cold boot when the env is already set.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { randomBytes } = require("node:crypto") as typeof import("node:crypto");
  return `cmux-dev-${randomBytes(24).toString("hex")}`;
})();

function rivetInternalSecret(): string {
  const value = process.env.CMUX_RIVET_INTERNAL_SECRET?.trim();
  if (value) return value;
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "CMUX_RIVET_INTERNAL_SECRET must be set in production (used to gate /api/rivet/*).",
    );
  }
  // Per-process random fallback. Read via the module constant so every caller in this
  // process agrees on the same value (REST route + catch-all gate would otherwise drift).
  return DEV_FALLBACK_SECRET;
}

export function assertRivetInternal(request: Request): boolean {
  const header = request.headers.get(RIVET_INTERNAL_HEADER);
  if (!header) return false;
  const expected = rivetInternalSecret();
  // Constant-time string compare wouldn't help much here (length is fixed, leak surface is
  // bounded by the handful of dev/prod values), but we keep it simple and direct.
  return header === expected;
}

/**
 * Authoritative base URL for the Rivet gateway. On Vercel we trust VERCEL_URL (deployment
 * only, set by the platform). Local dev reads `CMUX_VM_API_BASE_URL` or falls back to
 * `http://localhost:3000`. Deriving this from `request.url.origin` is unsafe — a misconfigured
 * reverse proxy could rewrite Host and redirect Stack Auth tokens to an attacker-controlled
 * endpoint.
 */
function rivetBaseURL(): string {
  const explicit = process.env.CMUX_VM_API_BASE_URL?.trim();
  if (explicit) return explicit.replace(/\/$/, "");
  const vercel = process.env.VERCEL_URL?.trim();
  if (vercel) return `https://${vercel}`;
  return "http://localhost:3000";
}

export function parseBearer(request: Request): StackBearer | null {
  const auth = request.headers.get("authorization");
  const refresh = request.headers.get("x-stack-refresh-token");
  if (!auth?.toLowerCase().startsWith("bearer ") || !refresh) return null;
  const accessToken = auth.slice("bearer ".length).trim();
  const refreshToken = refresh.trim();
  if (!accessToken || !refreshToken) return null;
  return { accessToken, refreshToken };
}

export function rivetClient(bearer: StackBearer): Client<Registry> {
  return createClient<Registry>({
    endpoint: `${rivetBaseURL()}/api/rivet`,
    headers: {
      authorization: `Bearer ${bearer.accessToken}`,
      "x-stack-refresh-token": bearer.refreshToken,
      [RIVET_INTERNAL_HEADER]: rivetInternalSecret(),
    },
  });
}

/**
 * Confirms this user owns `vmId` before any mutation (destroy, exec, openSSH, snapshot).
 * Prevents IDOR: without this, any authenticated user could DELETE/exec/ssh anyone else's
 * VM by passing the raw provider id to the route. Checks against the coordinator actor's
 * own list rather than asking the vmActor directly (the vmActor would happily getOrCreate a
 * brand-new shell actor for an id it's never seen).
 */
export async function userOwnsVm(
  client: Client<Registry>,
  userId: string,
  vmId: string,
): Promise<boolean> {
  const list = await client.userVmsActor.getOrCreate([userId]).list();
  return list.some((v) => v.providerVmId === vmId);
}

/**
 * `Response.json(...)` misbehaves under Next.js 16's turbopack dev build (the handler's
 * promise settles but turbopack reports "No response is returned from route handler").
 * Use `new Response(JSON.stringify(...), { ... })` explicitly instead.
 */
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function notFoundVm(vmId: string): Response {
  return jsonResponse({ error: `vm not found: ${vmId}` }, 404);
}
