import { Freestyle } from "freestyle";
import {
  ProviderError,
  type CreateOptions,
  type ExecResult,
  type AttachEndpoint,
  type SSHEndpoint,
  type SnapshotRef,
  type VMHandle,
  type VMProvider,
  type VMStatus,
} from "./types";
import {
  recordSpanError,
  setSpanAttributes,
  withVmSpan,
} from "../telemetry";

// Default cmux-sandbox snapshot. Produced by scratch/vm-experiments/images/build-freestyle.ts.
// Override via FREESTYLE_SANDBOX_SNAPSHOT. Image bakes sshd + cmuxd-remote + mutagen-agent.
export const DEFAULT_FREESTYLE_SNAPSHOT_ID = "sc-4t27vve1xgwyewhxtbzj";

function defaultSnapshotId(): string {
  return process.env.FREESTYLE_SANDBOX_SNAPSHOT?.trim() || DEFAULT_FREESTYLE_SNAPSHOT_ID;
}

// Freestyle VMs reach the outside world only via their SSH gateway, which terminates on
// `vm-ssh.freestyle.sh:22`. `ssh <vmId>+<user>@vm-ssh.freestyle.sh` authenticates against
// an identity token the backend mints per attach session (short TTL, revoked on rm).
const SSH_HOST = "vm-ssh.freestyle.sh";
const SSH_PORT = 22;
const CMUX_LINUX_USER = "cmux"; // must match Resources/install.sh in scratch/vm-experiments

const DEFAULT_TIMEOUT_MS = 60_000;
const CREATE_TIMEOUT_MS = 15 * 60 * 1000;
const SNAPSHOT_TIMEOUT_MS = 15 * 60 * 1000;
const EXEC_OVERHEAD_TIMEOUT_MS = 15_000;
const MAX_EXEC_TIMEOUT_MS = 15 * 60 * 1000;

function client(timeoutMs = DEFAULT_TIMEOUT_MS): Freestyle {
  const longFetch: typeof fetch = (input, init) =>
    fetch(input as Request, { ...(init ?? {}), signal: AbortSignal.timeout(timeoutMs) });
  return new Freestyle({ fetch: longFetch });
}

function normalizeExecTimeout(timeoutMs: number | undefined): number {
  if (typeof timeoutMs !== "number" || !Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    return 30_000;
  }
  return Math.min(Math.floor(timeoutMs), MAX_EXEC_TIMEOUT_MS);
}

function mapStatus(state: string | null | undefined): VMStatus {
  switch (state) {
    case "starting":
      return "creating";
    case "running":
      return "running";
    case "suspending":
    case "suspended":
      return "paused";
    case "stopped":
      return "destroyed";
    default:
      return "running";
  }
}

export class FreestyleProvider implements VMProvider {
  readonly id = "freestyle" as const;

  async create(options: CreateOptions): Promise<VMHandle> {
    const image = options.image || defaultSnapshotId();
    return withVmSpan(
      "cmux.vm.provider.create",
      {
        "cmux.vm.provider": "freestyle",
        "cmux.vm.operation": "create",
        "cmux.vm.image_set": image.length > 0,
        "cmux.timeout_ms": CREATE_TIMEOUT_MS,
      },
      async (span) => {
        const fs = client(CREATE_TIMEOUT_MS);
        try {
          const body: Parameters<typeof fs.vms.create>[0] = image
            ? { snapshotId: image }
            : {};
          // Build images can take several minutes if the snapshot cache misses.
          const created = await fs.vms.create({
            ...body,
            readySignalTimeoutSeconds: 600,
          });
          setSpanAttributes(span, { "cmux.vm.id": created.vmId });
          return {
            provider: "freestyle",
            providerVmId: created.vmId,
            status: "running",
            image: image || "freestyle:default",
            createdAt: Date.now(),
          };
        } catch (err) {
          throw new ProviderError("freestyle", `create(${image || "<default>"})`, err);
        }
      },
    );
  }

