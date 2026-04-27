import { createHash } from "node:crypto";
import * as Context from "effect/Context";
import * as Data from "effect/Data";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import { createClient, type RedisClientType } from "redis";

export type RateLimitPolicy = {
  readonly scope: string;
  readonly limit: number;
  readonly windowMs: number;
};

export type RateLimitDecision = {
  readonly scope: string;
  readonly limit: number;
  readonly remaining: number;
  readonly resetAt: Date;
};

export class RateLimitExceededError extends Data.TaggedError("RateLimitExceededError")<{
  readonly scope: string;
  readonly limit: number;
  readonly resetAt: Date;
}> {
  get retryAfterMs(): number {
    return Math.max(0, this.resetAt.getTime() - Date.now());
  }
}

export class RateLimitStoreError extends Data.TaggedError("RateLimitStoreError")<{
  readonly operation: string;
  readonly cause: unknown;
}> {}

export type RateLimitError = RateLimitExceededError | RateLimitStoreError;

export type RateLimitStoreShape = {
  readonly increment: (input: {
    readonly key: string;
    readonly windowMs: number;
    readonly now: Date;
  }) => Effect.Effect<number, RateLimitStoreError>;
};

export class RateLimitStore extends Context.Tag("cmux/RateLimitStore")<
  RateLimitStore,
  RateLimitStoreShape
>() {}

export const RateLimitStoreLive = Layer.succeed(
  RateLimitStore,
  makeRateLimitStore(process.env),
);

export function runRateLimit<A>(
  program: Effect.Effect<A, RateLimitError, RateLimitStore>,
): Promise<A> {
  return Effect.runPromise(program.pipe(Effect.provide(RateLimitStoreLive)));
}

export function enforceRateLimits(input: {
  readonly identity: string;
  readonly policies: readonly RateLimitPolicy[];
  readonly now?: Date;
}) {
  return Effect.gen(function* () {
    const store = yield* RateLimitStore;
    const now = input.now ?? new Date();
    const decisions: RateLimitDecision[] = [];
    for (const policy of input.policies) {
      const resetAt = resetAtForWindow(now, policy.windowMs);
      const key = rateLimitKey({
        scope: policy.scope,
        identity: input.identity,
        resetAt,
      });
      const count = yield* store.increment({ key, windowMs: policy.windowMs, now });
      if (count > policy.limit) {
        return yield* Effect.fail(new RateLimitExceededError({
          scope: policy.scope,
          limit: policy.limit,
          resetAt,
        }));
      }
      decisions.push({
        scope: policy.scope,
        limit: policy.limit,
        remaining: Math.max(0, policy.limit - count),
        resetAt,
      });
    }
    return decisions;
  });
}

export function vmCreateRateLimitPolicies(env: Record<string, string | undefined> = process.env): readonly RateLimitPolicy[] {
  return [
    {
      scope: "vm:create:burst",
      limit: positiveIntegerEnv(env, "CMUX_VM_CREATE_RATE_LIMIT_BURST", 3),
      windowMs: durationMsEnv(env, "CMUX_VM_CREATE_RATE_LIMIT_BURST_WINDOW_MS", 10 * 60 * 1000),
    },
    {
      scope: "vm:create:daily",
      limit: positiveIntegerEnv(env, "CMUX_VM_CREATE_RATE_LIMIT_DAILY", 20),
      windowMs: durationMsEnv(env, "CMUX_VM_CREATE_RATE_LIMIT_DAILY_WINDOW_MS", 24 * 60 * 60 * 1000),
    },
  ];
}

export function vmControlRateLimitPolicies(env: Record<string, string | undefined> = process.env): readonly RateLimitPolicy[] {
  return [
    {
      scope: "vm:control",
      limit: positiveIntegerEnv(env, "CMUX_VM_CONTROL_RATE_LIMIT_BURST", 600),
      windowMs: durationMsEnv(env, "CMUX_VM_CONTROL_RATE_LIMIT_WINDOW_MS", 60 * 1000),
    },
  ];
}

export function isRateLimitExceededError(err: unknown): err is RateLimitExceededError {
  return (err as { _tag?: string } | null)?._tag === "RateLimitExceededError";
}

export function isRateLimitStoreError(err: unknown): err is RateLimitStoreError {
  return (err as { _tag?: string } | null)?._tag === "RateLimitStoreError";
}

export function rateLimitResponse(error: RateLimitExceededError): Response {
  const retryAfterSeconds = Math.max(1, Math.ceil(error.retryAfterMs / 1000));
  return new Response(JSON.stringify({
    error: "rate_limited",
    scope: error.scope,
    limit: error.limit,
    retryAfterSeconds,
  }), {
    status: 429,
    headers: {
      "content-type": "application/json",
      "retry-after": String(retryAfterSeconds),
      "x-ratelimit-limit": String(error.limit),
      "x-ratelimit-reset": String(Math.ceil(error.resetAt.getTime() / 1000)),
    },
  });
}

export function rateLimitUnavailableResponse(): Response {
  return new Response(JSON.stringify({ error: "rate_limit_unavailable" }), {
    status: 503,
    headers: { "content-type": "application/json" },
  });
}

