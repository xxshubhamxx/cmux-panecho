import Foundation
import Combine

enum CodexAppServerPanelStatus: Equatable {
    case stopped
    case starting
    case ready
    case running
    case failed(String)

    var localizedTitle: String {
        switch self {
        case .stopped:
            return String(localized: "codexAppServer.status.stopped", defaultValue: "Stopped")
        case .starting:
            return String(localized: "codexAppServer.status.starting", defaultValue: "Starting")
        case .ready:
            return String(localized: "codexAppServer.status.ready", defaultValue: "Ready")
        case .running:
            return String(localized: "codexAppServer.status.running", defaultValue: "Running")
        case .failed:
            return String(localized: "codexAppServer.status.failed", defaultValue: "Failed")
        }
    }

    var isBusy: Bool {
        switch self {
        case .starting, .running:
            return true
        case .stopped, .ready, .failed:
            return false
        }
    }
}

enum CodexAppServerTranscriptRole: Equatable, Sendable {
    case user
    case assistant
    case event
    case stderr
    case error
}

enum CodexAppServerTranscriptPresentation: Equatable, Sendable {
    case plain
    case toolCall(name: String?)
    case toolOutput
    case commandOutput
}

struct CodexAppServerTranscriptItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var role: CodexAppServerTranscriptRole
    var title: String
    var body: String
    var date: Date
    var isStreaming: Bool
    var presentation: CodexAppServerTranscriptPresentation

    init(
        id: UUID = UUID(),
        role: CodexAppServerTranscriptRole,
        title: String,
        body: String,
        date: Date = Date(),
        isStreaming: Bool = false,
        presentation: CodexAppServerTranscriptPresentation = .plain
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.body = body
        self.date = date
        self.isStreaming = isStreaming
        self.presentation = presentation
    }
}

struct CodexAppServerPendingRequest: Identifiable {
    let id: Int
    let method: String
    let params: [String: Any]?
    let summary: String

    var supportsDecisionResponse: Bool {
        method == "item/commandExecution/requestApproval"
            || method == "item/fileChange/requestApproval"
    }
}

struct CodexAppServerResumeSnapshot: Equatable {
    var threadId: String
    var cwd: String?
    var transcriptItems: [CodexAppServerTranscriptItem]
    var totalRestoredItemCount: Int
    var didTruncate: Bool
    var responseWasTruncated: Bool
}

struct CodexSessionHistorySnapshot: Equatable, Sendable {
    var threadId: String
    var fileURL: URL?
    var transcriptItems: [CodexAppServerTranscriptItem]
    var totalDisplayableItemCount: Int
    var didTruncate: Bool
}

enum CodexAppServerTranscriptPolicy {
    static let maxItemCharacters = 160_000

    static func truncatedBody(_ body: String) -> String {
        guard body.utf8.count > maxItemCharacters else { return body }
        let prefix = String(
            localized: "codexAppServer.transcriptItem.truncatedPrefix",
            defaultValue: "[Earlier output omitted]"
        )
        return "\(prefix)\n\(String(body.suffix(maxItemCharacters)))"
    }
}

enum CodexAppServerApprovalDecision: String {
    case accept
    case decline
    case cancel
}

