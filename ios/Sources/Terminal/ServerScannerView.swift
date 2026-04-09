import SwiftUI

struct DiscoveredServer: Identifiable {
    let id = UUID()
    let hostname: String
    let port: Int
    let name: String
    let version: String
    let workspaceCount: Int
    let wsSecret: String
}

@MainActor
final class ServerScanner: ObservableObject {
    @Published var servers: [DiscoveredServer] = []
    @Published var isScanning = false

    private var scanTask: Task<Void, Never>?

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        servers = []

        scanTask = Task {
            let results = await scanAll()
            self.servers = results
            self.isScanning = false
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func scanAll() async -> [DiscoveredServer] {
        let secret = loadWsSecret()

        // Build list of (hostname, port) candidates
        var candidates: [(String, Int)] = []

        // Localhost ports 9444-9543
        for port in 9444...9543 {
            candidates.append(("127.0.0.1", port))
        }

        // Tailscale IPs from relay host file
        if let relayHost = loadRelayHost(), relayHost != "127.0.0.1" {
            for port in 9444...9543 {
                candidates.append((relayHost, port))
            }
        }

        // Probe in parallel batches
        let batchSize = 20
        var found: [DiscoveredServer] = []

        for batchStart in stride(from: 0, to: candidates.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let batchEnd = min(batchStart + batchSize, candidates.count)
            let batch = candidates[batchStart..<batchEnd]

            let results = await withTaskGroup(of: DiscoveredServer?.self) { group in
                for (host, port) in batch {
                    group.addTask {
                        await Self.probeAndIdentify(hostname: host, port: port, secret: secret)
                    }
                }
                var batchResults: [DiscoveredServer] = []
                for await result in group {
                    if let server = result {
                        batchResults.append(server)
                    }
                }
                return batchResults
            }

            found.append(contentsOf: results)
            // Update UI incrementally
            self.servers = found.sorted { $0.port < $1.port }
        }

        return found.sorted { $0.port < $1.port }
    }

    private static func probeAndIdentify(hostname: String, port: Int, secret: String) async -> DiscoveredServer? {
        // Full WebSocket handshake + hello RPC on a background thread
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = Self.probeSync(hostname: hostname, port: port, secret: secret)
                continuation.resume(returning: result)
            }
        }
    }

    private static func probeSync(hostname: String, port: Int, secret: String) -> DiscoveredServer? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Connect
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        inet_pton(AF_INET, hostname, &addr.sin_addr)
        let addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }
        guard connectResult == 0 else { return nil }

        // WebSocket upgrade
        let req = "GET / HTTP/1.1\r\nHost: \(hostname):\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdA==\r\nSec-WebSocket-Version: 13\r\n\r\n"
        _ = req.data(using: .utf8)?.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        guard n > 0, String(bytes: buf[0..<n], encoding: .utf8)?.contains("101") == true else { return nil }

        // Auth
        wsSend(fd: fd, data: "{\"secret\":\"\(secret)\"}")
        guard let authResp = wsRecv(fd: fd), authResp.contains("authenticated") else { return nil }

        // Hello RPC
        wsSend(fd: fd, data: "{\"id\":1,\"method\":\"hello\"}")
        guard let helloResp = wsRecv(fd: fd),
              let helloData = helloResp.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: helloData) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let name = result["name"] as? String,
              let version = result["version"] as? String else {
            return nil
        }

        let workspaceCount = result["workspace_count"] as? Int ?? 0

        return DiscoveredServer(
            hostname: hostname,
            port: port,
            name: name,
            version: version,
            workspaceCount: workspaceCount,
            wsSecret: secret
        )
    }

    // MARK: - WebSocket helpers

    private static func wsSend(fd: Int32, data: String) {
        guard let payload = data.data(using: .utf8) else { return }
        var frame = [UInt8]()
        frame.append(0x81)
        if payload.count <= 125 {
            frame.append(UInt8(payload.count))
        } else {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        }
        frame.append(contentsOf: payload)
        frame.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    private static func wsRecv(fd: Int32) -> String? {
        var header = [UInt8](repeating: 0, count: 2)
        let headerRead = read(fd, &header, 2)
        guard headerRead == 2 else { return nil }

        var payloadLen = Int(header[1] & 0x7F)
        if payloadLen == 126 {
            var extLen = [UInt8](repeating: 0, count: 2)
            guard read(fd, &extLen, 2) == 2 else { return nil }
            payloadLen = Int(extLen[0]) << 8 | Int(extLen[1])
        } else if payloadLen == 127 {
            var extLen = [UInt8](repeating: 0, count: 8)
            guard read(fd, &extLen, 8) == 8 else { return nil }
            payloadLen = 0
            for i in 0..<8 { payloadLen = payloadLen << 8 | Int(extLen[i]) }
        }

        guard payloadLen > 0, payloadLen < 1_000_000 else { return nil }
        var payload = [UInt8](repeating: 0, count: payloadLen)
        var totalRead = 0
        while totalRead < payloadLen {
            let n = payload.withUnsafeMutableBytes { buf in
                read(fd, buf.baseAddress! + totalRead, payloadLen - totalRead)
            }
            guard n > 0 else { return nil }
            totalRead += n
        }
        return String(bytes: payload, encoding: .utf8)
    }

    // MARK: - Config helpers

    private func loadWsSecret() -> String {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? NSHomeDirectory()
        let path = "\(home)/Library/Application Support/cmux/mobile-ws-secret"
        return (try? String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    private func loadRelayHost() -> String? {
        guard let path = Bundle.main.path(forResource: "debug-relay-host", ofType: nil),
              let host = try? String(contentsOfFile: path, encoding: .utf8)
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        return host
    }
}

struct ServerScannerView: View {
    @StateObject private var scanner = ServerScanner()
    @State private var connectedPorts: Set<Int>
    let onSelect: (DiscoveredServer) -> Void
    let onRemove: (DiscoveredServer) -> Void
    let onDismiss: () -> Void

    init(
        connectedPorts: Set<Int>,
        onSelect: @escaping (DiscoveredServer) -> Void,
        onRemove: @escaping (DiscoveredServer) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _connectedPorts = State(initialValue: connectedPorts)
        self.onSelect = onSelect
        self.onRemove = onRemove
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            List {
                if scanner.isScanning {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(String(localized: "server.scan.scanning", defaultValue: "Scanning..."))
                            .foregroundStyle(.secondary)
                    }
                }

                if scanner.servers.isEmpty && !scanner.isScanning {
                    ContentUnavailableView {
                        Label(
                            String(localized: "server.scan.empty_title", defaultValue: "No Servers Found"),
                            systemImage: "magnifyingglass"
                        )
                    } description: {
                        Text(String(localized: "server.scan.empty_description", defaultValue: "Make sure cmux is running on your Mac."))
                    } actions: {
                        Button(String(localized: "server.scan.rescan", defaultValue: "Scan Again")) {
                            scanner.startScan()
                        }
                    }
                }

                ForEach(scanner.servers) { server in
                    let isConnected = connectedPorts.contains(server.port)
                    Button {
                        if isConnected {
                            connectedPorts.remove(server.port)
                            onRemove(server)
                        } else {
                            connectedPorts.insert(server.port)
                            onSelect(server)
                        }
                    } label: {
                        ServerScanRow(server: server, isConnected: isConnected)
                    }
                }
            }
            .navigationTitle(String(localized: "server.scan.title", defaultValue: "Find Servers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "server.scan.done", defaultValue: "Done")) {
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .primaryAction) {
                    if scanner.isScanning {
                        ProgressView()
                    } else {
                        Button {
                            scanner.startScan()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task {
                scanner.startScan()
            }
        }
    }
}

private struct ServerScanRow: View {
    let server: DiscoveredServer
    let isConnected: Bool

    var body: some View {
        HStack {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(isConnected ? .blue : .secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                HStack(spacing: 8) {
                    if server.workspaceCount > 0 {
                        Text("\(server.workspaceCount) workspaces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("v\(server.version)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: isConnected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isConnected ? .blue : .secondary)
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        if server.hostname == "127.0.0.1" {
            return "Local (:\(server.port))"
        }
        return "\(server.hostname) (:\(server.port))"
    }
}