export function makeRateLimitStore(env: Record<string, string | undefined>): RateLimitStoreShape {
  const explicitDriver = env.CMUX_RATE_LIMIT_DRIVER?.trim().toLowerCase();
  if (explicitDriver === "disabled") return disabledRateLimitStore();
  if (explicitDriver === "memory") return memoryRateLimitStore();

  const redisUrl = env.REDIS_URL?.trim();
  if ((explicitDriver === "redis" || !explicitDriver) && redisUrl) {
    return redisRateLimitStore(redisUrl);
  }

  const upstashUrl = env.UPSTASH_REDIS_REST_URL?.trim() || env.KV_REST_API_URL?.trim();
  const upstashToken = env.UPSTASH_REDIS_REST_TOKEN?.trim() || env.KV_REST_API_TOKEN?.trim();
  if ((explicitDriver === "upstash" || !explicitDriver) && upstashUrl && upstashToken) {
    return upstashRateLimitStore({ url: upstashUrl, token: upstashToken });
  }

  const vercelKvUrl = env.KV_URL?.trim();
  if ((explicitDriver === "redis" || !explicitDriver) && vercelKvUrl) {
    return redisRateLimitStore(vercelKvUrl);
  }

  if (explicitDriver) {
    return unavailableRateLimitStore(`unsupported CMUX_RATE_LIMIT_DRIVER: ${explicitDriver}`);
  }

  return unavailableRateLimitStore("configure REDIS_URL, KV_URL, or Upstash REST env");
}

function redisRateLimitStore(url: string): RateLimitStoreShape {
  let clientPromise: Promise<RedisClientType> | null = null;

  const getClient = async (): Promise<RedisClientType> => {
    clientPromise ??= (async () => {
      const client = createClient({ url });
      client.on("error", () => {});
      await client.connect();
      return client as RedisClientType;
    })();
    return clientPromise;
  };

  return {
    increment: ({ key, windowMs }) =>
      Effect.tryPromise({
        try: async () => {
          const client = await getClient();
          const count = Number(await client.sendCommand(["INCR", key]));
          await client.sendCommand(["PEXPIRE", key, String(Math.max(1, windowMs + 1000)), "NX"]);
          return count;
        },
        catch: (cause) => new RateLimitStoreError({ operation: "redis_increment", cause }),
      }),
  };
}

function upstashRateLimitStore(config: { readonly url: string; readonly token: string }): RateLimitStoreShape {
  return {
    increment: ({ key, windowMs }) =>
      Effect.tryPromise({
        try: async () => {
          const response = await fetch(`${config.url.replace(/\/$/, "")}/pipeline`, {
            method: "POST",
            headers: {
              authorization: `Bearer ${config.token}`,
              "content-type": "application/json",
            },
            body: JSON.stringify([
              ["INCR", key],
              ["PEXPIRE", key, String(Math.max(1, windowMs + 1000)), "NX"],
            ]),
          });
          if (!response.ok) {
            throw new Error(`Upstash Redis returned HTTP ${response.status}`);
          }
          const data = await response.json() as readonly { result?: unknown; error?: string }[];
          const first = data[0];
          if (!first || first.error) {
            throw new Error(first?.error ?? "Upstash Redis increment returned no result");
          }
          return Number(first.result);
        },
        catch: (cause) => new RateLimitStoreError({ operation: "upstash_increment", cause }),
      }),
  };
}

function memoryRateLimitStore(): RateLimitStoreShape {
  const counters = new Map<string, { count: number; expiresAt: number }>();
  return {
    increment: ({ key, windowMs, now }) =>
      Effect.sync(() => {
        const current = counters.get(key);
        if (!current || current.expiresAt <= now.getTime()) {
          counters.set(key, { count: 1, expiresAt: now.getTime() + windowMs + 1000 });
          return 1;
        }
        current.count += 1;
        return current.count;
      }),
  };
}

function disabledRateLimitStore(): RateLimitStoreShape {
  return {
    increment: () => Effect.succeed(1),
  };
}

function unavailableRateLimitStore(message: string): RateLimitStoreShape {
  return {
    increment: () => Effect.fail(new RateLimitStoreError({
      operation: "rate_limit_unconfigured",
      cause: new Error(message),
    })),
  };
}

function rateLimitKey(input: { readonly scope: string; readonly identity: string; readonly resetAt: Date }): string {
  const identityHash = createHash("sha256").update(input.identity).digest("hex").slice(0, 32);
  return `cmux:rl:v1:${input.scope}:${identityHash}:${Math.floor(input.resetAt.getTime() / 1000)}`;
}

function resetAtForWindow(now: Date, windowMs: number): Date {
  const timestamp = now.getTime();
  return new Date(Math.floor(timestamp / windowMs) * windowMs + windowMs);
}

function positiveIntegerEnv(env: Record<string, string | undefined>, key: string, fallback: number): number {
  const raw = env[key]?.trim();
  if (!raw) return fallback;
  if (!/^\d+$/.test(raw)) throw new Error(`${key} must be a positive integer`);
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`${key} must be a positive integer`);
  return parsed;
}

function durationMsEnv(env: Record<string, string | undefined>, key: string, fallback: number): number {
  return positiveIntegerEnv(env, key, fallback);
}
