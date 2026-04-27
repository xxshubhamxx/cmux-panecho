import { describe, expect, test } from "bun:test";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import {
  RateLimitExceededError,
  RateLimitStore,
  enforceRateLimits,
  makeRateLimitStore,
  type RateLimitStoreShape,
} from "../services/rateLimit";

function runWithStore(
  store: RateLimitStoreShape,
  identity: string,
  now: Date,
) {
  return Effect.runPromise(
    enforceRateLimits({
      identity,
      now,
      policies: [{ scope: "test:window", limit: 2, windowMs: 1000 }],
    }).pipe(Effect.provide(Layer.succeed(RateLimitStore, store))),
  );
}

function runFailureWithStore(
  store: RateLimitStoreShape,
  identity: string,
  now: Date,
) {
  return Effect.runPromise(
    enforceRateLimits({
      identity,
      now,
      policies: [{ scope: "test:window", limit: 2, windowMs: 1000 }],
    }).pipe(
      Effect.flip,
      Effect.provide(Layer.succeed(RateLimitStore, store)),
    ),
  );
}

describe("rate limits", () => {
  test("memory store enforces a fixed window", async () => {
    const store = makeRateLimitStore({ CMUX_RATE_LIMIT_DRIVER: "memory" });
    const identity = `user-${crypto.randomUUID()}`;
    const now = new Date(1_800_000_000_000);

    await expect(runWithStore(store, identity, now)).resolves.toHaveLength(1);
    await expect(runWithStore(store, identity, now)).resolves.toHaveLength(1);

    const error = await runFailureWithStore(store, identity, now);
    expect(error).toBeInstanceOf(RateLimitExceededError);

    await expect(runWithStore(store, identity, new Date(now.getTime() + 1000))).resolves.toHaveLength(1);
  });

  const redisTest = process.env.CMUX_REDIS_TEST === "1" ? test : test.skip;

  redisTest("Redis store enforces a fixed window against local Docker Redis", async () => {
    const redisUrl = process.env.REDIS_URL;
    if (!redisUrl) throw new Error("REDIS_URL is required when CMUX_REDIS_TEST=1");
    const store = makeRateLimitStore({ REDIS_URL: redisUrl });
    const identity = `redis-user-${crypto.randomUUID()}`;
    const now = new Date(1_800_000_001_000);

    await expect(runWithStore(store, identity, now)).resolves.toHaveLength(1);
    await expect(runWithStore(store, identity, now)).resolves.toHaveLength(1);

    const error = await runFailureWithStore(store, identity, now);
    expect(error).toBeInstanceOf(RateLimitExceededError);
  });
});
