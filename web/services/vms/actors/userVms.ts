import { actor } from "rivetkit";
import { defaultProviderId, getProvider, type ProviderId } from "../drivers";
import type { registry } from "../registry";
import {
  setSpanAttributes,
  withRivetActorSpan,
  type MaybeAttributes,
  type SpanCallback,
} from "../telemetry";

export type UserVmEntry = {
  providerVmId: string; // the provider's own id — also the vmActor actor key
  provider: ProviderId;
  image: string;
  createdAt: number;
  /**
   * Client-supplied idempotency key, stored so a retry with the same key returns the
   * existing VM instead of provisioning a second paid one. Undefined when the client
   * didn't pass a key (best-effort behaviour, older CLI/curl users).
   */
  idempotencyKey?: string;
};

export type UserVmsState = {
  vms: UserVmEntry[];
};

const VM_CREATE_ACTION_TIMEOUT_MS = 16 * 60 * 1000;

// One coordinator per Stack Auth user. Tracks `{providerVmId, provider, image}` for every VM
// this user owns. We use the provider's own id everywhere — no cmux UUID layer on top.
// Rationale: both Freestyle (`ob7ho8876hklod2xizof`) and E2B (`i453t8zwgbo38qqlmsgsl`) mint
// 20-char alphanumeric ids already; stacking a UUID on top just muddies CLI output and docs.
export const userVmsActor = actor({
  options: {
    name: "UserVMs",
    icon: "users",
    actionTimeout: VM_CREATE_ACTION_TIMEOUT_MS,
  },

  state: { vms: [] } as UserVmsState,

  actions: {
    list: async (c) => {
      return withUserVmsActorSpan(c, "list", {}, () => c.state.vms);
    },

    create: async (
      c,
      opts: { image?: string; provider?: ProviderId; idempotencyKey?: string },
    ): Promise<UserVmEntry> => {
      return withUserVmsActorSpan(
        c,
        "create",
        {
          "cmux.vm.provider": opts.provider ?? defaultProviderId(),
          "cmux.vm.image_set": !!opts.image,
          "cmux.idempotency_key_set": !!opts.idempotencyKey?.trim(),
        },
        async (span): Promise<UserVmEntry> => {
          // Idempotency: a client retry (network hiccup, timeout, bad Wi-Fi) previously got a
          // second paid provider VM for the same logical request. If the caller sent a key and
          // we already have a VM tracked under it for this user, return that entry unchanged —
          // the RivetKit runtime serializes actions per actor, so the second call is guaranteed
          // to see whatever state the first call committed.
          const idempotencyKey = opts.idempotencyKey?.trim();
          if (idempotencyKey) {
            const existing = c.state.vms.find((v) => v.idempotencyKey === idempotencyKey);
            if (existing) {
              setSpanAttributes(span, {
                "cmux.idempotency_reused": true,
                "cmux.vm.id": existing.providerVmId,
                "cmux.vm.provider": existing.provider,
              });
              return existing;
            }
          }
          const provider = opts.provider ?? defaultProviderId();
          setSpanAttributes(span, { "cmux.vm.provider": provider });
          // Provision the provider VM directly, then spawn a vmActor keyed on the provider id.
          // This avoids the vmActor.onCreate -> driver.create round trip (which used an extra
          // cmux-owned UUID) and means the actor key equals the provider id.
          const driver = getProvider(provider);
          const handle = await driver.create({ image: opts.image ?? "" });
          const entry: UserVmEntry = {
            providerVmId: handle.providerVmId,
            provider,
            image: handle.image,
            createdAt: handle.createdAt,
            idempotencyKey: idempotencyKey || undefined,
          };
          setSpanAttributes(span, { "cmux.vm.id": entry.providerVmId });
          const client = c.client<typeof registry>();
          try {
            await client.vmActor.create([entry.providerVmId], {
              input: {
                userId: c.key[0] as string,
                provider,
                providerVmId: entry.providerVmId,
                image: entry.image,
              },
            });
          } catch (actorCreateError) {
            setSpanAttributes(span, { "cmux.rivet.actor_create_failed": true });
            // vmActor.create failed *after* the provider already provisioned the VM. Without a
            // rollback, that VM lives on forever as an orphan (costing the user and cluttering
            // the Freestyle/E2B dashboard). Best-effort destroy + rethrow so the caller sees
            // the actor creation failure. If rollback also fails, preserve the provider entry
            // so a later delete can retry cleanup instead of losing the only handle.
            try {
              await driver.destroy(entry.providerVmId);
            } catch (rollbackError) {
              setSpanAttributes(span, { "cmux.vm.rollback_failed": true });
              if (!c.state.vms.some((v) => v.providerVmId === entry.providerVmId)) {
                c.state.vms.push(entry);
                await c.saveState({ immediate: true });
              }
              console.error(
                "userVmsActor.create: failed to roll back provider VM after vmActor.create error; preserving tracking for retry cleanup",
                { providerVmId: entry.providerVmId, provider, rollbackError },
              );
            }
            throw actorCreateError;
          }
          c.state.vms.push(entry);
          setSpanAttributes(span, { "cmux.vm.count": c.state.vms.length });
          return entry;
        },
      );
    },

    forget: async (c, providerVmId: string) => {
      await withUserVmsActorSpan(
        c,
        "forget",
        { "cmux.vm.id": providerVmId },
        (span) => {
          const before = c.state.vms.length;
          c.state.vms = c.state.vms.filter((v) => v.providerVmId !== providerVmId);
          setSpanAttributes(span, {
            "cmux.vm.forgot": c.state.vms.length !== before,
            "cmux.vm.count": c.state.vms.length,
          });
        },
      );
    },
  },
});

function withUserVmsActorSpan<T>(
  c: { state: UserVmsState },
  actionName: string,
  attributes: MaybeAttributes,
  fn: SpanCallback<T>,
): Promise<T> {
  return withRivetActorSpan(
    "userVmsActor",
    actionName,
    { "cmux.vm.count": c.state.vms.length, ...attributes },
    fn,
  );
}
