import Foundation

enum TerminalWebSocketTransportError: LocalizedError {
    case invalidURL
    case handshakeRejected(String)
    case unexpectedMessageType
    case connectionClosed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(
                localized: "terminal.websocket.invalid_url",
                defaultValue: "Invalid WebSocket server URL."
            )
        case .handshakeRejected(let message):
            return message
        case .unexpectedMessageType:
            return String(
                localized: "terminal.websocket.unexpected_message",
                defaultValue: "Received unexpected message from server."
            )
        case .connectionClosed:
            return String(
                localized: "terminal.websocket.connection_closed",
                defaultValue: "WebSocket connection closed."
            )
        }
    }
}

final class TerminalWebSocketDaemonClient: Sendable {

    func connect(
        host: String,
        port: Int,
        secret: String,
        timeoutSeconds: TimeInterval = 8
    ) async throws -> any TerminalRemoteDaemonTransport {
        guard let url = URL(string: "ws://\(host):\(port)") else {
            throw TerminalWebSocketTransportError.invalidURL
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = timeoutSeconds
        config.timeoutIntervalForRequest = timeoutSeconds
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        task.resume()

        let handshakePayload: [String: Any] = ["secret": secret]
        let handshakeData = try JSONSerialization.data(withJSONObject: handshakePayload)
        let handshakeString = String(data: handshakeData, encoding: .utf8) ?? "{}"
        try await task.send(.string(handshakeString))

        let response = try await task.receive()
        let responseString: String
        switch response {
        case .string(let text):
            responseString = text
        case .data(let data):
            responseString = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            throw TerminalWebSocketTransportError.unexpectedMessageType
        }

        guard let responseData = responseString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              json["ok"] as? Bool == true else {
            let errorMessage = parseErrorMessage(from: responseString)
            throw TerminalWebSocketTransportError.handshakeRejected(
                errorMessage ?? String(
                    localized: "terminal.websocket.auth_failed",
                    defaultValue: "WebSocket authentication failed."
                )
            )
        }

        return TerminalWebSocketLineTransport(webSocket: task)
    }

    private func parseErrorMessage(from response: String) -> String? {
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String,
              !message.isEmpty else {
            return nil
        }
        return message
    }
}

actor TerminalWebSocketLineTransport: TerminalRemoteDaemonTransport {
    private let webSocket: URLSessionWebSocketTask

    init(webSocket: URLSessionWebSocketTask) {
        self.webSocket = webSocket
    }

    func writeLine(_ line: String) async throws {
        guard webSocket.state == .running else {
            throw TerminalWebSocketTransportError.connectionClosed
        }
        try await webSocket.send(.string(line))
    }

    func readLine() async throws -> String {
        let message = try await webSocket.receive()
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            return String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            throw TerminalWebSocketTransportError.unexpectedMessageType
        }
    }

    func cancel() {
        webSocket.cancel(with: .goingAway, reason: nil)
    }
}

final class TerminalWebSocketTransport: @unchecked Sendable, TerminalTransport {
    var eventHandler: (@Sendable (TerminalTransportEvent) -> Void)?

    private let host: TerminalHost
    private let sessionName: String
    private let wsClient: TerminalWebSocketDaemonClient
    private let sessionTransportFactory: @Sendable (
        any TerminalRemoteDaemonTransport,
        String,
        String,
        TerminalRemoteDaemonResumeState?
    ) -> TerminalTransport
    private let resumeState: TerminalRemoteDaemonResumeState?
    private let stateQueue = DispatchQueue(label: "TerminalWebSocketTransport.state")

    private var activeTransport: TerminalTransport?
    private var lineTransport: TerminalWebSocketLineTransport?
    private var lastKnownResumeState: TerminalRemoteDaemonResumeState?

