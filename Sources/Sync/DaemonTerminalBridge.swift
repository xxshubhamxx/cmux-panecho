import Foundation

/// Bridges a macOS Ghostty surface (Manual I/O mode) to a daemon terminal session.
/// Uses two separate Unix socket connections: one for the read loop (blocking poll)
/// and one for writes (non-blocking, always ready).
final class DaemonTerminalBridge: @unchecked Sendable {
    private let socketPath: String
    let sessionID: String
    private let shellCommand: String

    // Read connection (used exclusively by the read thread)
    private var readFD: Int32 = -1
    // Write connection (used by io_write_cb and resize, protected by writeLock)
    private var writeFD: Int32 = -1
    private let writeLock = NSLock()

    // Stable attachment ID: reused across reconnections so we don't leak attachments
    private let attachmentID: String = "bridge-\(UUID().uuidString.prefix(8).lowercased())"
    private var readOffset: UInt64 = 0
    private var readThread: Thread?
    private var running = false
    /// Pending resize to apply after the bridge connects. Set by the
    /// macOS surface when the real layout is known but the bridge hasn't
    /// attached yet.
    private var pendingResizeCols: Int = 0
    private var pendingResizeRows: Int = 0
    private var rpcID: Int = 0
    private let idLock = NSLock()

    var onOutput: ((_ data: Data) -> Void)?
    var onDisconnect: ((_ error: String?) -> Void)?

    init(socketPath: String, sessionID: String, shellCommand: String) {
        self.socketPath = socketPath
        self.sessionID = sessionID
        self.shellCommand = shellCommand
    }

    deinit {
        stop()
    }

    /// Deterministically compute the daemon session ID for a workspace+surface pair.
    /// Uses the surface ID only (not workspace ID) because surface IDs persist
    /// across app restarts in the session snapshot, while workspace IDs are
    /// regenerated. This keeps daemon sessions stable across macOS app restarts.
    static func computeSessionID(workspaceID: UUID, surfaceID: UUID) -> String {
        "ws-\(surfaceID.uuidString.lowercased())"
    }

