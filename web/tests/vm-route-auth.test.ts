import { beforeEach, describe, expect, mock, test } from "bun:test";

const getUser = mock(async () => null);
const createClient = mock(() => {
  throw new Error("unauthenticated VM routes must not create a Rivet client");
});

mock.module("../app/lib/stack", () => ({
  stackServerApp: { getUser },
}));

mock.module("rivetkit/client", () => ({
  createClient,
}));

const { POST } = await import("../app/api/vm/route");

beforeEach(() => {
  getUser.mockClear();
  getUser.mockResolvedValue(null);
  createClient.mockClear();
});

describe("VM REST auth", () => {
  test("rejects unauthenticated provisioning before reaching Rivet or providers", async () => {
    const response = await POST(
      new Request("https://cmux.test/api/vm", {
        method: "POST",
        body: JSON.stringify({ provider: "freestyle" }),
      }),
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(getUser).toHaveBeenCalled();
    expect(createClient).not.toHaveBeenCalled();
  });

  test("requires forwarded Stack credentials before opening a Rivet actor handle", async () => {
    getUser.mockResolvedValue({
      id: "user-1",
      displayName: null,
      primaryEmail: "user@example.com",
    });

    const response = await POST(
      new Request("https://cmux.test/api/vm", {
        method: "POST",
        body: JSON.stringify({ provider: "freestyle" }),
      }),
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(createClient).not.toHaveBeenCalled();
  });
});
