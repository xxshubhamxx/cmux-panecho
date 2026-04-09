#if DEBUG
import Foundation

/// Manages a local cmuxd-remote process that exposes a WebSocket endpoint
/// for the iOS app to connect to. DEBUG-only.
final class MobileDaemonBridge {
    static let shared = MobileDaemonBridge()

    private var process: Process?
    private var wsPort: Int = 0
    private var wsPortFilePath: String?
    private var wsSecretFilePath: String?

    private init() {}

    /// Start the daemon bridge. Call from applicationDidFinishLaunching.
    func startIfNeeded() {
        guard process == nil else { return }

        let socketPath = resolveSocketPath()
        let port = resolveWsPort()
        let secret = generateOrLoadSecret()
        guard let binaryPath = resolveDaemonBinary() else {
            NSLog("📱 MobileDaemonBridge: cmuxd-remote binary not found, skipping")
            return
        }

        // Write ws-secret for iOS to read
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cmuxDir = appSupport.appendingPathComponent("cmux")
        try? FileManager.default.createDirectory(at: cmuxDir, withIntermediateDirectories: true)
        let secretPath = cmuxDir.appendingPathComponent("mobile-ws-secret").path
        try? secret.write(toFile: secretPath, atomically: true, encoding: .utf8)
        wsSecretFilePath = secretPath

        // Derive daemon socket path (separate from the app's control socket)
        let daemonSocketPath = socketPath.replacingOccurrences(of: ".sock", with: "-daemon.sock")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "serve",
            "--unix", "--socket", daemonSocketPath,
            "--ws-port", String(port),
            "--ws-secret", secret,
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] _ in
            self?.cleanupFiles()
        }

        do {
            try proc.run()
            process = proc
            wsPort = port

            // Write wsport discovery file
            let wsportPath = socketPath.replacingOccurrences(of: ".sock", with: ".wsport")
            try? String(port).write(toFile: wsportPath, atomically: true, encoding: .utf8)
            wsPortFilePath = wsportPath

            NSLog("📱 MobileDaemonBridge: started on ws://127.0.0.1:%d (socket: %@)", port, daemonSocketPath)
        } catch {
            NSLog("📱 MobileDaemonBridge: failed to start: %@", error.localizedDescription)
        }
    }

    /// Stop the daemon bridge. Call from applicationWillTerminate.
    func stop() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        cleanupFiles()
    }

    private func cleanupFiles() {
        if let path = wsPortFilePath {
            try? FileManager.default.removeItem(atPath: path)
            wsPortFilePath = nil
        }
    }

    // MARK: - Resolution helpers

    private func resolveSocketPath() -> String {
        let bundleId = Bundle.main.bundleIdentifier
        if let tagged = SocketControlSettings.taggedDebugSocketPath(
            bundleIdentifier: bundleId,
            environment: ProcessInfo.processInfo.environment
        ) {
            return tagged
        }
        return "/tmp/cmux-debug.sock"
    }

    private func resolveWsPort() -> Int {
        let env = ProcessInfo.processInfo.environment
        if let portStr = env["CMUX_MOBILE_WS_PORT"], let port = Int(portStr) {
            return port
        }
        // Derive a stable port from tag or bundle ID to avoid collisions
        // between multiple tagged macOS builds. Uses FNV-1a (not hashValue,
        // which is randomized per process in Swift).
        let tag = env["CMUX_TAG"] ?? env["CMUX_LAUNCH_TAG"] ?? ""
        if !tag.isEmpty {
            return 9444 + 1 + (Self.stableHash(tag) % 99)
        }
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let basePrefixes = ["com.cmuxterm.app.debug", "dev.cmux.app.dev"]
        for prefix in basePrefixes {
            if bundleId.count > prefix.count, bundleId.hasPrefix(prefix) {
                let suffix = String(bundleId.dropFirst(prefix.count + 1))
                if !suffix.isEmpty {
                    return 9444 + 1 + (Self.stableHash(suffix) % 99)
                }
            }
        }
        return 9444
    }

    private static func stableHash(_ string: String) -> Int {
        // FNV-1a 32-bit
        var hash: UInt32 = 2_166_136_261
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return Int(hash)
    }

    private func generateOrLoadSecret() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let secretPath = appSupport.appendingPathComponent("cmux/mobile-ws-secret").path
        if let existing = try? String(contentsOfFile: secretPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        // Generate a random hex secret
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func resolveDaemonBinary() -> String? {
        let env = ProcessInfo.processInfo.environment

        // Check explicit override
        if let explicit = env["CMUX_REMOTE_DAEMON_BINARY"],
           FileManager.default.isExecutableFile(atPath: explicit) {
            return explicit
        }

        // Check common dev paths
        let candidates = [
            // Zig daemon (from this worktree)
            env["HOME"].map { "\($0)/fun/cmuxterm-hq/worktrees/task-move-ios-app-into-cmux-repo/daemon/remote/zig/zig-out/bin/cmuxd-remote" },
            // Rust daemon (from feat-amux-rust-backend worktree)
            env["HOME"].map { "\($0)/fun/cmuxterm-hq/worktrees/feat-amux-rust-backend/daemon/remote/rust/target/debug/cmuxd-remote" },
            env["HOME"].map { "\($0)/fun/cmuxterm-hq/worktrees/feat-amux-rust-backend/daemon/remote/rust/target/release/cmuxd-remote" },
            // Bundled in the app
            Bundle.main.resourceURL?.appendingPathComponent("bin/cmuxd-remote").path,
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }
}
#endif