  async destroy(vmId: string): Promise<void> {
    return withVmSpan(
      "cmux.vm.provider.destroy",
      {
        "cmux.vm.provider": "freestyle",
        "cmux.vm.operation": "destroy",
        "cmux.vm.id": vmId,
        "cmux.timeout_ms": DEFAULT_TIMEOUT_MS,
      },
      async () => {
        try {
          const fs = client();
          const ref = fs.vms.ref({ vmId });
          await ref.delete();
        } catch (err) {
          throw new ProviderError("freestyle", `destroy(${vmId})`, err);
        }
      },
    );
  }

  async pause(vmId: string): Promise<void> {
    return withVmSpan(
      "cmux.vm.provider.pause",
      {
        "cmux.vm.provider": "freestyle",
        "cmux.vm.operation": "pause",
        "cmux.vm.id": vmId,
        "cmux.timeout_ms": DEFAULT_TIMEOUT_MS,
      },
      async () => {
        try {
          const fs = client();
          const ref = fs.vms.ref({ vmId });
          await ref.suspend();
        } catch (err) {
          throw new ProviderError("freestyle", `pause(${vmId})`, err);
        }
      },
    );
  }

  async resume(vmId: string): Promise<VMHandle> {
    return withVmSpan(
      "cmux.vm.provider.resume",
      {
        "cmux.vm.provider": "freestyle",
        "cmux.vm.operation": "resume",
        "cmux.vm.id": vmId,
        "cmux.timeout_ms": DEFAULT_TIMEOUT_MS,
      },
      async (span) => {
        try {
          const fs = client();
          const ref = fs.vms.ref({ vmId });
          await ref.start();
          const info = await ref.getInfo();
          const status = mapStatus(info.state);
          setSpanAttributes(span, { "cmux.vm.provider_state": info.state, "cmux.vm.status": status });
          return {
            provider: "freestyle",
            providerVmId: info.id,
            status,
            image: "freestyle:resumed",
            createdAt: Date.now(),
          };
        } catch (err) {
          throw new ProviderError("freestyle", `resume(${vmId})`, err);
        }
      },
    );
  }

  async exec(
    vmId: string,
    command: string,
    opts?: { timeoutMs?: number },
  ): Promise<ExecResult> {
    const timeoutMs = normalizeExecTimeout(opts?.timeoutMs);
    return withVmSpan(
      "cmux.vm.provider.exec",
      {
        "cmux.vm.provider": "freestyle",
        "cmux.vm.operation": "exec",
        "cmux.vm.id": vmId,
        "cmux.command_length": command.length,
        "cmux.timeout_ms": timeoutMs,
      },
      async (span) => {
        try {
          const fs = client(timeoutMs + EXEC_OVERHEAD_TIMEOUT_MS);
          const ref = fs.vms.ref({ vmId });
          const r = await ref.exec({ command, timeoutMs });
          const exitCode = (r as { statusCode?: number }).statusCode ?? 0;
          setSpanAttributes(span, { "cmux.exec.exit_code": exitCode });
          // ResponsePostV1VmsVmIdExecAwait200 shape: { stdout, stderr, statusCode }
          return {
            exitCode,
            stdout: (r as { stdout?: string | null }).stdout ?? "",
            stderr: (r as { stderr?: string | null }).stderr ?? "",
          };
        } catch (err) {
          throw new ProviderError("freestyle", `exec(${vmId})`, err);
        }
      },
    );
  }

  async snapshot(vmId: string, name?: string): Promise<SnapshotRef> {
    return withVmSpan(
      "cmux.vm.provider.snapshot",
      {
        "cmux.vm.provider": "freestyle",
        "cmux.vm.operation": "snapshot",
        "cmux.vm.id": vmId,
        "cmux.snapshot.named": !!name,
        "cmux.timeout_ms": SNAPSHOT_TIMEOUT_MS,
      },
      async (span) => {
        try {
          const fs = client(SNAPSHOT_TIMEOUT_MS);
          const ref = fs.vms.ref({ vmId });
          const out = await ref.snapshot(name ? { name } : undefined);
          const id =
            (out as { snapshotId?: string }).snapshotId ??
            (out as { id?: string }).id ??
            "";
          if (!id) throw new Error("snapshot response missing snapshotId");
          setSpanAttributes(span, { "cmux.snapshot.id": id });
          return { id, createdAt: Date.now(), name };
        } catch (err) {
          throw new ProviderError("freestyle", `snapshot(${vmId})`, err);
        }
      },
    );
  }

