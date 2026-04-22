import Foundation

enum CodexAppServerClientError: Error, LocalizedError {
    case alreadyRunning
    case notRunning
    case processExited
    case invalidResponse(String)
    case requestFailed(String)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Codex app-server is already running."
        case .notRunning:
            return "Codex app-server is not running."
        case .processExited:
            return "Codex app-server exited."
        case .invalidResponse(let message):
            return "Invalid Codex app-server response: \(message)"
        case .requestFailed(let message):
            return "Codex app-server request failed: \(message)"
        case .writeFailed:
            return "Failed to write to Codex app-server."
        }
    }
}

enum CodexAppServerEvent {
    case notification(method: String, params: [String: Any]?)
    case serverRequest(id: Int, method: String, params: [String: Any]?)
    case stderr(String)
    case terminated(Int32)
}

enum CodexAppServerRequestFactory {
    static func request(id: Int, method: String, params: [String: Any]? = nil) -> [String: Any] {
        var object: [String: Any] = [
            "id": id,
            "method": method,
        ]
        if let params {
            object["params"] = params
        }
        return object
    }

    static func notification(method: String, params: [String: Any]? = nil) -> [String: Any] {
        var object: [String: Any] = ["method": method]
        if let params {
            object["params"] = params
        }
        return object
    }

    static func initializeRequest(id: Int) -> [String: Any] {
        request(
            id: id,
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "cmux",
                    "title": "cmux",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
                ],
                "capabilities": [
                    "experimentalApi": true,
                ],
            ]
        )
    }

    static func initializedNotification() -> [String: Any] {
        notification(method: "initialized")
    }

    static func threadStartRequest(id: Int, cwd: String?) -> [String: Any] {
        var params: [String: Any] = [
            "serviceName": "cmux",
            "ephemeral": true,
        ]
        if let cwd, !cwd.isEmpty {
            params["cwd"] = cwd
        }
        return request(id: id, method: "thread/start", params: params)
    }

    static func turnStartRequest(id: Int, threadId: String, text: String, cwd: String?) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadId,
            "input": [
                [
                    "type": "text",
                    "text": text,
                    "textElements": [],
                ],
            ],
        ]
        if let cwd, !cwd.isEmpty {
            params["cwd"] = cwd
        }
        return request(id: id, method: "turn/start", params: params)
    }
}

final class CodexAppServerClient: @unchecked Sendable {
    typealias EventHandler = (CodexAppServerEvent) -> Void

    private final class PendingRequest {
        let continuation: CheckedContinuation<[String: Any], Error>

        init(_ continuation: CheckedContinuation<[String: Any], Error>) {
            self.continuation = continuation
        }
    }

    private let stateQueue = DispatchQueue(label: "cmux.codexAppServerClient.state")
    private let callbackQueue: DispatchQueue
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var nextRequestId = 1
    private var pending: [Int: PendingRequest] = [:]

    var onEvent: EventHandler?

