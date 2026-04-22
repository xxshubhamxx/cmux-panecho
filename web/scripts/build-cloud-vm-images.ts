#!/usr/bin/env bun
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  Template,
  defaultBuildLogger,
  waitForURL,
} from "e2b";
import { Freestyle } from "freestyle";

type Target = "e2b" | "freestyle" | "all";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(webRoot, "..");
const buildRoot = path.join(webRoot, ".cmux-cloud-build");

function argValue(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  if (index === -1) return undefined;
  return process.argv[index + 1];
}

function hasFlag(name: string): boolean {
  return process.argv.includes(name);
}

function defaultTag(): string {
  const stamp = new Date().toISOString()
    .replace(/[-:]/g, "")
    .replace(/\..+$/, "")
    .replace("T", "-");
  return `ws-${stamp}`;
}

const target = (argValue("--target") ?? "all") as Target;
if (!["e2b", "freestyle", "all"].includes(target)) {
  throw new Error("--target must be e2b, freestyle, or all");
}
const tag = (argValue("--tag") ?? defaultTag()).trim();
const skipCache = hasFlag("--skip-cache");
const binaryPath = path.join(buildRoot, tag, "cmuxd-remote-linux-amd64");

mkdirSync(path.dirname(binaryPath), { recursive: true });

await buildRemoteDaemon(binaryPath);

const output: Record<string, unknown> = {
  tag,
  binaryPath,
};

if (target === "e2b" || target === "all") {
  output.e2b = await buildE2BTemplate(tag, binaryPath, skipCache);
}
if (target === "freestyle" || target === "all") {
  output.freestyle = await buildFreestyleSnapshot(tag, binaryPath, skipCache);
}

console.log(JSON.stringify(output, null, 2));

async function buildRemoteDaemon(outPath: string): Promise<void> {
  await runCommand(
    "go",
    ["build", "-trimpath", "-ldflags=-s -w", "-o", outPath, "./cmd/cmuxd-remote"],
    {
      cwd: path.join(repoRoot, "daemon/remote"),
      env: { GOOS: "linux", GOARCH: "amd64", CGO_ENABLED: "0" },
    },
  );
}

async function buildE2BTemplate(tag: string, daemonPath: string, skipCache: boolean): Promise<unknown> {
  if (!process.env.E2B_API_KEY) {
    throw new Error("E2B_API_KEY is required to build the E2B template");
  }
  const fileContextPath = path.dirname(daemonPath);
  const template = Template({ fileContextPath })
    .fromUbuntuImage("24.04")
    .aptInstall(["bash", "ca-certificates", "curl", "git"], { noInstallRecommends: true })
    .setEnvs({ LANG: "C.UTF-8" })
    .copy(path.basename(daemonPath), "/usr/local/bin/cmuxd-remote", {
      forceUpload: true,
      mode: 0o755,
    })
    .runCmd([
      "useradd -m -s /bin/bash cmux || true",
      "install -d -m 0700 /tmp/cmux",
    ], { user: "root" })
    .setStartCmd(
      "/usr/local/bin/cmuxd-remote serve --ws --listen 0.0.0.0:7777 --auth-lease-file /tmp/cmux/attach-lease.json --shell /bin/bash",
      waitForURL("http://127.0.0.1:7777/healthz", 200),
    );

  const name = `cmuxd-ws:${tag}`;
  const result = await Template.build(template, name, {
    cpuCount: 2,
    memoryMB: 2048,
    skipCache,
    onBuildLogs: defaultBuildLogger({ minLevel: "info" }),
  });
  return { name, result };
}