@MainActor
final class CodexAppServerPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .codexAppServer

    private static let restoredTranscriptItemLimit = 250
    private static let localHistoryItemLimit = 2_000
    private static let maxTranscriptItems = 2_500

    private(set) var workspaceId: UUID

    @Published var promptText: String = ""
    @Published var cwd: String
    @Published private(set) var status: CodexAppServerPanelStatus = .stopped
    @Published private(set) var transcriptItems: [CodexAppServerTranscriptItem] = []
    @Published private(set) var pendingRequests: [CodexAppServerPendingRequest] = []

    private let client: CodexAppServerClient
    private let initialResumeThreadId: String?
    private var threadId: String?
    private var currentTurnId: String?
    private var activeAssistantItemId: UUID?
    private var isStarted = false
    private var isClosed = false
    private var didResumeInitialThread = false

    var displayTitle: String {
        String(localized: "codexAppServer.panel.title", defaultValue: "Codex")
    }

    var displayIcon: String? {
        "sparkles"
    }

    var canSendPrompt: Bool {
        !status.isBusy && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: UUID = UUID(),
        workspaceId: UUID,
        cwd: String,
        resumeThreadId: String? = nil,
        client: CodexAppServerClient = CodexAppServerClient()
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.cwd = cwd
        self.initialResumeThreadId = resumeThreadId?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.client = client
        self.client.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    deinit {
        client.stop()
    }

    func start() async {
        guard !isStarted, status != .starting else { return }
        status = .starting
        do {
            try await client.startAndInitialize()
            isStarted = true
            if let initialResumeThreadId, !initialResumeThreadId.isEmpty, !didResumeInitialThread {
                status = .running
                let response = try await client.resumeThread(
                    threadId: initialResumeThreadId,
                    cwd: currentWorkingDirectory()
                )
                didResumeInitialThread = true
                let snapshot = applyResumeResponse(response, fallbackThreadId: initialResumeThreadId)
                if snapshot.responseWasTruncated {
                    await loadLocalHistory(for: snapshot.threadId)
                }
                status = .ready
                appendEvent(
                    title: String(localized: "codexAppServer.event.resumed", defaultValue: "Thread resumed"),
                    body: threadId ?? initialResumeThreadId
                )
            } else {
                status = .ready
                appendEvent(
                    title: String(localized: "codexAppServer.event.started", defaultValue: "App server started"),
                    body: currentWorkingDirectory()
                )
            }
        } catch {
            status = .failed(error.localizedDescription)
            appendError(error.localizedDescription)
        }
    }

    func stop() {
        if isStarted {
            client.stop()
        }
        isStarted = false
        threadId = nil
        currentTurnId = nil
        activeAssistantItemId = nil
        pendingRequests.removeAll()
        status = .stopped
    }

    func sendPrompt() async {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !status.isBusy else { return }
        promptText = ""
        appendUser(text)

        do {
            if !isStarted {
                await start()
            }
            guard isStarted else { return }
            let resolvedThreadId: String
            if let threadId {
                resolvedThreadId = threadId
            } else {
                let newThreadId = try await client.startThread(cwd: currentWorkingDirectory())
                threadId = newThreadId
                resolvedThreadId = newThreadId
            }

            status = .running
            currentTurnId = try await client.startTurn(
                threadId: resolvedThreadId,
                text: text,
                cwd: currentWorkingDirectory()
            )
        } catch {
            status = .failed(error.localizedDescription)
            appendError(error.localizedDescription)
        }
    }

    func resolvePendingRequest(_ request: CodexAppServerPendingRequest, decision: CodexAppServerApprovalDecision) {
        do {
            guard request.supportsDecisionResponse else {
                try client.rejectServerRequest(
                    id: request.id,
                    message: String(
                        localized: "codexAppServer.request.unsupported",
                        defaultValue: "cmux does not support this Codex app-server request yet."
                    )
                )
                removePendingRequest(id: request.id)
                return
            }

            try client.respondToServerRequest(id: request.id, result: ["decision": decision.rawValue])
            removePendingRequest(id: request.id)
            appendEvent(
                title: String(localized: "codexAppServer.event.approvalSent", defaultValue: "Approval response sent"),
                body: request.method
            )
        } catch {
            appendError(error.localizedDescription)
        }
    }

    func close() {
        isClosed = true
        stop()
    }

    func focus() {}

    func unfocus() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
    }

    private func handle(_ event: CodexAppServerEvent) {
        guard !isClosed else { return }
        switch event {
        case .notification(let notification):
            handleNotification(notification)
        case .serverRequest(let request):
            pendingRequests.append(
                CodexAppServerPendingRequest(
                    id: request.id,
                    method: request.rawMethod,
                    params: request.paramsObject,
                    summary: Self.prettyJSON(request.paramsObject)
                )
            )
            appendEvent(
                title: String(localized: "codexAppServer.event.request", defaultValue: "Approval requested"),
                body: request.rawMethod
            )
        case .stderr(let text):
            append(
                role: .stderr,
                title: String(localized: "codexAppServer.event.stderr", defaultValue: "stderr"),
                body: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .terminated(let statusCode):
            isStarted = false
            status = .stopped
            threadId = nil
            currentTurnId = nil
            activeAssistantItemId = nil
            pendingRequests.removeAll()
            appendEvent(
                title: String(localized: "codexAppServer.event.terminated", defaultValue: "App server exited"),
                body: String(statusCode)
            )
        }
    }

    private func handleNotification(_ notification: CodexAppServerServerNotification) {
        let method = notification.rawMethod
        let params = notification.paramsObject

        switch method {
        case "thread/started":
            if let thread = params?["thread"] as? [String: Any],
               let threadId = thread["id"] as? String {
                self.threadId = threadId
            }
        case "turn/started":
            status = .running
        case "turn/completed":
            status = .ready
            currentTurnId = nil
            finishStreamingAssistant()
        case "item/agentMessage/delta":
            appendAssistantDelta(Self.stringValue(named: "delta", in: params))
        case "item/commandExecution/outputDelta":
            appendCommandDelta(Self.stringValue(named: "delta", in: params))
        case "item/completed":
            handleCompletedItem(params?["item"] as? [String: Any])
        default:
            appendEvent(title: method, body: Self.prettyJSON(params))
        }
    }

    private func handleCompletedItem(_ item: [String: Any]?) {
        guard let item else { return }
        let type = item["type"] as? String ?? item["kind"] as? String ?? ""
        switch type {
        case "agentMessage":
            let text = Self.stringValue(named: "text", in: item)
                ?? Self.stringValue(named: "message", in: item)
                ?? Self.stringValue(named: "content", in: item)
            if let text, !text.isEmpty {
                if activeAssistantItemId == nil || transcriptItems.last?.role != .assistant {
                    appendAssistantDelta(text)
                }
                finishStreamingAssistant()
            }
        case "commandExecution":
            appendEvent(
                title: String(localized: "codexAppServer.event.command", defaultValue: "Command"),
                body: Self.commandSummary(from: item),
                presentation: .toolCall(name: "shell")
            )
        case "fileChange":
            appendEvent(
                title: String(localized: "codexAppServer.event.fileChange", defaultValue: "File change"),
                body: Self.prettyJSON(item)
            )
        default:
            appendEvent(title: type.isEmpty ? "item/completed" : type, body: Self.prettyJSON(item))
        }
    }

    private func appendUser(_ text: String) {
        append(
            role: .user,
            title: String(localized: "codexAppServer.role.user", defaultValue: "You"),
            body: text
        )
    }

    private func appendAssistantDelta(_ delta: String?) {
        guard let delta, !delta.isEmpty else { return }
        if let id = activeAssistantItemId,
           let index = transcriptItems.firstIndex(where: { $0.id == id }) {
            transcriptItems[index].body = Self.truncatedTranscriptBody(transcriptItems[index].body + delta)
            transcriptItems[index].date = Date()
        } else {
            let item = CodexAppServerTranscriptItem(
                role: .assistant,
                title: String(localized: "codexAppServer.role.assistant", defaultValue: "Codex"),
                body: Self.truncatedTranscriptBody(delta),
                isStreaming: true
            )
            activeAssistantItemId = item.id
            transcriptItems.append(item)
            trimTranscriptItemsIfNeeded()
        }
    }

    private func appendCommandDelta(_ delta: String?) {
        guard let delta, !delta.isEmpty else { return }
        if let index = transcriptItems.indices.last,
           transcriptItems[index].presentation == .commandOutput {
            transcriptItems[index].body = Self.truncatedTranscriptBody(transcriptItems[index].body + delta)
            transcriptItems[index].date = Date()
            return
        }
        append(
            role: .event,
            title: String(localized: "codexAppServer.event.output", defaultValue: "Output"),
            body: delta,
            presentation: .commandOutput
        )
    }

    private func finishStreamingAssistant() {
        guard let id = activeAssistantItemId,
              let index = transcriptItems.firstIndex(where: { $0.id == id }) else {
            activeAssistantItemId = nil
            return
        }
        transcriptItems[index].isStreaming = false
        activeAssistantItemId = nil
    }

    private func appendEvent(
        title: String,
        body: String,
        presentation: CodexAppServerTranscriptPresentation = .plain
    ) {
        append(role: .event, title: title, body: body, presentation: presentation)
    }

    private func appendError(_ message: String) {
        append(
            role: .error,
            title: String(localized: "codexAppServer.event.error", defaultValue: "Error"),
            body: message
        )
    }

    @discardableResult
    private func applyResumeResponse(_ response: [String: Any], fallbackThreadId: String) -> CodexAppServerResumeSnapshot {
        let snapshot = Self.resumeSnapshot(
            from: response,
            fallbackThreadId: fallbackThreadId,
            restoredItemLimit: Self.restoredTranscriptItemLimit
        )
        threadId = snapshot.threadId
        if let resumedCwd = snapshot.cwd, !resumedCwd.isEmpty {
            cwd = resumedCwd
        }

        activeAssistantItemId = nil

        if snapshot.responseWasTruncated {
            return snapshot
        }

        guard !snapshot.transcriptItems.isEmpty else { return snapshot }
        if snapshot.didTruncate {
            transcriptItems = [
                Self.historyTruncatedItem(
                    displayedCount: snapshot.transcriptItems.count,
                    totalCount: snapshot.totalRestoredItemCount,
                    date: snapshot.transcriptItems.first?.date
                )
            ] + snapshot.transcriptItems
        } else {
            transcriptItems = snapshot.transcriptItems
        }
        return snapshot
    }

    private func loadLocalHistory(for threadId: String) async {
        let snapshot = await CodexSessionHistoryLoader.loadHistory(
            threadId: threadId,
            limit: Self.localHistoryItemLimit
        )
        guard !isClosed else { return }
        guard !snapshot.transcriptItems.isEmpty else {
            appendEvent(
                title: String(localized: "codexAppServer.event.historyOmitted", defaultValue: "History omitted"),
                body: String(
                    localized: "codexAppServer.event.historyOmitted.body",
                    defaultValue: "Codex returned a very large history. The thread is connected, and new messages will stream here."
                )
            )
            return
        }

        activeAssistantItemId = nil
        if snapshot.didTruncate {
            transcriptItems = [
                Self.historyTruncatedItem(
                    displayedCount: snapshot.transcriptItems.count,
                    totalCount: snapshot.totalDisplayableItemCount,
                    date: snapshot.transcriptItems.first?.date
                )
            ] + snapshot.transcriptItems
        } else {
            transcriptItems = snapshot.transcriptItems
        }
        let format = String(
            localized: "codexAppServer.event.historyLoaded.body",
            defaultValue: "Loaded the latest %1$ld items from local Codex history."
        )
        appendEvent(
            title: String(localized: "codexAppServer.event.historyLoaded", defaultValue: "History loaded"),
            body: String(
                format: format,
                locale: Locale.current,
                snapshot.transcriptItems.count
            )
        )
    }

    static func resumeSnapshot(
        from response: [String: Any],
        fallbackThreadId: String,
        restoredItemLimit: Int
    ) -> CodexAppServerResumeSnapshot {
        let thread = response["thread"] as? [String: Any]
        let resolvedThreadId = Self.stringValue(named: "id", in: thread) ?? fallbackThreadId
        let resolvedCwd = Self.stringValue(named: "cwd", in: response)
            ?? Self.stringValue(named: "cwd", in: thread)
        let responseWasTruncated = (response["_cmuxResponseTruncated"] as? Bool) == true
        guard !responseWasTruncated else {
            return CodexAppServerResumeSnapshot(
                threadId: resolvedThreadId,
                cwd: resolvedCwd,
                transcriptItems: [],
                totalRestoredItemCount: 0,
                didTruncate: false,
                responseWasTruncated: true
            )
        }

        let turns = thread?["turns"] as? [[String: Any]] ?? []
        var restoredItems: [CodexAppServerTranscriptItem] = []
        for turn in turns {
            let date = Self.dateValue(named: "startedAt", in: turn) ?? Date()
            let items = turn["items"] as? [[String: Any]] ?? []
            for item in items {
                if let restoredItem = restoredTranscriptItem(fromThreadItem: item, date: date) {
                    restoredItems.append(restoredItem)
                }
            }
        }

        let totalRestoredItemCount = restoredItems.count
        let limit = max(1, restoredItemLimit)
        let didTruncate = totalRestoredItemCount > limit
        if didTruncate {
            restoredItems = Array(restoredItems.suffix(limit))
        }

        return CodexAppServerResumeSnapshot(
            threadId: resolvedThreadId,
            cwd: resolvedCwd,
            transcriptItems: restoredItems,
            totalRestoredItemCount: totalRestoredItemCount,
            didTruncate: didTruncate,
            responseWasTruncated: false
        )
    }

    private static func historyTruncatedItem(
        displayedCount: Int,
        totalCount: Int,
        date: Date?
    ) -> CodexAppServerTranscriptItem {
        let format = String(
            localized: "codexAppServer.event.historyTruncated.body",
            defaultValue: "Showing the latest %1$ld of %2$ld history items."
        )
        let body = String(
            format: format,
            locale: Locale.current,
            displayedCount,
            totalCount
        )
        return CodexAppServerTranscriptItem(
            role: .event,
            title: String(localized: "codexAppServer.event.historyTruncated", defaultValue: "Earlier history omitted"),
            body: body,
            date: date ?? Date()
        )
    }

    private static func restoredTranscriptItem(
        fromThreadItem item: [String: Any],
        date: Date
    ) -> CodexAppServerTranscriptItem? {
        let type = Self.stringValue(named: "type", in: item) ?? ""
        switch type {
        case "userMessage":
            guard let text = Self.userMessageText(from: item), !text.isEmpty else { return nil }
            return CodexAppServerTranscriptItem(
                role: .user,
                title: String(localized: "codexAppServer.role.user", defaultValue: "You"),
                body: Self.truncatedTranscriptBody(text),
                date: date
            )
        case "agentMessage":
            guard let text = Self.stringValue(named: "text", in: item), !text.isEmpty else { return nil }
            return CodexAppServerTranscriptItem(
                role: .assistant,
                title: String(localized: "codexAppServer.role.assistant", defaultValue: "Codex"),
                body: Self.truncatedTranscriptBody(text),
                date: date
            )
        case "plan":
            guard let text = Self.stringValue(named: "text", in: item), !text.isEmpty else { return nil }
            return CodexAppServerTranscriptItem(
                role: .event,
                title: String(localized: "codexAppServer.event.plan", defaultValue: "Plan"),
                body: Self.truncatedTranscriptBody(text),
                date: date
            )
        case "commandExecution":
            return CodexAppServerTranscriptItem(
                role: .event,
                title: String(localized: "codexAppServer.event.command", defaultValue: "Command"),
                body: Self.truncatedTranscriptBody(Self.commandSummary(from: item)),
                date: date,
                presentation: .toolCall(name: "shell")
            )
        case "fileChange":
            return CodexAppServerTranscriptItem(
                role: .event,
                title: String(localized: "codexAppServer.event.fileChange", defaultValue: "File change"),
                body: Self.truncatedTranscriptBody(Self.prettyJSON(item)),
                date: date
            )
        default:
            let body = Self.stringValue(named: "text", in: item) ?? Self.prettyJSON(item)
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return CodexAppServerTranscriptItem(
                role: .event,
                title: type.isEmpty
                    ? String(localized: "codexAppServer.event.item", defaultValue: "Item")
                    : type,
                body: Self.truncatedTranscriptBody(body),
                date: date
            )
        }
    }

    private func append(
        role: CodexAppServerTranscriptRole,
        title: String,
        body: String,
        presentation: CodexAppServerTranscriptPresentation = .plain
    ) {
        let trimmedBody = Self.truncatedTranscriptBody(body.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmedBody.isEmpty else { return }
        transcriptItems.append(
            CodexAppServerTranscriptItem(
                role: role,
                title: title,
                body: trimmedBody,
                presentation: presentation
            )
        )
        trimTranscriptItemsIfNeeded()
    }

    private func trimTranscriptItemsIfNeeded() {
        let overflow = transcriptItems.count - Self.maxTranscriptItems
        guard overflow > 0 else { return }

        var remainingToRemove = overflow
        transcriptItems.removeAll { item in
            guard remainingToRemove > 0 else { return false }
            if let activeAssistantItemId, item.id == activeAssistantItemId {
                return false
            }
            remainingToRemove -= 1
            return true
        }
    }

    private static func truncatedTranscriptBody(_ body: String) -> String {
        CodexAppServerTranscriptPolicy.truncatedBody(body)
    }

    private func removePendingRequest(id: Int) {
        pendingRequests.removeAll { $0.id == id }
    }

    private func currentWorkingDirectory() -> String {
        cwd.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringValue(named key: String, in object: [String: Any]?) -> String? {
        guard let value = object?[key] else { return nil }
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func dateValue(named key: String, in object: [String: Any]?) -> Date? {
        guard let value = object?[key] else { return nil }
        if let value = value as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        if let value = value as? Double {
            return Date(timeIntervalSince1970: value)
        }
        if let value = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        return nil
    }

    private static func userMessageText(from item: [String: Any]) -> String? {
        guard let content = item["content"] as? [[String: Any]] else { return nil }
        let parts = content.compactMap { input -> String? in
            if let text = stringValue(named: "text", in: input) {
                return text
            }
            if let url = stringValue(named: "url", in: input) {
                return url
            }
            return nil
        }
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func commandSummary(from item: [String: Any]) -> String {
        if let command = item["command"] as? String {
            return command
        }
        if let command = item["command"] as? [String] {
            return command.joined(separator: " ")
        }
        return Self.prettyJSON(item)
    }

    private static func prettyJSON(_ value: Any?) -> String {
        guard let value else { return "{}" }
        let object: Any
        if JSONSerialization.isValidJSONObject(value) {
            object = value
        } else {
            object = ["value": String(describing: value)]
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}

enum CodexSessionHistoryLoader {
    private static let chunkSize = 1024 * 1024
    private static let responseItemNeedle = Data(#""type":"response_item""#.utf8)
    private static let messageNeedle = Data(#""type":"message""#.utf8)
    private static let userRoleNeedle = Data(#""role":"user""#.utf8)
    private static let assistantRoleNeedle = Data(#""role":"assistant""#.utf8)
    private static let functionCallNeedle = Data(#""type":"function_call""#.utf8)
    private static let functionCallOutputNeedle = Data(#""type":"function_call_output""#.utf8)

    static func loadHistory(threadId: String, limit: Int) async -> CodexSessionHistorySnapshot {
        await Task.detached(priority: .utility) {
            loadHistorySync(threadId: threadId, limit: limit)
        }.value
    }

    static func loadHistorySync(
        threadId: String,
        limit: Int,
        searchRoots: [URL]? = nil
    ) -> CodexSessionHistorySnapshot {
        let sanitizedThreadId = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedThreadId.isEmpty else {
            return emptySnapshot(threadId: threadId, fileURL: nil)
        }

        let roots = searchRoots ?? defaultSearchRoots()
        guard let fileURL = historyFile(threadId: sanitizedThreadId, searchRoots: roots) else {
            return emptySnapshot(threadId: sanitizedThreadId, fileURL: nil)
        }

        return parseHistoryFile(fileURL, threadId: sanitizedThreadId, limit: limit)
    }

    private static func defaultSearchRoots() -> [URL] {
        let codexHome = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        return [
            codexHome.appendingPathComponent("sessions", isDirectory: true),
            codexHome.appendingPathComponent("archived_sessions", isDirectory: true),
        ]
    }

    private static func emptySnapshot(threadId: String, fileURL: URL?) -> CodexSessionHistorySnapshot {
        CodexSessionHistorySnapshot(
            threadId: threadId,
            fileURL: fileURL,
            transcriptItems: [],
            totalDisplayableItemCount: 0,
            didTruncate: false
        )
    }

    private static func historyFile(threadId: String, searchRoots: [URL]) -> URL? {
        var jsonlFiles: [URL] = []
        for root in searchRoots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                guard isRegularFile(fileURL) else { continue }
                jsonlFiles.append(fileURL)
            }
        }

        let filenameMatches = jsonlFiles.filter { $0.lastPathComponent.contains(threadId) }
        if let match = sortedMostRecentlyModified(filenameMatches).first {
            return match
        }

        let metadataMatches = jsonlFiles.filter { sessionMetadataMatches(fileURL: $0, threadId: threadId) }
        return sortedMostRecentlyModified(metadataMatches).first
    }

    private static func sortedMostRecentlyModified(_ files: [URL]) -> [URL] {
        files.sorted { lhs, rhs in
            modificationDate(lhs) > modificationDate(rhs)
        }
    }

    private static func modificationDate(_ fileURL: URL) -> Date {
        (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func isRegularFile(_ fileURL: URL) -> Bool {
        (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func sessionMetadataMatches(fileURL: URL, threadId: String) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024), !data.isEmpty else {
            return false
        }
        let idNeedle = Data(("\"id\":\"\(threadId)\"").utf8)
        return data.range(of: idNeedle) != nil
    }

    private static func parseHistoryFile(
        _ fileURL: URL,
        threadId: String,
        limit: Int
    ) -> CodexSessionHistorySnapshot {
        let resolvedLimit = max(1, limit)
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return emptySnapshot(threadId: threadId, fileURL: fileURL)
        }
        defer { try? handle.close() }

        var lineBuffer = CodexAppServerLineBuffer()
        var transcriptItems: [CodexAppServerTranscriptItem] = []
        var totalDisplayableItemCount = 0

        func consume(_ line: Data) {
            guard shouldParseLine(line),
                  let item = transcriptItem(from: line) else {
                return
            }
            totalDisplayableItemCount += 1
            transcriptItems.append(item)
            if transcriptItems.count > resolvedLimit * 2 {
                transcriptItems.removeFirst(transcriptItems.count - resolvedLimit)
            }
        }

        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: chunkSize)
            } catch {
                break
            }
            guard let chunk, !chunk.isEmpty else {
                break
            }
            for line in lineBuffer.append(chunk) {
                consume(line)
            }
        }
        if let finalLine = lineBuffer.finish() {
            consume(finalLine)
        }

        if transcriptItems.count > resolvedLimit {
            transcriptItems = Array(transcriptItems.suffix(resolvedLimit))
        }

        return CodexSessionHistorySnapshot(
            threadId: threadId,
            fileURL: fileURL,
            transcriptItems: transcriptItems,
            totalDisplayableItemCount: totalDisplayableItemCount,
            didTruncate: totalDisplayableItemCount > transcriptItems.count
        )
    }

    private static func shouldParseLine(_ line: Data) -> Bool {
        guard line.range(of: responseItemNeedle) != nil else { return false }
        if line.range(of: messageNeedle) != nil {
            return line.range(of: userRoleNeedle) != nil || line.range(of: assistantRoleNeedle) != nil
        }
        return line.range(of: functionCallNeedle) != nil
            || line.range(of: functionCallOutputNeedle) != nil
    }

    private static func transcriptItem(from line: Data) -> CodexAppServerTranscriptItem? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any] else {
            return nil
        }

        let date = dateValue(named: "timestamp", in: object) ?? Date()
        switch stringValue(named: "type", in: payload) {
        case "message":
            return messageTranscriptItem(from: payload, date: date)
        case "function_call":
            return functionCallTranscriptItem(from: payload, date: date)
        case "function_call_output":
            return functionCallOutputTranscriptItem(from: payload, date: date)
        default:
            return nil
        }
    }

    private static func messageTranscriptItem(
        from payload: [String: Any],
        date: Date
    ) -> CodexAppServerTranscriptItem? {
        let role = stringValue(named: "role", in: payload)
        let transcriptRole: CodexAppServerTranscriptRole
        let title: String
        switch role {
        case "user":
            transcriptRole = .user
            title = String(localized: "codexAppServer.role.user", defaultValue: "You")
        case "assistant":
            transcriptRole = .assistant
            title = String(localized: "codexAppServer.role.assistant", defaultValue: "Codex")
        default:
            return nil
        }

        guard let text = messageText(from: payload["content"]), !text.isEmpty else {
            return nil
        }
        return CodexAppServerTranscriptItem(
            role: transcriptRole,
            title: title,
            body: CodexAppServerTranscriptPolicy.truncatedBody(text),
            date: date
        )
    }

    private static func functionCallTranscriptItem(
        from payload: [String: Any],
        date: Date
    ) -> CodexAppServerTranscriptItem? {
        let name = stringValue(named: "name", in: payload)
        let body = functionCallBody(from: payload).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let title = (name?.isEmpty == false ? name : nil)
            ?? String(localized: "codexAppServer.event.toolCall", defaultValue: "Tool call")
        return CodexAppServerTranscriptItem(
            role: .event,
            title: title,
            body: CodexAppServerTranscriptPolicy.truncatedBody(body),
            date: date,
            presentation: .toolCall(name: name)
        )
    }

    private static func functionCallOutputTranscriptItem(
        from payload: [String: Any],
        date: Date
    ) -> CodexAppServerTranscriptItem? {
        guard let output = stringValue(named: "output", in: payload)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }
        return CodexAppServerTranscriptItem(
            role: .event,
            title: String(localized: "codexAppServer.event.toolOutput", defaultValue: "Tool output"),
            body: CodexAppServerTranscriptPolicy.truncatedBody(output),
            date: date,
            presentation: .toolOutput
        )
    }

    private static func messageText(from content: Any?) -> String? {
        if let text = content as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let parts = content as? [[String: Any]] else { return nil }
        let text = parts.compactMap { part -> String? in
            if let text = stringValue(named: "text", in: part) {
                return text
            }
            if let text = stringValue(named: "content", in: part) {
                return text
            }
            if let url = stringValue(named: "url", in: part) {
                return url
            }
            return nil
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func functionCallBody(from payload: [String: Any]) -> String {
        guard let arguments = stringValue(named: "arguments", in: payload) else {
            return prettyJSON(payload)
        }
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return arguments
        }

        if let command = stringValue(named: "cmd", in: object) {
            return command
        }
        if let command = stringValue(named: "command", in: object) {
            return command
        }
        if let command = object["command"] as? [String] {
            return command.joined(separator: " ")
        }
        return prettyJSON(object)
    }

    private static func stringValue(named key: String, in object: [String: Any]?) -> String? {
        guard let value = object?[key] else { return nil }
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func dateValue(named key: String, in object: [String: Any]?) -> Date? {
        guard let value = object?[key] else { return nil }
        if let value = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            return ISO8601DateFormatter().date(from: value)
        }
        if let value = value as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        return nil
    }

    private static func prettyJSON(_ value: Any?) -> String {
        guard let value else { return "{}" }
        let object: Any
        if JSONSerialization.isValidJSONObject(value) {
            object = value
        } else {
            object = ["value": String(describing: value)]
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}