    init(
        host: TerminalHost,
        sessionName: String,
        resumeState: TerminalRemoteDaemonResumeState? = nil,
        wsClient: TerminalWebSocketDaemonClient = TerminalWebSocketDaemonClient(),
        sessionTransportFactory: @escaping @Sendable (
            any TerminalRemoteDaemonTransport,
            String,
            String,
            TerminalRemoteDaemonResumeState?
        ) -> TerminalTransport = { transport, command, sessionName, resumeState in
            TerminalRemoteDaemonSessionTransport(
                client: TerminalRemoteDaemonClient(transport: transport),
                command: command,
                preferredSessionID: sessionName,
                resumeState: resumeState,
                attachmentMode: .observer
            )
        }
    ) {
        self.host = host
        self.sessionName = sessionName
        self.resumeState = resumeState
        self.wsClient = wsClient
        self.sessionTransportFactory = sessionTransportFactory
        self.lastKnownResumeState = resumeState
    }

    func connect(initialSize: TerminalGridSize) async throws {
        guard let wsPort = host.wsPort,
              let wsSecret = host.wsSecret,
              !wsSecret.isEmpty else {
            throw TerminalWebSocketTransportError.invalidURL
        }

        let daemonTransport = try await wsClient.connect(
            host: host.hostname,
            port: wsPort,
            secret: wsSecret
        )

        let wsLineTransport = daemonTransport as? TerminalWebSocketLineTransport
        stateQueue.sync { self.lineTransport = wsLineTransport }

        let effectiveSessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "cmux-\(UUID().uuidString.prefix(8).lowercased())"
            : sessionName
        let command = host.bootstrapCommand.replacingOccurrences(of: "{{session}}", with: effectiveSessionName)
        let transport = sessionTransportFactory(daemonTransport, command, effectiveSessionName, resumeState)
        transport.eventHandler = { [weak self, weak transport] event in
            self?.handle(event: event, activeTransport: transport)
        }
        stateQueue.sync { self.activeTransport = transport }

        do {
            try await transport.connect(initialSize: initialSize)
        } catch {
            stateQueue.sync {
                self.activeTransport = nil
                self.lineTransport = nil
            }
            throw error
        }
    }

    func send(_ data: Data) async throws {
        guard let transport = stateQueue.sync(execute: { activeTransport }) else { return }
        try await transport.send(data)
    }

    func resize(_ size: TerminalGridSize) async {
        guard let transport = stateQueue.sync(execute: { activeTransport }) else { return }
        await transport.resize(size)
    }

    func disconnect() async {
        let (transport, line) = stateQueue.sync {
            let t = activeTransport
            let l = lineTransport
            activeTransport = nil
            lineTransport = nil
            lastKnownResumeState = nil
            return (t, l)
        }
        await transport?.disconnect()
        await line?.cancel()
    }

    private func handle(event: TerminalTransportEvent, activeTransport: TerminalTransport?) {
        if let snapshotting = activeTransport as? TerminalRemoteDaemonResumeStateSnapshotting {
            stateQueue.sync {
                lastKnownResumeState = snapshotting.remoteDaemonResumeStateSnapshot()
            }
        }
        if case .disconnected = event {
            let line = stateQueue.sync { () -> TerminalWebSocketLineTransport? in
                self.activeTransport = nil
                let l = self.lineTransport
                self.lineTransport = nil
                return l
            }
            Task { await line?.cancel() }
        }
        eventHandler?(event)
    }
}

extension TerminalWebSocketTransport: TerminalRemoteDaemonResumeStateSnapshotting {
    func remoteDaemonResumeStateSnapshot() -> TerminalRemoteDaemonResumeState? {
        stateQueue.sync { lastKnownResumeState }
    }
}

extension TerminalWebSocketTransport: TerminalSessionParking {
    func suspendPreservingSession() async {
        let (transport, line) = stateQueue.sync {
            let t = activeTransport
            let l = lineTransport
            activeTransport = nil
            lineTransport = nil
            return (t, l)
        }
        if let parking = transport as? TerminalSessionParking {
            await parking.suspendPreservingSession()
        } else {
            await transport?.disconnect()
            stateQueue.sync { lastKnownResumeState = nil }
        }
        await line?.cancel()
    }
}
