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
    case notification(CodexAppServerServerNotification)
    case serverRequest(CodexAppServerServerRequest)
    case stderr(String)
    case terminated(Int32)
}

struct CodexAppServerLaunchConfiguration: Equatable {
    var executablePath: String
    var arguments: [String]
    var environment: [String: String]
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

    static func response(id: Int, result: [String: Any]) -> [String: Any] {
        [
            "id": id,
            "result": result,
        ]
    }

    static func errorResponse(id: Int, message: String) -> [String: Any] {
        [
            "id": id,
            "error": [
                "code": -32000,
                "message": message,
            ],
        ]
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

    static func threadResumeRequest(id: Int, threadId: String, cwd: String?) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadId,
        ]
        if let cwd, !cwd.isEmpty {
            params["cwd"] = cwd
        }
        return request(id: id, method: "thread/resume", params: params)
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

struct CodexAppServerLineBuffer {
    private var buffer = Data()
    private var scanOffset = 0

    var bufferedByteCount: Int {
        buffer.count
    }

    mutating func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)

        var lines: [Data] = []
        while scanOffset < buffer.endIndex {
            guard let newline = buffer[scanOffset..<buffer.endIndex].firstIndex(of: 0x0A) else {
                scanOffset = buffer.endIndex
                break
            }

            let lineData = Data(buffer[..<newline])
            buffer.removeSubrange(..<buffer.index(after: newline))
            scanOffset = buffer.startIndex
            if !lineData.isEmpty {
                lines.append(lineData)
            }
        }
        return lines
    }

    mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        buffer.removeAll(keepingCapacity: keepCapacity)
        scanOffset = buffer.startIndex
    }

    mutating func finish() -> Data? {
        guard !buffer.isEmpty else { return nil }
        let data = buffer
        buffer.removeAll(keepingCapacity: false)
        scanOffset = buffer.startIndex
        return data
    }
}

final class CodexAppServerClient: @unchecked Sendable {
    typealias EventHandler = (CodexAppServerEvent) -> Void

    private final class QueueIdentity {}

    private final class PendingRequest {
        let continuation: CheckedContinuation<[String: Any], Error>
        let maximumResponseBytesToParse: Int?
        let oversizedResponseFallback: [String: Any]?

        init(
            _ continuation: CheckedContinuation<[String: Any], Error>,
            maximumResponseBytesToParse: Int? = nil,
            oversizedResponseFallback: [String: Any]? = nil
        ) {
            self.continuation = continuation
            self.maximumResponseBytesToParse = maximumResponseBytesToParse
            self.oversizedResponseFallback = oversizedResponseFallback
        }

        func fallbackIfOversized(byteCount: Int) -> [String: Any]? {
            guard let maximumResponseBytesToParse,
                  byteCount > maximumResponseBytesToParse else {
                return nil
            }
            return oversizedResponseFallback
        }
    }

    private static let maximumResumeResponseBytesToParse = 16 * 1024 * 1024
    private static let stateQueueSpecificKey = DispatchSpecificKey<QueueIdentity>()

    private let stateQueue = DispatchQueue(label: "cmux.codexAppServerClient.state")
    private let stateQueueIdentity = QueueIdentity()
    private let callbackQueue: DispatchQueue
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutLineBuffer = CodexAppServerLineBuffer()
    private var nextRequestId = 1
    private var pending: [Int: PendingRequest] = [:]

    var onEvent: EventHandler?