    /// Pre-create a daemon session without starting a bridge. Used on session restore
    /// so iOS clients can attach to the session even before the desktop user opens
    /// the workspace (Ghostty surface creation is lazy).
    ///
    /// Called synchronously; performs its RPC on a background queue. Safe to call
    /// multiple times (uses already_exists check).
    static func preCreateSession(
        socketPath: String,
        workspaceID: UUID,
        surfaceID: UUID,
        shellCommand: String,
        cols: Int = 80,
        rows: Int = 24
    ) {
        let sessionID = computeSessionID(workspaceID: workspaceID, surfaceID: surfaceID)
        DispatchQueue.global(qos: .userInitiated).async {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return }
            defer { Darwin.close(fd) }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
            socketPath.withCString { cstr in
                _ = memcpy(&addr.sun_path, cstr, min(Int(strlen(cstr)), pathSize - 1))
            }
            let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let result = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(fd, sockaddrPtr, addrLen)
                }
            }
            guard result == 0 else { return }

            var timeout = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            // terminal.open with the deterministic session ID
            let openPayload: [String: Any] = [
                "id": 1,
                "method": "terminal.open",
                "params": [
                    "session_id": sessionID,
                    "command": shellCommand,
                    "cols": cols,
                    "rows": rows,
                ] as [String: Any],
            ]
            guard var openData = try? JSONSerialization.data(withJSONObject: openPayload) else { return }
            openData.append(0x0A)
            _ = openData.withUnsafeBytes { ptr in Darwin.write(fd, ptr.baseAddress, ptr.count) }

            // Read response
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(fd, &buf, buf.count)
            guard n > 0 else { return }
            let respData = Data(buf[0..<Int(n)])
            guard let respLine = respData.split(separator: 0x0A).first,
                  let respJson = try? JSONSerialization.jsonObject(with: Data(respLine)) as? [String: Any] else {
                return
            }

            // If already_exists, session is good — done.
            // If ok=true, we need to detach the bootstrap attachment so the session
            // has zero attachments (daemon preserves the size via last_known).
            if let ok = respJson["ok"] as? Bool, ok,
               let result = respJson["result"] as? [String: Any],
               let bootstrapID = result["attachment_id"] as? String {
                let detachPayload: [String: Any] = [
                    "id": 2,
                    "method": "session.detach",
                    "params": [
                        "session_id": sessionID,
                        "attachment_id": bootstrapID,
                    ] as [String: Any],
                ]
                if var detachData = try? JSONSerialization.data(withJSONObject: detachPayload) {
                    detachData.append(0x0A)
                    _ = detachData.withUnsafeBytes { ptr in Darwin.write(fd, ptr.baseAddress, ptr.count) }
                    _ = Darwin.read(fd, &buf, buf.count)
                }
                NSLog("📱 DaemonBridge: pre-created session %@", sessionID)
            }
        }
    }

    // MARK: - Lifecycle

    func start(cols: Int, rows: Int) {
        guard !running else { return }
        running = true

        let thread = Thread { [weak self] in
            self?.sessionLoop(cols: cols, rows: rows)
        }
        thread.name = "DaemonTerminalBridge.\(sessionID)"
        thread.qualityOfService = .userInteractive
        thread.start()
        readThread = thread
    }

    func stop() {
        running = false
        // Detach via write socket before closing
        writeLock.lock()
        if writeFD >= 0 {
            let params: [String: Any] = ["session_id": sessionID, "attachment_id": attachmentID]
            let id = nextID()
            let payload: [String: Any] = ["id": id, "method": "session.detach", "params": params]
            if var data = try? JSONSerialization.data(withJSONObject: payload) {
                data.append(0x0A)
                _ = data.withUnsafeBytes { ptr in Darwin.write(writeFD, ptr.baseAddress, ptr.count) }
            }
            Darwin.close(writeFD)
            writeFD = -1
        }
        writeLock.unlock()
        // readFD is closed by the read thread
    }

    // MARK: - Write (user input → daemon) — uses dedicated write socket

    func writeToSession(_ data: Data) {
        let base64 = data.base64EncodedString()
        let params: [String: Any] = ["session_id": sessionID, "data": base64]
        // Fire directly on the calling thread (io_write_cb is already off-main).
        // The write socket is separate from the read socket, so no contention.
        sendOnWriteSocket(method: "terminal.write", params: params)
    }

    // MARK: - Resize

    func resize(cols: Int, rows: Int) {
        // If the write socket isn't connected yet, save as pending.
        // The session loop will apply it after attaching.
        writeLock.lock()
        let connected = writeFD >= 0
        writeLock.unlock()
        if !connected {
            pendingResizeCols = max(1, cols)
            pendingResizeRows = max(1, rows)
            return
        }
        let params: [String: Any] = [
            "session_id": sessionID,
            "attachment_id": attachmentID,
            "cols": max(1, cols),
            "rows": max(1, rows),
        ]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.sendOnWriteSocket(method: "session.resize", params: params)
        }
    }

    // MARK: - Session loop (runs on dedicated thread, uses read socket only)

    private func sessionLoop(cols: Int, rows: Int) {
        while running {
            guard let fd = openSocket() else {
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            readFD = fd

            // Also open the write socket
            if let wfd = openSocket() {
                writeLock.lock()
                writeFD = wfd
                writeLock.unlock()
            }

            // Try to attach to existing session first
            let attached = attachToSession(fd: fd, cols: cols, rows: rows)
            if !attached {
                let opened = openSession(fd: fd, cols: cols, rows: rows)
                if !opened {
                    NSLog("📱 DaemonBridge[%@]: failed to open/attach, retrying in 1s", sessionID)
                    Darwin.close(fd)
                    readFD = -1
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }
            }

            NSLog("📱 DaemonBridge[%@]: connected, attachment=%@", sessionID, attachmentID ?? "nil")

            // Apply any pending resize that was set before the bridge connected.
            if pendingResizeCols > 0 && pendingResizeRows > 0 {
                let pc = pendingResizeCols
                let pr = pendingResizeRows
                pendingResizeCols = 0
                pendingResizeRows = 0
                if pc != cols || pr != rows {
                    resize(cols: pc, rows: pr)
                }
            }

            readLoop(fd: fd)

            Darwin.close(fd)
            readFD = -1
            if running {
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }

    private func readLoop(fd: Int32) {
        while running {
            let id = nextID()
            let payload: [String: Any] = [
                "id": id,
                "method": "terminal.read",
                "params": [
                    "session_id": sessionID,
                    "offset": readOffset,
                    "max_bytes": 65536,
                    "timeout_ms": 30000,
                ] as [String: Any],
            ]

            guard let response = sendRPCOn(fd: fd, payload: payload) else {
                break
            }

            guard let ok = response["ok"] as? Bool, ok,
                  let result = response["result"] as? [String: Any] else {
                if let error = response["error"] as? [String: Any],
                   let code = error["code"] as? String,
                   code == "deadline_exceeded" {
                    continue
                }
                break
            }

            if let newOffset = result["offset"] as? UInt64 {
                readOffset = newOffset
            } else if let newOffset = result["offset"] as? Int {
                readOffset = UInt64(newOffset)
            }

            if let base64 = result["data"] as? String,
               let data = Data(base64Encoded: base64),
               !data.isEmpty {
                onOutput?(data)
            }

            if let eof = result["eof"] as? Bool, eof {
                onDisconnect?(nil)
                return
            }
        }
    }

    // MARK: - Session management (uses read socket during setup)

    private func attachToSession(fd: Int32, cols: Int, rows: Int) -> Bool {
        let id = nextID()
        let payload: [String: Any] = [
            "id": id,
            "method": "session.attach",
            "params": [
                "session_id": sessionID,
                "attachment_id": attachmentID,
                "cols": max(1, cols),
                "rows": max(1, rows),
            ] as [String: Any],
        ]

        guard let response = sendRPCOn(fd: fd, payload: payload),
              let ok = response["ok"] as? Bool, ok else {
            return false
        }

        // Don't reset readOffset here. On reconnect we want to resume
        // from where we left off, not replay the entire terminal history
        // on top of what Ghostty already rendered. readOffset is only
        // reset to 0 when the session is first opened (openSession).
        return true
    }

    private func openSession(fd: Int32, cols: Int, rows: Int) -> Bool {
        let id = nextID()
        let payload: [String: Any] = [
            "id": id,
            "method": "terminal.open",
            "params": [
                "session_id": sessionID,
                "command": shellCommand,
                "cols": max(1, cols),
                "rows": max(1, rows),
            ] as [String: Any],
        ]

        guard let response = sendRPCOn(fd: fd, payload: payload),
              let ok = response["ok"] as? Bool, ok else {
            return false
        }

        // Brand new session — read from the beginning.
        readOffset = 0

        // terminal.open creates its own attachment; detach it and re-attach with our stable ID
        if let result = response["result"] as? [String: Any],
           let bootstrapAttach = result["attachment_id"] as? String {
            // Detach bootstrap attachment
            let detachPayload: [String: Any] = [
                "id": nextID(),
                "method": "session.detach",
                "params": ["session_id": sessionID, "attachment_id": bootstrapAttach] as [String: Any],
            ]
            _ = sendRPCOn(fd: fd, payload: detachPayload)
        }

        // Attach with our stable ID
        return attachToSession(fd: fd, cols: cols, rows: rows)
    }

    // MARK: - Socket I/O

    private func openSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
        socketPath.withCString { cstr in
            _ = memcpy(&addr.sun_path, cstr, min(Int(strlen(cstr)), pathSize - 1))
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }

        if result != 0 {
            Darwin.close(fd)
            return nil
        }

        // Send timeout stays short (2s). Recv timeout must exceed the
        // terminal.read server-side timeout (30s) so the socket doesn't
        // EAGAIN mid-poll and trigger a spurious reconnect cycle.
        var sendTimeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        var recvTimeout = timeval(tv_sec: 35, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, socklen_t(MemoryLayout<timeval>.size))

        return fd
    }

    private func nextID() -> Int {
        idLock.lock()
        rpcID += 1
        let id = rpcID
        idLock.unlock()
        return id
    }

    /// Send RPC on a specific fd (used by read thread on readFD).
    private func sendRPCOn(fd: Int32, payload: [String: Any]) -> [String: Any]? {
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        data.append(0x0A)

        let writeResult = data.withUnsafeBytes { ptr -> Int in
            Darwin.write(fd, ptr.baseAddress, ptr.count)
        }
        guard writeResult > 0 else { return nil }

        var accumulated = Data()
        var buf = [UInt8](repeating: 0, count: 65536 + 4096)
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            guard n > 0 else { return nil }
            accumulated.append(contentsOf: buf[0..<n])
            if accumulated.contains(0x0A) { break }
        }

        if let newlineIndex = accumulated.firstIndex(of: 0x0A) {
            let jsonData = accumulated[accumulated.startIndex..<newlineIndex]
            return try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        }
        return try? JSONSerialization.jsonObject(with: accumulated) as? [String: Any]
    }

    /// Send RPC on the dedicated write socket (fire-and-forget with response drain).
    private func sendOnWriteSocket(method: String, params: [String: Any]) {
        writeLock.lock()
        guard writeFD >= 0 else { writeLock.unlock(); return }
        let fd = writeFD
        let id = nextID()
        writeLock.unlock()

        let payload: [String: Any] = ["id": id, "method": method, "params": params]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        data.append(0x0A)

        let writeResult = data.withUnsafeBytes { ptr -> Int in
            Darwin.write(fd, ptr.baseAddress, ptr.count)
        }
        guard writeResult > 0 else { return }

        // Drain response
        var buf = [UInt8](repeating: 0, count: 4096)
        _ = Darwin.read(fd, &buf, buf.count)
    }
}
