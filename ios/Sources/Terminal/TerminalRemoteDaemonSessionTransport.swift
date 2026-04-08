import Foundation

protocol TerminalRemoteDaemonResumeStateSnapshotting {
    func remoteDaemonResumeStateSnapshot() -> TerminalRemoteDaemonResumeState?
}

protocol TerminalRemoteDaemonSessionClient: Sendable {
    func sendHello() async throws -> TerminalRemoteDaemonHello
    func sessionAttach(
        sessionID: String,
        attachmentID: String,
        cols: Int,
        rows: Int
    ) async throws -> TerminalRemoteDaemonSessionStatus
    func terminalOpen(command: String, cols: Int, rows: Int) async throws -> TerminalRemoteDaemonTerminalOpenResult
    func terminalWrite(sessionID: String, data: Data) async throws
    func terminalRead(
        sessionID: String,
        offset: UInt64,
        maxBytes: Int,
        timeoutMilliseconds: Int
    ) async throws -> TerminalRemoteDaemonTerminalReadResult
    func sessionResize(
        sessionID: String,
        attachmentID: String,
        cols: Int,
        rows: Int
    ) async throws -> TerminalRemoteDaemonSessionStatus
    func sessionDetach(
        sessionID: String,
        attachmentID: String
    ) async throws -> TerminalRemoteDaemonSessionStatus
    func sessionClose(sessionID: String) async throws
    func sessionHistory(sessionID: String, format: String) async throws -> TerminalRemoteDaemonSessionHistoryResult
}

enum TerminalRemoteDaemonSessionTransportError: LocalizedError {
    case missingCapability(String)

    var errorDescription: String? {
        switch self {
        case .missingCapability(let capability):
            return "Remote daemon is missing required capability \(capability)."
        }
    }
}

final class TerminalRemoteDaemonSessionTransport: @unchecked Sendable, TerminalTransport {
    var eventHandler: (@Sendable (TerminalTransportEvent) -> Void)?

    private let client: any TerminalRemoteDaemonSessionClient
    private let command: String
    private let resumeState: TerminalRemoteDaemonResumeState?
    private let readTimeoutMilliseconds: Int
    private let maxReadBytes: Int
    private let stateLock = NSLock()

    private var sessionID: String?
    private var attachmentID: String?
    private var nextOffset: UInt64 = 0
    private var readTask: Task<Void, Never>?
    private var closed = false

    init(
        client: any TerminalRemoteDaemonSessionClient,
        command: String,
        resumeState: TerminalRemoteDaemonResumeState? = nil,
        readTimeoutMilliseconds: Int = 250,
        maxReadBytes: Int = 64 * 1024
    ) {
        self.client = client
        self.command = command
        self.resumeState = resumeState
        self.readTimeoutMilliseconds = readTimeoutMilliseconds
        self.maxReadBytes = maxReadBytes
    }

    func connect(initialSize: TerminalGridSize) async throws {
        NSLog("📱 SessionTransport: starting connect")
        let hello = try await client.sendHello()
        NSLog("📱 SessionTransport: hello OK, capabilities=%@", hello.capabilities.joined(separator: ","))
        guard hello.capabilities.contains("terminal.stream") else {
            throw TerminalRemoteDaemonSessionTransportError.missingCapability("terminal.stream")
        }

        try await openOrAttachTerminal(initialSize: initialSize)
        NSLog("📱 SessionTransport: terminal opened, sessionID=%@", lockedSessionID() ?? "nil")

        // Fetch scrollback so the terminal starts with existing content.
        if let sessionID = lockedSessionID() {
            do {
                let historyResult = try await client.sessionHistory(sessionID: sessionID, format: "plain")
                if !historyResult.history.isEmpty, let data = historyResult.history.data(using: .utf8) {
                    NSLog("📱 SessionTransport: sending %d bytes of scrollback", data.count)
                    eventHandler?(.output(data))
                }
            } catch {
                NSLog("📱 SessionTransport: scrollback fetch failed: %@", error.localizedDescription)
            }
        }

        eventHandler?(.connected)
        startReadLoop()
        NSLog("📱 SessionTransport: read loop started")
    }

    func send(_ data: Data) async throws {
        guard let sessionID = lockedSessionID() else { return }
        try await client.terminalWrite(sessionID: sessionID, data: data)
    }

    func resize(_ size: TerminalGridSize) async {
        guard let state = lockedSessionState() else { return }
        _ = try? await client.sessionResize(
            sessionID: state.sessionID,
            attachmentID: state.attachmentID,
            cols: max(1, size.columns),
            rows: max(1, size.rows)
        )
    }