    init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
    }

    deinit {
        stop()
    }

    func start() throws {
        let result: Result<Void, Error> = stateQueue.sync {
            do {
                try startLocked()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        try result.get()
    }

    func stop() {
        stateQueue.sync {
            stopLocked()
        }
    }

    func startAndInitialize() async throws {
        try start()
        _ = try await sendRequestObject(CodexAppServerRequestFactory.initializeRequest(id: nextId()))
        try sendNotificationObject(CodexAppServerRequestFactory.initializedNotification())
    }

    func startThread(cwd: String?) async throws -> String {
        let response = try await sendRequestObject(
            CodexAppServerRequestFactory.threadStartRequest(id: nextId(), cwd: cwd)
        )
        guard let thread = response["thread"] as? [String: Any],
              let threadId = thread["id"] as? String,
              !threadId.isEmpty else {
            throw CodexAppServerClientError.invalidResponse("thread/start response did not include thread.id")
        }
        return threadId
    }

    func startTurn(threadId: String, text: String, cwd: String?) async throws -> String {
        let response = try await sendRequestObject(
            CodexAppServerRequestFactory.turnStartRequest(
                id: nextId(),
                threadId: threadId,
                text: text,
                cwd: cwd
            )
        )
        guard let turn = response["turn"] as? [String: Any],
              let turnId = turn["id"] as? String,
              !turnId.isEmpty else {
            throw CodexAppServerClientError.invalidResponse("turn/start response did not include turn.id")
        }
        return turnId
    }

    private func nextId() -> Int {
        stateQueue.sync {
            let id = nextRequestId
            nextRequestId += 1
            return id
        }
    }

    private func startLocked() throws {
        guard process == nil else {
            throw CodexAppServerClientError.alreadyRunning
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        process.environment = Self.appServerEnvironment()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] process in
            self?.handleTermination(status: process.terminationStatus)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ingestStdout(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8),
                  !text.isEmpty else { return }
            self?.emit(.stderr(text))
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    private func stopLocked() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
        failPending(CodexAppServerClientError.processExited)
    }

    private static func appServerEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extraPaths = [
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        let existing = environment["PATH"] ?? ""
        let merged = (extraPaths + existing.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { paths, candidate in
                guard !candidate.isEmpty, !paths.contains(candidate) else { return }
                paths.append(candidate)
            }
            .joined(separator: ":")
        environment["PATH"] = merged
        return environment
    }

    private func sendRequestObject(_ object: [String: Any]) async throws -> [String: Any] {
        guard let id = Self.integerId(from: object["id"]) else {
            throw CodexAppServerClientError.invalidResponse("request object missing numeric id")
        }

        return try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                guard self.process?.isRunning == true,
                      let stdinPipe = self.stdinPipe else {
                    continuation.resume(throwing: CodexAppServerClientError.notRunning)
                    return
                }

                self.pending[id] = PendingRequest(continuation)
                do {
                    try Self.writeJSONObject(object, to: stdinPipe.fileHandleForWriting)
                } catch {
                    self.pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendNotificationObject(_ object: [String: Any]) throws {
        let result: Result<Void, Error> = stateQueue.sync {
            do {
                guard process?.isRunning == true,
                      let stdinPipe else {
                    throw CodexAppServerClientError.notRunning
                }
                try Self.writeJSONObject(object, to: stdinPipe.fileHandleForWriting)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        try result.get()
    }

    private static func writeJSONObject(_ object: [String: Any], to handle: FileHandle) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CodexAppServerClientError.invalidResponse("request is not valid JSON")
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: [])
        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw CodexAppServerClientError.writeFailed
        }
    }

    private func ingestStdout(_ data: Data) {
        stateQueue.async {
            self.stdoutBuffer.append(data)
            while let newline = self.stdoutBuffer.firstIndex(of: 0x0A) {
                let lineData = self.stdoutBuffer[..<newline]
                self.stdoutBuffer.removeSubrange(...newline)
                guard !lineData.isEmpty else { continue }
                self.handleStdoutLine(Data(lineData))
            }
        }
    }

    private func handleStdoutLine(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let text = String(data: data, encoding: .utf8) {
                emit(.stderr("Unparseable Codex app-server output: \(text)\n"))
            }
            return
        }

        if let id = Self.integerId(from: object["id"]),
           object["result"] != nil || object["error"] != nil {
            let request = pending.removeValue(forKey: id)
            if let errorObject = object["error"] as? [String: Any] {
                let message = errorObject["message"] as? String ?? String(describing: errorObject)
                request?.continuation.resume(throwing: CodexAppServerClientError.requestFailed(message))
            } else if let result = object["result"] as? [String: Any] {
                request?.continuation.resume(returning: result)
            } else {
                request?.continuation.resume(returning: [:])
            }
            return
        }

        guard let method = object["method"] as? String else { return }
        let params = object["params"] as? [String: Any]
        if let id = Self.integerId(from: object["id"]) {
            emit(.serverRequest(id: id, method: method, params: params))
        } else {
            emit(.notification(method: method, params: params))
        }
    }

    private func handleTermination(status: Int32) {
        stateQueue.async {
            self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            self.stderrPipe?.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            self.stdinPipe = nil
            self.stdoutPipe = nil
            self.stderrPipe = nil
            self.failPending(CodexAppServerClientError.processExited)
            self.emit(.terminated(status))
        }
    }

    private func failPending(_ error: Error) {
        let pending = self.pending
        self.pending.removeAll()
        for request in pending.values {
            request.continuation.resume(throwing: error)
        }
    }

    private func emit(_ event: CodexAppServerEvent) {
        callbackQueue.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private static func integerId(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}