  async restore(snapshotId: string): Promise<VMHandle> {
    return withVmSpan(
      "cmux.vm.provider.restore",
      {
        "cmux.vm.provider": "freestyle",
        "cmux.vm.operation": "restore",
        "cmux.snapshot.id": snapshotId,
        "cmux.timeout_ms": CREATE_TIMEOUT_MS,
      },
      async (span) => {
        try {
          const fs = client(CREATE_TIMEOUT_MS);
          const created = await fs.vms.create({ snapshotId });
          setSpanAttributes(span, { "cmux.vm.id": created.vmId });
          return {
            provider: "freestyle",
            providerVmId: created.vmId,
            status: "running",
            image: snapshotId,
            createdAt: Date.now(),
          };
        } catch (err) {
          throw new ProviderError("freestyle", `restore(${snapshotId})`, err);
        }
      },
    );
  }

  /**
   * Mint a short-lived SSH token + permission scoped to this VM, return the endpoint the mac
   * client will dial. Freestyle's gateway terminates at `vm-ssh.freestyle.sh:22`, username is
   * `<vmId>+<linuxUser>`, password is the access token we just minted.
   */
  async openAttach(vmId: string): Promise<AttachEndpoint> {
    return await this.openSSH(vmId);
  }

  async openSSH(vmId: string): Promise<SSHEndpoint> {
    return withVmSpan(
      "cmux.vm.provider.open_ssh",
      {
        "cmux.vm.provider": "freestyle",
        "cmux.vm.operation": "open_ssh",
        "cmux.vm.id": vmId,
        "cmux.timeout_ms": DEFAULT_TIMEOUT_MS,
      },
      async (span) => {
        const fs = client();
        // A fresh identity per attach session. `vmActor` persists the identityId so it can
        // call `revokeSSHIdentity` on VM destroy / before minting a replacement, otherwise
        // every `cmux vm shell` invocation would leak a live credential under the Freestyle
        // account indefinitely.
        let identity: Awaited<ReturnType<typeof fs.identities.create>>["identity"] | undefined;
        let identityId = "";
        try {
          const created = await fs.identities.create({});
          identity = created.identity;
          identityId = created.identityId;
          setSpanAttributes(span, { "cmux.ssh.identity_created": true });
          await identity.permissions.vms.grant({
            vmId,
            allowedUsers: [CMUX_LINUX_USER],
          });
          const { token } = await identity.tokens.create();
          return {
            transport: "ssh",
            host: SSH_HOST,
            port: SSH_PORT,
            username: `${vmId}+${CMUX_LINUX_USER}`,
            publicKeyFingerprint: null,
            credential: { kind: "password", value: token },
            identityHandle: identityId,
          };
        } catch (err) {
          // Without this, an identity created above but failed-on afterwards (grant or token
          // mint threw) leaks. Best-effort delete before rethrowing.
          if (identityId) {
            try {
              await fs.identities.delete({ identityId });
            } catch (cleanupError) {
              recordSpanError(span, cleanupError);
            }
          }
          throw new ProviderError("freestyle", `openSSH(${vmId})`, err);
        }
      },
    );
  }

  async revokeSSHIdentity(identityHandle: string): Promise<void> {
    if (!identityHandle) return;
    await withVmSpan(
      "cmux.vm.provider.revoke_ssh_identity",
      {
        "cmux.vm.provider": "freestyle",
        "cmux.vm.operation": "revoke_ssh_identity",
        "cmux.timeout_ms": DEFAULT_TIMEOUT_MS,
      },
      async (span) => {
        try {
          await client().identities.delete({ identityId: identityHandle });
        } catch (err) {
          // Best effort: identity may already be gone (e.g. VM was destroyed by the provider
          // itself). Don't let cleanup failures cascade into the caller, but keep it visible.
          recordSpanError(span, err);
        }
      },
    );
  }
}