async function buildFreestyleSnapshot(tag: string, daemonPath: string, skipCache: boolean): Promise<unknown> {
  if (!process.env.FREESTYLE_API_KEY) {
    throw new Error("FREESTYLE_API_KEY is required to build the Freestyle snapshot");
  }
  const daemonURL = await remoteDaemonBuildURL(tag, daemonPath);
  const fs = new Freestyle();
  const name = `cmuxd-ws-${tag}`;
  const result = await fs.vms.snapshots.create({
    name,
    template: {
      baseImage: {
        dockerfileContent: [
          "FROM ubuntu:24.04",
          "ENV LANG=C.UTF-8",
          "RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bash ca-certificates curl git && rm -rf /var/lib/apt/lists/*",
          `RUN curl -fsSL ${shellQuote(daemonURL)} -o /usr/local/bin/cmuxd-remote && chmod 0755 /usr/local/bin/cmuxd-remote`,
          "RUN useradd -m -s /bin/bash cmux || true",
          "RUN install -d -m 0700 /tmp/cmux",
        ].join("\n"),
      },
      ports: [{ port: 443, targetPort: 7777 }],
      systemd: {
        services: [{
          name: "cmuxd-ws",
          mode: "service",
          exec: [
            "/usr/local/bin/cmuxd-remote serve --ws --listen 0.0.0.0:7777 --auth-lease-file /tmp/cmux/attach-lease.json --shell /bin/bash",
          ],
          user: "root",
          enable: true,
          restartPolicy: { policy: "always", restartSec: 1 },
        }],
      },
      discriminator: `cmuxd-ws-${tag}`,
      skipCache,
    },
  });
  return {
    name,
    daemonURL: daemonURL.includes("X-Amz-") ? "<presigned-r2-url>" : daemonURL,
    result,
  };
}

async function remoteDaemonBuildURL(tag: string, daemonPath: string): Promise<string> {
  const explicit = process.env.CMUX_REMOTE_DAEMON_BUILD_URL?.trim();
  if (explicit) return explicit;

  const required = [
    "R2_ENDPOINT",
    "R2_BUCKET_NAME",
    "R2_PUBLIC_URL",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
  ];
  const missing = required.filter((key) => !process.env[key]?.trim());
  if (missing.length > 0) {
    throw new Error(
      `Freestyle snapshot build needs CMUX_REMOTE_DAEMON_BUILD_URL or R2 env vars; missing ${missing.join(", ")}`,
    );
  }

  const key = `cmux-build-artifacts/cloud-vm/${tag}/cmuxd-remote-linux-amd64`;
  const env = {
    AWS_ACCESS_KEY_ID: process.env.R2_ACCESS_KEY_ID!,
    AWS_SECRET_ACCESS_KEY: process.env.R2_SECRET_ACCESS_KEY!,
    AWS_DEFAULT_REGION: "auto",
    AWS_REGION: "auto",
  };
  await runCommand(
    "aws",
    [
      "s3",
      "cp",
      daemonPath,
      `s3://${process.env.R2_BUCKET_NAME!}/${key}`,
      "--endpoint-url",
      process.env.R2_ENDPOINT!,
      "--content-type",
      "application/octet-stream",
      "--cache-control",
      "no-store",
      "--only-show-errors",
    ],
    { env },
  );

  const presigned = await runCommand(
    "aws",
    [
      "s3",
      "presign",
      `s3://${process.env.R2_BUCKET_NAME!}/${key}`,
      "--endpoint-url",
      process.env.R2_ENDPOINT!,
      "--expires-in",
      "3600",
    ],
    { env },
  );
  return presigned.trim();
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function runCommand(
  command: string,
  args: string[],
  options: { cwd?: string; env?: Record<string, string> } = {},
): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: { ...process.env, ...options.env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    child.stdout.on("data", (chunk: Buffer) => stdout.push(chunk));
    child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));
    child.once("error", reject);
    child.once("close", (code) => {
      const output = Buffer.concat(stdout).toString();
      const errorOutput = Buffer.concat(stderr).toString();
      if (code === 0) {
        resolve(output);
        return;
      }
      reject(new Error(`${command} ${args.join(" ")} failed with ${code}\n${errorOutput}`));
    });
  });
}