    init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
        stateQueue.setSpecific(key: Self.stateQueueSpecificKey, value: stateQueueIdentity)
    }

    deinit {
        stopFromDeinit()
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
        stateQueue.async {
            self.stopLocked()
        }
    }

    private func stopFromDeinit() {
        if DispatchQueue.getSpecific(key: Self.stateQueueSpecificKey) === stateQueueIdentity {
            stopLocked()
        } else {
            stateQueue.sync {
                stopLocked()
            }
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

    func resumeThread(threadId: String, cwd: String?) async throws -> [String: Any] {
        let response = try await sendRequestObject(
            CodexAppServerRequestFactory.threadResumeRequest(id: nextId(), threadId: threadId, cwd: cwd),
            maximumResponseBytesToParse: Self.maximumResumeResponseBytesToParse,
            oversizedResponseFallback: [
                "thread": ["id": threadId],
                "_cmuxResponseTruncated": true,
            ]
        )
        guard let thread = response["thread"] as? [String: Any],
              let resumedThreadId = thread["id"] as? String,
              !resumedThreadId.isEmpty else {
            throw CodexAppServerClientError.invalidResponse("thread/resume response did not include thread.id")
        }
        return response
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

    func respondToServerRequest(id: Int, result: [String: Any]) throws {
        try sendResponseObject(CodexAppServerRequestFactory.response(id: id, result: result))
    }

    func rejectServerRequest(id: Int, message: String) throws {
        try sendResponseObject(CodexAppServerRequestFactory.errorResponse(id: id, message: message))
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

        let configuration = Self.appServerLaunchConfiguration()
        process.executableURL = URL(fileURLWithPath: configuration.executablePath)
        process.arguments = configuration.arguments
        process.environment = configuration.environment
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
        stdoutLineBuffer.removeAll(keepingCapacity: false)
        failPending(CodexAppServerClientError.processExited)
    }

    static func appServerLaunchConfiguration(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CodexAppServerLaunchConfiguration {
        let environment = appServerEnvironment(baseEnvironment: baseEnvironment)
        let codexPath = resolvedExecutablePath("codex", environment: environment)
        let nodePath = resolvedExecutablePath("node", environment: environment)

        if let codexPath,
           let nodePath,
           executableUsesEnvNode(codexPath) {
            return CodexAppServerLaunchConfiguration(
                executablePath: nodePath,
                arguments: [codexPath, "app-server", "--listen", "stdio://"],
                environment: environment
            )
        }

        if let codexPath {
            return CodexAppServerLaunchConfiguration(
                executablePath: codexPath,
                arguments: ["app-server", "--listen", "stdio://"],
                environment: environment
            )
        }

        return CodexAppServerLaunchConfiguration(
            executablePath: "/usr/bin/env",
            arguments: ["codex", "app-server", "--listen", "stdio://"],
            environment: environment
        )
    }

    static func appServerEnvironment(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = baseEnvironment
        let paths = commandSearchDirectories(environment: environment)
        let existing = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        let merged = (paths + existing)
            .reduce(into: [String]()) { paths, candidate in
                guard !candidate.isEmpty, !paths.contains(candidate) else { return }
                paths.append(candidate)
            }
            .joined(separator: ":")
        environment["PATH"] = merged
        return environment
    }

    static func resolvedExecutablePath(
        _ executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard !executable.isEmpty else { return nil }
        let fileManager = FileManager.default
        if executable.contains("/") {
            return fileManager.isExecutableFile(atPath: executable) ? executable : nil
        }

        for directory in commandSearchDirectories(environment: environment) {
            let path = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(executable)
                .path
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func commandSearchDirectories(environment: [String: String]) -> [String] {
        var paths: [String] = []
        var seen: Set<String> = []

        func append(_ path: String?) {
            guard let path else { return }
            for component in path.split(separator: ":").map(String.init) {
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      seen.insert(trimmed).inserted else {
                    continue
                }
                paths.append(trimmed)
            }
        }

        let home = environment["HOME"]?.isEmpty == false ? environment["HOME"]! : NSHomeDirectory()
        append(environment["PATH"])
        if let resourceBinPath = Bundle.main.resourceURL?.appendingPathComponent("bin").path {
            append(resourceBinPath)
        }
        append((home as NSString).appendingPathComponent(".bun/bin"))
        append((home as NSString).appendingPathComponent(".local/bin"))
        append((home as NSString).appendingPathComponent("bin"))
        append((home as NSString).appendingPathComponent(".volta/bin"))
        append((home as NSString).appendingPathComponent(".asdf/shims"))
        append((home as NSString).appendingPathComponent(".deno/bin"))
        append((home as NSString).appendingPathComponent("Library/pnpm"))
        appendNodeVersionManagerPaths(home: home, append: append)
        append("/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/opt/local/bin")
        append("/usr/bin:/bin:/usr/sbin:/sbin")
        return paths
    }

    private static func appendNodeVersionManagerPaths(home: String, append: (String?) -> Void) {
        let fileManager = FileManager.default

        append((home as NSString).appendingPathComponent(".nvm/current/bin"))
        let nvmVersions = (home as NSString).appendingPathComponent(".nvm/versions/node")
        for version in sortedNodeVersionDirectories(in: nvmVersions, fileManager: fileManager) {
            append((nvmVersions as NSString).appendingPathComponent("\(version)/bin"))
        }

        let fnmVersions = (home as NSString).appendingPathComponent(".fnm/node-versions")
        for version in sortedNodeVersionDirectories(in: fnmVersions, fileManager: fileManager) {
            append((fnmVersions as NSString).appendingPathComponent("\(version)/installation/bin"))
            append((fnmVersions as NSString).appendingPathComponent("\(version)/bin"))
        }
    }

    private static func sortedNodeVersionDirectories(
        in directory: String,
        fileManager: FileManager
    ) -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return []
        }
        return names
            .filter { name in
                var isDirectory: ObjCBool = false
                let path = (directory as NSString).appendingPathComponent(name)
                return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .sorted { lhs, rhs in
                compareNodeVersionsDescending(lhs, rhs)
            }
    }

    private static func compareNodeVersionsDescending(_ lhs: String, _ rhs: String) -> Bool {
        let lhsComponents = nodeVersionComponents(lhs)
        let rhsComponents = nodeVersionComponents(rhs)
        for index in 0..<max(lhsComponents.count, rhsComponents.count) {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
        }
        return lhs > rhs
    }

    private static func nodeVersionComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    private static func executableUsesEnvNode(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.hasPrefix("#!/usr/bin/env node")
            || text.hasPrefix("#! /usr/bin/env node")
            || text.hasPrefix("#!/bin/env node")
            || text.hasPrefix("#! /bin/env node")
    }

    private func sendRequestObject(
        _ object: [String: Any],
        maximumResponseBytesToParse: Int? = nil,
        oversizedResponseFallback: [String: Any]? = nil
    ) async throws -> [String: Any] {
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

                self.pending[id] = PendingRequest(
                    continuation,
                    maximumResponseBytesToParse: maximumResponseBytesToParse,
                    oversizedResponseFallback: oversizedResponseFallback
                )
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

    private func sendResponseObject(_ object: [String: Any]) throws {
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
            for line in self.stdoutLineBuffer.append(data) {
                self.handleStdoutLine(line)
            }
        }
    }

    private func handleStdoutLine(_ data: Data) {
        if let id = Self.responseId(in: data),
           let request = pending[id],
           let fallback = request.fallbackIfOversized(byteCount: data.count) {
            pending.removeValue(forKey: id)
            request.continuation.resume(returning: fallback)
            return
        }

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
        let params = object["params"]
        if let id = Self.integerId(from: object["id"]) {
            emit(.serverRequest(CodexAppServerServerRequest(id: id, method: method, params: params)))
        } else {
            emit(.notification(CodexAppServerServerNotification(method: method, params: params)))
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
            self.stdoutLineBuffer.removeAll(keepingCapacity: false)
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

    private static func responseId(in data: Data) -> Int? {
        guard let prefix = String(data: data.prefix(4096), encoding: .utf8) else {
            return nil
        }

        var searchStart = prefix.startIndex
        while let idLabelRange = prefix.range(of: "\"id\"", range: searchStart..<prefix.endIndex) {
            var index = idLabelRange.upperBound
            while index < prefix.endIndex, prefix[index].isWhitespace {
                index = prefix.index(after: index)
            }
            guard index < prefix.endIndex, prefix[index] == ":" else {
                searchStart = idLabelRange.upperBound
                continue
            }
            index = prefix.index(after: index)
            while index < prefix.endIndex, prefix[index].isWhitespace {
                index = prefix.index(after: index)
            }

            var digits = ""
            while index < prefix.endIndex, prefix[index].isNumber {
                digits.append(prefix[index])
                index = prefix.index(after: index)
            }
            if let id = Int(digits) {
                return id
            }
            searchStart = idLabelRange.upperBound
        }
        return nil
    }
}