    func disconnect() async {
        let sessionID = lockedSessionID()
        let readTask = takeReadTask(markClosed: false)
        readTask?.cancel()
        await readTask?.value

        if let sessionID {
            try? await client.sessionClose(sessionID: sessionID)
        }
        clearSessionState()
        finishDisconnect(error: nil)
    }

    func suspendPreservingSession() async {
        guard let state = lockedSessionState() else { return }

        let readTask = takeReadTask(markClosed: true)
        readTask?.cancel()
        await readTask?.value

        _ = try? await client.sessionDetach(
            sessionID: state.sessionID,
            attachmentID: state.attachmentID
        )
        clearSessionState()
    }

    private func openOrAttachTerminal(initialSize: TerminalGridSize) async throws {
        let cols = max(1, initialSize.columns)
        let rows = max(1, initialSize.rows)

        if let resumeState {
            do {
                _ = try await client.sessionAttach(
                    sessionID: resumeState.sessionID,
                    attachmentID: resumeState.attachmentID,
                    cols: cols,
                    rows: rows
                )
                withLockedState {
                    sessionID = resumeState.sessionID
                    attachmentID = resumeState.attachmentID
                    nextOffset = resumeState.readOffset
                    closed = false
                }
                return
            } catch let error as TerminalRemoteDaemonClientError {
                if case .rpc(let code, _) = error, code == "not_found" {
                    clearSessionState()
                } else {
                    throw error
                }
            }
        }

        let openResult = try await client.terminalOpen(
            command: command,
            cols: cols,
            rows: rows
        )

        withLockedState {
            sessionID = openResult.sessionID
            attachmentID = openResult.attachmentID
            nextOffset = openResult.offset
            closed = false
        }
    }

    private func startReadLoop() {
        withLockedState {
            readTask?.cancel()
            readTask = Task { [weak self] in
                await self?.runReadLoop()
            }
        }
    }

    private func runReadLoop() async {
        while !Task.isCancelled {
            guard let state = lockedSessionStateWithOffset() else { return }

            do {
                let result = try await client.terminalRead(
                    sessionID: state.sessionID,
                    offset: state.offset,
                    maxBytes: maxReadBytes,
                    timeoutMilliseconds: readTimeoutMilliseconds
                )

                withLockedState {
                    nextOffset = result.offset
                }

                if !result.data.isEmpty {
                    eventHandler?(.output(result.data))
                }

                if result.eof {
                    NSLog("📱 readLoop: EOF received for session %@, data=%d bytes", state.sessionID, result.data.count)
                    clearSessionState()
                    finishDisconnect(error: nil)
                    return
                }
            } catch let error as TerminalRemoteDaemonClientError {
                if case .rpc(let code, _) = error, code == "deadline_exceeded" {
                    continue
                }
                NSLog("📱 readLoop RPC error: %@", error.localizedDescription ?? "unknown")
                finishDisconnect(error: error.localizedDescription)
                return
            } catch {
                NSLog("📱 readLoop error: %@", String(describing: error))
                finishDisconnect(error: error.localizedDescription)
                return
            }
        }
    }

    private func finishDisconnect(error: String?) {
        stateLock.lock()
        guard !closed else {
            stateLock.unlock()
            return
        }
        closed = true
        readTask?.cancel()
        readTask = nil
        stateLock.unlock()

        eventHandler?(.disconnected(error))
    }

    private func lockedSessionID() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return sessionID
    }

    private func lockedSessionState() -> (sessionID: String, attachmentID: String)? {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard let sessionID, let attachmentID else { return nil }
        return (sessionID, attachmentID)
    }

    private func lockedSessionStateWithOffset() -> (sessionID: String, attachmentID: String, offset: UInt64)? {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard let sessionID, let attachmentID else { return nil }
        return (sessionID, attachmentID, nextOffset)
    }

    private func clearSessionState() {
        withLockedState {
            sessionID = nil
            attachmentID = nil
            nextOffset = 0
        }
    }

    private func takeReadTask(markClosed: Bool) -> Task<Void, Never>? {
        withLockedState {
            let task = readTask
            readTask = nil
            if markClosed {
                closed = true
            }
            return task
        }
    }

    private func withLockedState<Result>(_ body: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}

extension TerminalRemoteDaemonSessionTransport: TerminalRemoteDaemonResumeStateSnapshotting {
    func remoteDaemonResumeStateSnapshot() -> TerminalRemoteDaemonResumeState? {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard let sessionID, let attachmentID else { return nil }
        return TerminalRemoteDaemonResumeState(
            sessionID: sessionID,
            attachmentID: attachmentID,
            readOffset: nextOffset
        )
    }
}

extension TerminalRemoteDaemonSessionTransport: TerminalSessionParking {}
