import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import {
  RIVET_INTERNAL_HEADER,
  assertRivetInternal,
  makeActorAuthParams,
  requireActorAuth,
  requireRivetPrivateEndpointForPublicStart,
} from "../services/vms/rivetSecurity";

const originalEnv = { ...process.env };

beforeEach(() => {
  process.env = { ...originalEnv, CMUX_RIVET_INTERNAL_SECRET: "test-rivet-secret" };
});

afterEach(() => {
  process.env = { ...originalEnv };
});

describe("VM Rivet auth", () => {
  test("accepts only the configured internal gateway header", () => {
    const missing = new Request("https://cmux.test/api/rivet/metadata");
    expect(assertRivetInternal(missing)).toBe(false);

    const wrong = new Request("https://cmux.test/api/rivet/metadata", {
      headers: { [RIVET_INTERNAL_HEADER]: "wrong-secret" },
    });
    expect(assertRivetInternal(wrong)).toBe(false);

    const valid = new Request("https://cmux.test/api/rivet/metadata", {
      headers: { [RIVET_INTERNAL_HEADER]: "test-rivet-secret" },
    });
    expect(assertRivetInternal(valid)).toBe(true);
  });

  test("requires signed actor params for the expected Stack user", () => {
    const signed = makeActorAuthParams("user-1");
    expect(requireActorAuth(signed, "user-1")).toEqual(signed);

    expect(() => requireActorAuth(undefined, "user-1")).toThrow("Unauthorized");
    expect(() => requireActorAuth(signed, "user-2")).toThrow("Unauthorized");
    expect(() => requireActorAuth({ ...signed, sig: "bad-signature" }, "user-1")).toThrow(
      "Unauthorized",
    );
  });

  test("requires a private Rivet endpoint before exposing public serverless start in deployed envs", () => {
    process.env = { ...process.env, NODE_ENV: "production" };
    delete process.env.RIVET_ENDPOINT;
    delete process.env.RIVET_TOKEN;
    delete process.env.RIVET_NAMESPACE;

    expect(() => requireRivetPrivateEndpointForPublicStart()).toThrow(
      "RIVET_ENDPOINT or RIVET_TOKEN/RIVET_NAMESPACE must be set",
    );

    process.env.RIVET_ENDPOINT = "https://example.rivet.dev/sk_test";
    expect(() => requireRivetPrivateEndpointForPublicStart()).not.toThrow();
  });
});
