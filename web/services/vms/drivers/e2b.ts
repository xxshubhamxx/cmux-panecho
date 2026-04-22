import { Sandbox } from "e2b";
import {
  ProviderError,
  type CreateOptions,
  type ExecResult,
  type SSHEndpoint,
  type SnapshotRef,
  type VMHandle,
  type VMProvider,
} from "./types";
import { withVmSpan } from "../telemetry";

// Default cmux-sandbox template. Built from scratch/vm-experiments/images/build-e2b.ts and
// kept in sync via the E2B_SANDBOX_TEMPLATE env var. The template already bakes sshd, mutagen-agent,
// git, and the `cmux` user; sshd is started on demand by openSSH (not as the E2B start command,
// because E2B sandboxes run unprivileged and can't bind port 22).
const DEFAULT_TEMPLATE = process.env.E2B_SANDBOX_TEMPLATE ?? "cmux-sandbox:v0-71a954b8e53b";

export class E2BProvider implements VMProvider {
  readonly id = "e2b" as const;

  async create(options: CreateOptions): Promise<VMHandle> {
    const image = options.image || DEFAULT_TEMPLATE;
    return withVmSpan(
      "cmux.vm.provider.create",
      {
        "cmux.vm.provider": "e2b",
        "cmux.vm.operation": "create",
        "cmux.vm.image_set": image.length > 0,
      },
      async (span) => {
        try {
          const sandbox = await Sandbox.create(image);
          span.setAttribute("cmux.vm.id", sandbox.sandboxId);
          return {
            provider: "e2b",
            providerVmId: sandbox.sandboxId,
            status: "running",
            image,
            createdAt: Date.now(),
          };
        } catch (err) {
          throw new ProviderError("e2b", `create(${image}) failed`, err);
        }
      },
    );
  }

  async destroy(vmId: string): Promise<void> {
    await withVmSpan(
      "cmux.vm.provider.destroy",
      { "cmux.vm.provider": "e2b", "cmux.vm.operation": "destroy", "cmux.vm.id": vmId },
      async () => {
        await Sandbox.kill(vmId);
      },
    );
  }

  async pause(vmId: string): Promise<void> {
    await withVmSpan(
      "cmux.vm.provider.pause",
      { "cmux.vm.provider": "e2b", "cmux.vm.operation": "pause", "cmux.vm.id": vmId },
      async () => {
        await Sandbox.pause(vmId);
      },
    );
  }

  async resume(vmId: string): Promise<VMHandle> {
    return withVmSpan(
      "cmux.vm.provider.resume",
      { "cmux.vm.provider": "e2b", "cmux.vm.operation": "resume", "cmux.vm.id": vmId },
      async () => {
        const sbx = await Sandbox.connect(vmId);
        const info = await Sandbox.getInfo(vmId);
        return {
          provider: "e2b",
          providerVmId: sbx.sandboxId,
          status: "running",
          image: info.templateId,
          createdAt: info.startedAt.getTime(),
        };
      },
    );
  }

  async exec(vmId: string, command: string, opts?: { timeoutMs?: number }): Promise<ExecResult> {
    const timeoutMs = opts?.timeoutMs ?? 30_000;
    return withVmSpan(
      "cmux.vm.provider.exec",
      {
        "cmux.vm.provider": "e2b",
        "cmux.vm.operation": "exec",
        "cmux.vm.id": vmId,
        "cmux.command_length": command.length,
        "cmux.timeout_ms": timeoutMs,
      },
      async (span) => {
        const sbx = await Sandbox.connect(vmId);
        const r = await sbx.commands.run(command, { timeoutMs });
        span.setAttribute("cmux.exec.exit_code", r.exitCode);
        return { exitCode: r.exitCode, stdout: r.stdout, stderr: r.stderr };
      },
    );
  }

  async snapshot(vmId: string, name?: string): Promise<SnapshotRef> {
    return withVmSpan(
      "cmux.vm.provider.snapshot",
      {
        "cmux.vm.provider": "e2b",
        "cmux.vm.operation": "snapshot",
        "cmux.vm.id": vmId,
        "cmux.snapshot.named": !!name,
      },
      async (span) => {
        const sbx = await Sandbox.connect(vmId);
        const snap = await sbx.createSnapshot();
        const id =
          (snap as { snapshotId?: string }).snapshotId ??
          (snap as { snapshot_id?: string }).snapshot_id ??
          JSON.stringify(snap);
        span.setAttribute("cmux.snapshot.id", id);
        return { id, createdAt: Date.now(), name };
      },
    );
  }

  async restore(snapshotId: string): Promise<VMHandle> {
    return withVmSpan(
      "cmux.vm.provider.restore",
      { "cmux.vm.provider": "e2b", "cmux.vm.operation": "restore", "cmux.snapshot.id": snapshotId },
      async (span) => {
        const sbx = await Sandbox.create(snapshotId);
        span.setAttribute("cmux.vm.id", sbx.sandboxId);
        return {
          provider: "e2b",
          providerVmId: sbx.sandboxId,
          status: "running",
          image: snapshotId,
          createdAt: Date.now(),
        };
      },
    );
  }

  async openSSH(vmId: string): Promise<SSHEndpoint> {
    return withVmSpan(
      "cmux.vm.provider.open_ssh",
      { "cmux.vm.provider": "e2b", "cmux.vm.operation": "open_ssh", "cmux.vm.id": vmId },
      async () => {
        // E2B sandboxes expose ports only via https://<port>-<sandbox-id>.e2b.app — they don't
        // route raw TCP/22 from outside, so mac client can't SSH directly into an E2B VM.
        // cmux's interactive paths (`cmux vm new` shell, `cmux vm new --workspace`) require
        // direct SSH + cmuxd-remote, so we surface a user-facing error. Use --provider freestyle
        // for interactive work, or `cmux vm new --provider e2b --detach` for scratch exec.
        throw new ProviderError(
          "e2b",
          "E2B sandboxes don't support interactive attach (no raw TCP egress). " +
            "Use `cmux vm new` without `--provider e2b` (Freestyle is the default), " +
            "or `cmux vm new --provider e2b --detach` to create without attach, " +
            "then `cmux vm exec <id> -- <cmd>`.",
        );
      },
    );
  }

  async revokeSSHIdentity(identityHandle: string): Promise<void> {
    void identityHandle;
    // E2B doesn't mint per-session credentials — openSSH always throws — so there's
    // nothing to revoke. Defined to satisfy VMProvider; never called against this driver.
  }
}
