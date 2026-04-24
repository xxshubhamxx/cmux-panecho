import AppKit
import CodexTrajectory
import SwiftUI

struct CodexTrajectoryTranscriptView: NSViewRepresentable {
    var items: [CodexAppServerTranscriptItem]

    func makeNSView(context: Context) -> CodexTrajectoryTranscriptScrollView {
        CodexTrajectoryTranscriptScrollView()
    }

    func updateNSView(_ nsView: CodexTrajectoryTranscriptScrollView, context: Context) {
        nsView.update(entries: CodexTrajectoryTranscriptDisplayEntry.entries(from: items))
    }
}

enum CodexTrajectoryTranscriptDisplayKind: Hashable {
    case plain
    case toolGroup
    case compaction
}

struct CodexTrajectoryTranscriptDisplayEntry: Hashable {
    var id: String
    var kind: CodexTrajectoryTranscriptDisplayKind
    var title: String
    var subtitle: String
    var statusText: String?
    var block: CodexTrajectoryBlock

    var isAccordion: Bool {
        kind == .toolGroup
    }

    var isCompaction: Bool {
        kind == .compaction
    }

    static func entries(from items: [CodexAppServerTranscriptItem]) -> [Self] {
        var entries: [Self] = []
        var toolItems: [CodexAppServerTranscriptItem] = []

        func flushToolItems() {
            guard !toolItems.isEmpty else { return }
            if let entry = toolGroup(from: toolItems) {
                entries.append(entry)
            }
            toolItems.removeAll(keepingCapacity: true)
        }

        for item in items {
            if item.isToolTranscriptItem {
                toolItems.append(item)
            } else if item.presentation == .compaction {
                flushToolItems()
                entries.append(compaction(from: item))
            } else {
                flushToolItems()
                entries.append(plain(from: item))
            }
        }
        flushToolItems()
        return entries
    }

    private static func compaction(from item: CodexAppServerTranscriptItem) -> Self {
        Self(
            id: item.id.uuidString,
            kind: .compaction,
            title: item.title,
            subtitle: "",
            statusText: nil,
            block: CodexTrajectoryBlock(
                id: item.id.uuidString,
                kind: .status,
                title: item.title,
                text: "",
                isStreaming: false,
                createdAt: item.date
            )
        )
    }

    private static func plain(from item: CodexAppServerTranscriptItem) -> Self {
        Self(
            id: item.id.uuidString,
            kind: .plain,
            title: item.title,
            subtitle: "",
            statusText: nil,
            block: CodexTrajectoryBlock(
                id: item.id.uuidString,
                kind: item.trajectoryKind,
                title: item.title,
                text: item.body,
                isStreaming: item.isStreaming,
                createdAt: item.date
            )
        )
    }

    private static func toolGroup(from items: [CodexAppServerTranscriptItem]) -> Self? {
        guard let first = items.first else { return nil }
        let runs = CodexTrajectoryToolRun.runs(from: items)
        let detailText = runs.map(\.detailText).filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !detailText.isEmpty else { return nil }

        let title = CodexTrajectoryToolRun.title(for: runs)

        let subtitle = runs.compactMap(\.summary).first ?? first.title
        return Self(
            id: "toolgroup-\(first.id.uuidString)",
            kind: .toolGroup,
            title: title,
            subtitle: subtitle,
            statusText: statusText(for: runs),
            block: CodexTrajectoryBlock(
                id: "toolgroup-\(first.id.uuidString)-content",
                kind: .commandOutput,
                title: "",
                text: detailText,
                isStreaming: items.contains(where: \.isStreaming),
                createdAt: first.date
            )
        )
    }

    private static func statusText(for runs: [CodexTrajectoryToolRun]) -> String? {
        let exitCodes = runs.compactMap(\.exitCode)
        guard !exitCodes.isEmpty else { return nil }
        if let failingCode = exitCodes.first(where: { $0 != 0 }) {
            let format = String(
                localized: "codexAppServer.toolGroup.exitCode",
                defaultValue: "Exit code %1$ld"
            )
            return String(format: format, locale: Locale.current, failingCode)
        }
        guard exitCodes.count == runs.count else { return nil }
        return String(localized: "codexAppServer.toolGroup.success", defaultValue: "Success")
    }
}

private enum CodexTrajectoryToolRunKind: Hashable {
    case command
    case edit
    case read
    case search
    case list
    case webSearch
    case tool
}

private struct CodexTrajectoryToolRun: Hashable {
    var kind: CodexTrajectoryToolRunKind
    var label: String
    var summaryLine: String
    var command: String
    var output: String
    var exitCode: Int?

    var summary: String? {
        if !summaryLine.isEmpty {
            return summaryLine
        }
        return output.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    var detailText: String {
        let heading = summaryLine.isEmpty ? label : summaryLine
        var lines: [String] = [heading]
        if !command.isEmpty {
            let commandHeading = String(
                format: String(localized: "codexAppServer.toolGroup.ranCommandLine", defaultValue: "Ran %@"),
                locale: Locale.current,
                command
            )
            if heading != commandHeading {
                lines.append("")
                lines.append("$ \(command)")
            }
        }
        if !output.isEmpty {
            lines.append("")
            lines.append(output)
        }
        if let exitCode {
            lines.append("")
            let format = String(
                localized: "codexAppServer.toolGroup.exitCode",
                defaultValue: "Exit code %1$ld"
            )
            lines.append(String(format: format, locale: Locale.current, exitCode))
        }
        return lines.joined(separator: "\n")
    }

    static func runs(from items: [CodexAppServerTranscriptItem]) -> [Self] {
        var runs: [Self] = []
        for item in items {
            switch item.presentation {
            case .toolCall(let name):
                let newRuns = runsForToolCall(name: name, body: item.body, fallbackTitle: item.title)
                if let run = runs.last, run.command.isEmpty, !run.output.isEmpty {
                    if newRuns.count == 1 {
                        var merged = newRuns[0]
                        merged.output = run.output
                        merged.exitCode = run.exitCode
                        runs[runs.count - 1] = merged
                    } else {
                        runs.append(contentsOf: newRuns)
                    }
                    continue
                }
                runs.append(contentsOf: newRuns)
            case .toolOutput, .commandOutput:
                let normalized = CodexTrajectoryToolOutput.normalize(item.body)
                if runs.isEmpty {
                    runs.append(
                        Self(
                            kind: .tool,
                            label: item.title.isEmpty ? outputLabel : item.title,
                            summaryLine: item.title.isEmpty ? outputLabel : item.title,
                            command: "",
                            output: normalized.text,
                            exitCode: normalized.exitCode
                        )
                    )
                } else {
                    var run = runs.removeLast()
                    if !normalized.text.isEmpty {
                        if run.output.isEmpty {
                            run.output = normalized.text
                        } else {
                            run.output += "\n" + normalized.text
                        }
                    }
                    if let exitCode = normalized.exitCode {
                        run.exitCode = exitCode
                    }
                    runs.append(run)
                }
            case .plain, .compaction:
                break
            }
        }
        return runs
    }

    static func title(for runs: [Self]) -> String {
        let editCount = count(.edit, in: runs)
        let commandCount = count(.command, in: runs)
        let readCount = count(.read, in: runs)
        let searchCount = count(.search, in: runs)
        let listCount = count(.list, in: runs)
        let webSearchCount = count(.webSearch, in: runs)
        let toolCount = count(.tool, in: runs)

        var parts: [String] = []
        if editCount > 0 {
            parts.append(editCountTitle(editCount))
        }

        let hasExploration = readCount > 0 || searchCount > 0 || listCount > 0
        if hasExploration {
            let explorationParts = [
                readCount > 0 ? fileCountTitle(readCount) : nil,
                searchCount > 0 ? searchCountTitle(searchCount) : nil,
                listCount > 0 ? listCountTitle(listCount) : nil,
            ].compactMap { $0 }

            if editCount == 0 {
                let format = String(
                    localized: "codexAppServer.toolGroup.explored",
                    defaultValue: "Explored %@"
                )
                parts.append(
                    String(
                        format: format,
                        locale: Locale.current,
                        explorationParts.joined(separator: ", ")
                    )
                )
            } else {
                parts.append(contentsOf: explorationParts)
            }
        }

        if commandCount > 0 {
            parts.append(commandCountTitle(commandCount, isContinuation: !parts.isEmpty))
        }
        if webSearchCount > 0 {
            parts.append(webSearchCountTitle(webSearchCount, isContinuation: !parts.isEmpty))
        }
        if toolCount > 0 {
            parts.append(toolCountTitle(toolCount))
        }

        guard !parts.isEmpty else {
            return String(localized: "codexAppServer.toolGroup.ranTool.one", defaultValue: "Ran tool")
        }
        return parts.joined(separator: ", ")
    }

    private static func runsForToolCall(name: String?, body: String, fallbackTitle: String) -> [Self] {
        let toolName = normalizedToolName(name ?? fallbackTitle)
        switch toolName {
        case "exec_command", "functions.exec_command", "shell", "command":
            return [shellRun(command: body, fallbackTitle: fallbackTitle)]
        case "apply_patch", "functions.apply_patch":
            return editRuns(from: body, fallbackTitle: fallbackTitle)
        case "web.run", "web":
            return webSearchRuns(from: body, fallbackTitle: fallbackTitle)
        case "tool_search.tool_search_tool", "tool_search_tool":
            return [toolSearchRun(from: body, fallbackTitle: fallbackTitle)]
        case "multi_tool_use.parallel":
            let nested = parallelToolRuns(from: body, fallbackTitle: fallbackTitle)
            return nested.isEmpty ? [genericToolRun(name: name, body: body, fallbackTitle: fallbackTitle)] : nested
        default:
            return [genericToolRun(name: name, body: body, fallbackTitle: fallbackTitle)]
        }
    }

    private static func shellRun(command: String, fallbackTitle: String) -> Self {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = shellTokens(from: trimmed)
        let executable = tokens.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""

        if isListCommand(executable: executable, tokens: tokens) {
            return Self(
                kind: .list,
                label: toolLabel(name: "shell", fallback: fallbackTitle),
                summaryLine: String(localized: "codexAppServer.toolGroup.listedFiles", defaultValue: "Listed files"),
                command: trimmed,
                output: "",
                exitCode: nil
            )
        }

        if isReadCommand(executable: executable),
           let path = fileArgument(from: tokens) {
            let format = String(
                localized: "codexAppServer.toolGroup.readFile",
                defaultValue: "Read %@"
            )
            return Self(
                kind: .read,
                label: toolLabel(name: "shell", fallback: fallbackTitle),
                summaryLine: String(format: format, locale: Locale.current, displayPath(path)),
                command: trimmed,
                output: "",
                exitCode: nil
            )
        }

        if isSearchCommand(executable: executable),
           let search = searchArguments(from: tokens) {
            let summary: String
            if let path = search.path, !path.isEmpty {
                let format = String(
                    localized: "codexAppServer.toolGroup.searchedForIn",
                    defaultValue: "Searched for %@ in %@"
                )
                summary = String(
                    format: format,
                    locale: Locale.current,
                    search.query,
                    displayPath(path)
                )
            } else {
                let format = String(
                    localized: "codexAppServer.toolGroup.searchedFor",
                    defaultValue: "Searched for %@"
                )
                summary = String(format: format, locale: Locale.current, search.query)
            }
            return Self(
                kind: .search,
                label: toolLabel(name: "shell", fallback: fallbackTitle),
                summaryLine: summary,
                command: trimmed,
                output: "",
                exitCode: nil
            )
        }

        let format = String(
            localized: "codexAppServer.toolGroup.ranCommandLine",
            defaultValue: "Ran %@"
        )
        return Self(
            kind: .command,
            label: toolLabel(name: "shell", fallback: fallbackTitle),
            summaryLine: String(format: format, locale: Locale.current, trimmed),
            command: trimmed,
            output: "",
            exitCode: nil
        )
    }

    private static func editRuns(from body: String, fallbackTitle: String) -> [Self] {
        let patchRuns = patchFileChanges(from: body).map { change in
            let format = String(
                localized: "codexAppServer.toolGroup.editedLine",
                defaultValue: "Edited %@ +%ld -%ld"
            )
            return Self(
                kind: .edit,
                label: toolLabel(name: "apply_patch", fallback: fallbackTitle),
                summaryLine: String(
                    format: format,
                    locale: Locale.current,
                    displayPath(change.path),
                    change.added,
                    change.removed
                ),
                command: body,
                output: "",
                exitCode: nil
            )
        }
        if !patchRuns.isEmpty {
            return patchRuns
        }

        let paths = jsonPaths(from: body)
        if !paths.isEmpty {
            return paths.map { path in
                let format = String(
                    localized: "codexAppServer.toolGroup.editedLine",
                    defaultValue: "Edited %@ +%ld -%ld"
                )
                return Self(
                    kind: .edit,
                    label: toolLabel(name: "apply_patch", fallback: fallbackTitle),
                    summaryLine: String(format: format, locale: Locale.current, displayPath(path), 0, 0),
                    command: body,
                    output: "",
                    exitCode: nil
                )
            }
        }

        return [
            Self(
                kind: .edit,
                label: toolLabel(name: "apply_patch", fallback: fallbackTitle),
                summaryLine: String(localized: "codexAppServer.toolGroup.editedFiles", defaultValue: "Edited files"),
                command: body,
                output: "",
                exitCode: nil
            ),
        ]
    }

    private static func webSearchRuns(from body: String, fallbackTitle: String) -> [Self] {
        guard let object = jsonDictionary(from: body) else {
            return [genericToolRun(name: "web.run", body: body, fallbackTitle: fallbackTitle)]
        }
        let queries = queryStrings(from: object, key: "search_query")
            + queryStrings(from: object, key: "image_query")
        guard !queries.isEmpty else {
            return [genericToolRun(name: "web.run", body: body, fallbackTitle: fallbackTitle)]
        }
        return queries.map { query in
            Self(
                kind: .webSearch,
                label: toolLabel(name: "web.run", fallback: fallbackTitle),
                summaryLine: query,
                command: "",
                output: "",
                exitCode: nil
            )
        }
    }

    private static func toolSearchRun(from body: String, fallbackTitle: String) -> Self {
        let query = jsonDictionary(from: body).flatMap { stringValue(named: "query", in: $0) }
            ?? body.trimmingCharacters(in: .whitespacesAndNewlines)
        let format = String(
            localized: "codexAppServer.toolGroup.searchedFor",
            defaultValue: "Searched for %@"
        )
        return Self(
            kind: .search,
            label: toolLabel(name: "tool_search_tool", fallback: fallbackTitle),
            summaryLine: String(format: format, locale: Locale.current, query),
            command: "",
            output: "",
            exitCode: nil
        )
    }

    private static func parallelToolRuns(from body: String, fallbackTitle: String) -> [Self] {
        guard let object = jsonDictionary(from: body),
              let toolUses = object["tool_uses"] as? [[String: Any]] else {
            return []
        }
        return toolUses.flatMap { toolUse -> [Self] in
            let name = stringValue(named: "recipient_name", in: toolUse)
                ?? stringValue(named: "name", in: toolUse)
            let parameters: Any = toolUse["parameters"] ?? toolUse["input"] ?? [String: Any]()
            let body: String
            if let value = parameters as? String {
                body = value
            } else if let object = parameters as? [String: Any] {
                if let command = stringValue(named: "cmd", in: object)
                    ?? stringValue(named: "command", in: object) {
                    body = command
                } else {
                    body = prettyJSON(object)
                }
            } else {
                body = String(describing: parameters)
            }
            return runsForToolCall(name: name, body: body, fallbackTitle: name ?? fallbackTitle)
        }
    }

    private static func genericToolRun(name: String?, body: String, fallbackTitle: String) -> Self {
        let label = toolLabel(name: name, fallback: fallbackTitle)
        let format = String(
            localized: "codexAppServer.toolGroup.usedTool",
            defaultValue: "Used %@"
        )
        return Self(
            kind: .tool,
            label: label,
            summaryLine: String(format: format, locale: Locale.current, label),
            command: body,
            output: "",
            exitCode: nil
        )
    }

    private static var outputLabel: String {
        String(localized: "codexAppServer.toolGroup.output", defaultValue: "Output")
    }

    private static func toolLabel(name: String?, fallback: String) -> String {
        let rawCandidate: String
        if let name, !name.isEmpty {
            rawCandidate = name
        } else {
            rawCandidate = fallback
        }
        let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate == "exec_command" || candidate == "shell" || candidate == "Command" {
            return String(localized: "codexAppServer.toolGroup.shell", defaultValue: "Shell")
        }
        return candidate.isEmpty ? outputLabel : candidate
    }

    private static func normalizedToolName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func count(_ kind: CodexTrajectoryToolRunKind, in runs: [Self]) -> Int {
        runs.filter { $0.kind == kind }.count
    }

    private static func editCountTitle(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "codexAppServer.toolGroup.editedFile.one", defaultValue: "Edited 1 file")
        }
        let format = String(
            localized: "codexAppServer.toolGroup.editedFile.many",
            defaultValue: "Edited %1$ld files"
        )
        return String(format: format, locale: Locale.current, count)
    }

    private static func fileCountTitle(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "codexAppServer.toolGroup.file.one", defaultValue: "1 file")
        }
        let format = String(
            localized: "codexAppServer.toolGroup.file.many",
            defaultValue: "%1$ld files"
        )
        return String(format: format, locale: Locale.current, count)
    }

    private static func searchCountTitle(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "codexAppServer.toolGroup.search.one", defaultValue: "1 search")
        }
        let format = String(
            localized: "codexAppServer.toolGroup.search.many",
            defaultValue: "%1$ld searches"
        )
        return String(format: format, locale: Locale.current, count)
    }

    private static func listCountTitle(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "codexAppServer.toolGroup.list.one", defaultValue: "1 list")
        }
        let format = String(
            localized: "codexAppServer.toolGroup.list.many",
            defaultValue: "%1$ld lists"
        )
        return String(format: format, locale: Locale.current, count)
    }

    private static func commandCountTitle(_ count: Int, isContinuation: Bool) -> String {
        if count == 1 {
            return isContinuation
                ? String(localized: "codexAppServer.toolGroup.ranCommand.one.continuation", defaultValue: "ran command")
                : String(localized: "codexAppServer.toolGroup.ranCommand.one", defaultValue: "Ran command")
        }
        let format = isContinuation
            ? String(
                localized: "codexAppServer.toolGroup.ranCommand.many.continuation",
                defaultValue: "ran %1$ld commands"
            )
            : String(localized: "codexAppServer.toolGroup.ranCommand.many", defaultValue: "Ran %1$ld commands")
        return String(format: format, locale: Locale.current, count)
    }

    private static func webSearchCountTitle(_ count: Int, isContinuation: Bool) -> String {
        if count == 1 {
            return isContinuation
                ? String(localized: "codexAppServer.toolGroup.searchedWeb.one.continuation", defaultValue: "searched web")
                : String(localized: "codexAppServer.toolGroup.searchedWeb.one.start", defaultValue: "Searched web")
        }
        let format = isContinuation
            ? String(
                localized: "codexAppServer.toolGroup.searchedWeb.many.continuation",
                defaultValue: "searched web %1$ld times"
            )
            : String(
                localized: "codexAppServer.toolGroup.searchedWeb.many.start",
                defaultValue: "Searched web %1$ld times"
            )
        return String(format: format, locale: Locale.current, count)
    }

    private static func toolCountTitle(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "codexAppServer.toolGroup.ranTool.one", defaultValue: "Ran tool")
        }
        let format = String(
            localized: "codexAppServer.toolGroup.ranTool.many",
            defaultValue: "Ran %1$ld tools"
        )
        return String(format: format, locale: Locale.current, count)
    }

    private static func isReadCommand(executable: String) -> Bool {
        ["cat", "sed", "nl", "head", "tail"].contains(executable)
    }

    private static func isSearchCommand(executable: String) -> Bool {
        ["rg", "grep", "ag"].contains(executable)
    }

    private static func isListCommand(executable: String, tokens: [String]) -> Bool {
        if ["ls", "find", "fd"].contains(executable) {
            return true
        }
        if executable == "rg", tokens.contains("--files") {
            return true
        }
        if executable == "git", tokens.dropFirst().first == "ls-files" {
            return true
        }
        return false
    }

    private static func shellTokens(from command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current.removeAll(keepingCapacity: true)
        }

        for character in command {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                flush()
            } else {
                current.append(character)
            }
        }
        flush()
        return tokens
    }

    private static func fileArgument(from tokens: [String]) -> String? {
        for token in tokens.dropFirst().reversed() {
            guard !token.hasPrefix("-"),
                  token != "|",
                  token != ">",
                  token != "2>",
                  token != "1>" else {
                continue
            }
            return token
        }
        return nil
    }

    private static func searchArguments(from tokens: [String]) -> (query: String, path: String?)? {
        guard tokens.count > 1 else { return nil }
        var arguments: [String] = []
        var shouldSkipNext = false
        let optionsWithValues: Set<String> = [
            "-e", "-f", "-g", "--glob", "--type", "-t", "--type-not", "-T", "--context", "-C",
            "--after-context", "-A", "--before-context", "-B",
        ]

        for token in tokens.dropFirst() {
            if shouldSkipNext {
                shouldSkipNext = false
                continue
            }
            if optionsWithValues.contains(token) {
                shouldSkipNext = true
                continue
            }
            if token.hasPrefix("-") {
                continue
            }
            arguments.append(token)
        }
        guard let query = arguments.first else { return nil }
        return (query, arguments.dropFirst().last)
    }

    private struct PatchFileChange {
        var path: String
        var added: Int
        var removed: Int
    }

    private static func patchFileChanges(from body: String) -> [PatchFileChange] {
        var changes: [PatchFileChange] = []
        var current: PatchFileChange?

        func finishCurrent() {
            if let current {
                changes.append(current)
            }
            current = nil
        }

        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let path = patchPath(from: line) {
                finishCurrent()
                current = PatchFileChange(path: path, added: 0, removed: 0)
                continue
            }
            guard current != nil else { continue }
            if line.hasPrefix("+"), !line.hasPrefix("+++") {
                current?.added += 1
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                current?.removed += 1
            }
        }
        finishCurrent()
        return changes
    }

    private static func patchPath(from line: String) -> String? {
        let prefixes = [
            "*** Update File: ",
            "*** Add File: ",
            "*** Delete File: ",
        ]
        for prefix in prefixes where line.hasPrefix(prefix) {
            let path = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }
        return nil
    }

    private static func jsonPaths(from body: String) -> [String] {
        guard let value = jsonValue(from: body) else { return [] }
        var paths: [String] = []

        func collect(_ value: Any) {
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    if ["path", "file", "filePath", "filename"].contains(key),
                       let string = child as? String,
                       !string.isEmpty {
                        paths.append(string)
                    }
                    collect(child)
                }
            } else if let array = value as? [Any] {
                array.forEach(collect)
            }
        }

        collect(value)
        return Array(Set(paths)).sorted()
    }

    private static func queryStrings(from object: [String: Any], key: String) -> [String] {
        guard let queries = object[key] as? [[String: Any]] else { return [] }
        return queries.compactMap { query in
            stringValue(named: "q", in: query)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }

    private static func displayPath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("./") {
            path.removeFirst(2)
        }
        guard path.hasPrefix("/") else { return path }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func jsonDictionary(from text: String) -> [String: Any]? {
        jsonValue(from: text) as? [String: Any]
    }

    private static func jsonValue(from text: String) -> Any? {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func stringValue(named key: String, in object: [String: Any]) -> String? {
        if let value = object[key] as? String {
            return value
        }
        if let value = object[key] as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func prettyJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}

private struct CodexTrajectoryToolOutput {
    var text: String
    var exitCode: Int?

    static func normalize(_ body: String) -> Self {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Self(text: trimmed, exitCode: nil)
        }

        let stdout = stringValue(named: "stdout", in: object)
            ?? stringValue(named: "output", in: object)
            ?? stringValue(named: "text", in: object)
        let stderr = stringValue(named: "stderr", in: object)
        let parts = [stdout, stderr]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let displayText = parts.isEmpty ? prettyJSON(object) : parts.joined(separator: "\n")
        return Self(
            text: displayText,
            exitCode: intValue(named: "exit_code", in: object)
                ?? intValue(named: "exitCode", in: object)
                ?? intValue(named: "status", in: object)
        )
    }

    private static func stringValue(named key: String, in object: [String: Any]) -> String? {
        if let value = object[key] as? String {
            return value
        }
        if let value = object[key] as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func intValue(named key: String, in object: [String: Any]) -> Int? {
        if let value = object[key] as? Int {
            return value
        }
        if let value = object[key] as? NSNumber {
            return value.intValue
        }
        if let value = object[key] as? String {
            return Int(value)
        }
        return nil
    }

    private static func prettyJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}

private extension CodexAppServerTranscriptItem {
    var isToolTranscriptItem: Bool {
        switch presentation {
        case .toolCall, .toolOutput, .commandOutput:
            return true
        case .plain, .compaction:
            return false
        }
    }

    var trajectoryKind: CodexTrajectoryBlockKind {
        switch role {
        case .user:
            return .userText
        case .assistant:
            return .assistantText
        case .event:
            return .systemEvent
        case .stderr:
            return .stderr
        case .error:
            return .stderr
        }
    }
}

final class CodexTrajectoryTranscriptScrollView: NSScrollView {
    private let trajectoryView = CodexTrajectoryTranscriptDocumentView()
    private var entries: [CodexTrajectoryTranscriptDisplayEntry] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        documentView = trajectoryView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        reloadPreservingScroll(stickToBottom: isScrolledNearBottom)
    }

    fileprivate func update(entries: [CodexTrajectoryTranscriptDisplayEntry]) {
        let shouldStickToBottom = isScrolledNearBottom || entries.count > self.entries.count
        self.entries = entries
        reloadPreservingScroll(stickToBottom: shouldStickToBottom)
    }

    private var documentWidth: CGFloat {
        max(1, contentView.bounds.width)
    }

    private var isScrolledNearBottom: Bool {
        let visibleMaxY = contentView.bounds.maxY
        let documentHeight = trajectoryView.frame.height
        return documentHeight - visibleMaxY < 48
    }

    private func reloadPreservingScroll(stickToBottom: Bool) {
        guard documentWidth > 1 else { return }
        trajectoryView.update(entries: entries, width: documentWidth)
        if stickToBottom {
            scrollToBottom()
        }
    }

    private func scrollToBottom() {
        let maxY = max(0, trajectoryView.frame.height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: 0, y: maxY))
        reflectScrolledClipView(contentView)
    }
}

private final class CodexTrajectoryTranscriptDocumentView: NSView, NSUserInterfaceValidations {
    private enum PageChrome {
        case plain
        case accordionHeader
        case accordionContent
        case compaction
    }

    private struct PageEntry {
        var entry: CodexTrajectoryTranscriptDisplayEntry
        var page: CodexTrajectoryLayoutPage?
        var chrome: PageChrome
        var topSpacing: CGFloat
        var bottomSpacing: CGFloat
        var fullContentHeight: CGFloat
    }

    private struct LayoutCacheKey: Hashable {
        var block: CodexTrajectoryBlock
        var width: Int
        var themeIdentifier: String
    }

    private struct CachedLayout {
        var block: CodexTrajectoryBlock
        var layout: CodexTrajectoryBlockLayout
    }

    private struct ExpansionAnimation {
        var from: CGFloat
        var to: CGFloat
        var startTime: TimeInterval
        var duration: TimeInterval
    }

    private struct TextSelectionEndpoint: Equatable {
        var blockID: String
        var utf16Offset: Int
    }

    private struct TextSelection {
        var anchor: TextSelectionEndpoint
        var focus: TextSelectionEndpoint

        var isEmpty: Bool {
            anchor == focus
        }
    }

    private struct NormalizedTextSelection {
        var lower: TextSelectionEndpoint
        var upper: TextSelectionEndpoint
        var lowerBlockIndex: Int
        var upperBlockIndex: Int
    }

    private let layoutEngine = CodexTrajectoryLayoutEngine()
    private let renderer = CodexTrajectoryRenderer()
    private var entries: [CodexTrajectoryTranscriptDisplayEntry] = []
    private var pageEntries: [PageEntry] = []
    private var heightIndex = CodexTrajectoryHeightIndex()
    private var cachedLayouts: [LayoutCacheKey: CachedLayout] = [:]
    private var expandedAccordionIDs: Set<String> = []
    private var expansionAnimations: [String: ExpansionAnimation] = [:]
    private var textSelection: TextSelection?
    private var isSelectingText = false
    private var animationTimer: Timer?
    private var documentWidth: CGFloat = 1
    private let horizontalInset: CGFloat = 14
    private let rowSpacing: CGFloat = 10
    private let accordionHeaderHeight: CGFloat = 40
    private let compactionHeight: CGFloat = 58
    private let accordionContentIndent: CGFloat = 24
    private let accordionContentTopSpacing: CGFloat = 8
    private let accordionAnimationDuration: TimeInterval = 0.18

    override var isFlipped: Bool {
        true
    }

    override var wantsUpdateLayer: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    deinit {
        animationTimer?.invalidate()
    }

    func update(entries: [CodexTrajectoryTranscriptDisplayEntry], width: CGFloat) {
        let normalizedWidth = max(1, width)
        let activeAccordionIDs = Set(entries.filter(\.isAccordion).map(\.id))
        expandedAccordionIDs.formIntersection(activeAccordionIDs)
        expansionAnimations = expansionAnimations.filter { activeAccordionIDs.contains($0.key) }

        guard entries != self.entries || abs(normalizedWidth - documentWidth) > 0.5 else { return }
        self.entries = entries
        documentWidth = normalizedWidth
        rebuildLayout()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        backgroundColor.setFill()
        NSBezierPath(rect: dirtyRect).fill()

        let range = heightIndex.indexRange(
            intersectingOffset: dirtyRect.minY,
            length: dirtyRect.height,
            overscan: 480
        )
        guard !range.isEmpty else { return }

        let theme = Self.theme(for: effectiveAppearance)
        for index in range {
            let y = heightIndex.prefixSum(upTo: index)
            let pageEntry = pageEntries[index]
            switch pageEntry.chrome {
            case .plain:
                guard let page = pageEntry.page else { continue }
                let pageRect = CGRect(
                    x: horizontalInset,
                    y: y + rowSpacing / 2,
                    width: max(1, documentWidth - horizontalInset * 2),
                    height: page.measuredSize.height
                )
                drawBackground(for: pageEntry.entry.block.kind, in: pageRect, context: context)
                drawSelectionIfNeeded(
                    pageEntry: pageEntry,
                    pageEntryIndex: index,
                    page: page,
                    pageRect: pageRect,
                    theme: theme,
                    context: context
                )
                renderer.draw(
                    block: pageEntry.entry.block,
                    page: page,
                    in: context,
                    rect: pageRect,
                    theme: theme,
                    coordinates: .yDown
                )
            case .accordionHeader:
                let rect = accordionHeaderRect(at: y)
                drawAccordionHeader(entry: pageEntry.entry, in: rect, context: context)
            case .accordionContent:
                guard let page = pageEntry.page else { continue }
                let allocatedHeight = heightIndex.height(at: index) ?? 0
                guard allocatedHeight > 0.5 else { continue }
                let progress = max(0.01, expansionProgress(for: pageEntry.entry.id))
                let contentX = horizontalInset + accordionContentIndent
                let contentWidth = max(1, documentWidth - horizontalInset * 2 - accordionContentIndent)
                let pageRect = CGRect(
                    x: contentX,
                    y: y + pageEntry.topSpacing * progress,
                    width: contentWidth,
                    height: page.measuredSize.height
                )
                let clipRect = CGRect(
                    x: contentX,
                    y: y,
                    width: contentWidth,
                    height: allocatedHeight
                )

                context.saveGState()
                context.clip(to: clipRect)
                context.setAlpha(min(1, progress * 1.35))
                drawAccordionContentBackground(in: pageRect, context: context)
                drawSelectionIfNeeded(
                    pageEntry: pageEntry,
                    pageEntryIndex: index,
                    page: page,
                    pageRect: pageRect,
                    theme: theme,
                    context: context
                )
                renderer.draw(
                    block: pageEntry.entry.block,
                    page: page,
                    in: context,
                    rect: pageRect,
                    theme: theme,
                    coordinates: .yDown
                )
                context.restoreGState()
            case .compaction:
                drawCompaction(entry: pageEntry.entry, at: y, context: context)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let endpoint = textEndpoint(at: point, allowNearest: false) {
            window?.makeFirstResponder(self)
            textSelection = TextSelection(anchor: endpoint, focus: endpoint)
            isSelectingText = true
            needsDisplay = true
            return
        }

        guard let index = heightIndex.index(containingOffset: point.y),
              pageEntries.indices.contains(index) else {
            clearTextSelection()
            super.mouseDown(with: event)
            return
        }

        let pageEntry = pageEntries[index]
        guard case .accordionHeader = pageEntry.chrome else {
            super.mouseDown(with: event)
            return
        }

        let y = heightIndex.prefixSum(upTo: index)
        guard accordionHeaderRect(at: y).contains(point) else {
            super.mouseDown(with: event)
            return
        }

        toggleAccordion(id: pageEntry.entry.id)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelectingText, let selection = textSelection else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let endpoint = textEndpoint(at: point, allowNearest: true),
           endpoint != selection.focus {
            textSelection = TextSelection(anchor: selection.anchor, focus: endpoint)
            needsDisplay = true
        }
        _ = autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isSelectingText {
            isSelectingText = false
            if textSelection?.isEmpty == true {
                textSelection = nil
                needsDisplay = true
            }
            return
        }
        super.mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectAll(nil)
            return
        }
        super.keyDown(with: event)
    }

    @objc func copy(_ sender: Any?) {
        guard let text = selectedTranscriptText, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        guard let first = firstTextEndpoint(), let last = lastTextEndpoint(), first != last else { return }
        window?.makeFirstResponder(self)
        textSelection = TextSelection(anchor: first, focus: last)
        needsDisplay = true
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return selectedTranscriptText?.isEmpty == false
        }
        if item.action == #selector(selectAll(_:)) {
            return firstTextEndpoint() != nil
        }
        return true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let theme = Self.theme(for: effectiveAppearance)
        let visibleRange = heightIndex.indexRange(
            intersectingOffset: visibleRect.minY,
            length: visibleRect.height,
            overscan: 80
        )
        for index in visibleRange {
            guard pageEntries.indices.contains(index) else {
                continue
            }
            let y = heightIndex.prefixSum(upTo: index)
            let pageEntry = pageEntries[index]
            switch pageEntry.chrome {
            case .accordionHeader:
                addCursorRect(accordionHeaderRect(at: y), cursor: .pointingHand)
            case .plain, .accordionContent:
                if let rect = selectablePageRect(
                    for: pageEntry,
                    at: index,
                    y: y,
                    theme: theme
                ) {
                    addCursorRect(rect, cursor: .iBeam)
                }
            case .compaction:
                continue
            }
        }
    }

    private var backgroundColor: NSColor {
        .textBackgroundColor
    }

    private func clearTextSelection() {
        guard textSelection != nil else { return }
        textSelection = nil
        isSelectingText = false
        needsDisplay = true
    }

    private func clampSelectionToCurrentText() {
        guard let selection = textSelection else { return }
        guard let anchor = clampedEndpoint(selection.anchor),
              let focus = clampedEndpoint(selection.focus) else {
            textSelection = nil
            isSelectingText = false
            return
        }
        textSelection = TextSelection(anchor: anchor, focus: focus)
    }

    private func clampedEndpoint(_ endpoint: TextSelectionEndpoint) -> TextSelectionEndpoint? {
        guard let pageEntry = pageEntries.first(where: { pageEntry in
            pageEntry.page != nil && pageEntry.entry.block.id == endpoint.blockID
        }) else {
            return nil
        }
        let length = Self.displayText(for: pageEntry.entry.block).utf16.count
        return TextSelectionEndpoint(
            blockID: endpoint.blockID,
            utf16Offset: min(max(endpoint.utf16Offset, 0), length)
        )
    }

    private func normalizedSelection(_ selection: TextSelection) -> NormalizedTextSelection? {
        guard let anchorBounds = pageEntryBounds(forBlockID: selection.anchor.blockID),
              let focusBounds = pageEntryBounds(forBlockID: selection.focus.blockID) else {
            return nil
        }

        let anchorIsLower: Bool
        if selection.anchor.blockID == selection.focus.blockID {
            anchorIsLower = selection.anchor.utf16Offset <= selection.focus.utf16Offset
        } else {
            anchorIsLower = anchorBounds.first <= focusBounds.first
        }

        if anchorIsLower {
            return NormalizedTextSelection(
                lower: selection.anchor,
                upper: selection.focus,
                lowerBlockIndex: anchorBounds.first,
                upperBlockIndex: focusBounds.last
            )
        }
        return NormalizedTextSelection(
            lower: selection.focus,
            upper: selection.anchor,
            lowerBlockIndex: focusBounds.first,
            upperBlockIndex: anchorBounds.last
        )
    }

    private func pageEntryBounds(forBlockID blockID: String) -> (first: Int, last: Int)? {
        var first: Int?
        var last: Int?
        for (index, pageEntry) in pageEntries.enumerated() {
            guard pageEntry.page != nil, pageEntry.entry.block.id == blockID else { continue }
            if first == nil {
                first = index
            }
            last = index
        }
        guard let first, let last else { return nil }
        return (first, last)
    }

    private func rebuildLayout() {
        let theme = Self.theme(for: effectiveAppearance)
        let layoutWidth = max(1, documentWidth - horizontalInset * 2)
        pageEntries.removeAll(keepingCapacity: true)
        var heights: [CGFloat] = []

        for entry in entries {
            if entry.isCompaction {
                pageEntries.append(
                    PageEntry(
                        entry: entry,
                        page: nil,
                        chrome: .compaction,
                        topSpacing: 0,
                        bottomSpacing: rowSpacing,
                        fullContentHeight: compactionHeight
                    )
                )
                heights.append(compactionHeight)
            } else if entry.isAccordion {
                let progress = expansionProgress(for: entry.id)
                pageEntries.append(
                    PageEntry(
                        entry: entry,
                        page: nil,
                        chrome: .accordionHeader,
                        topSpacing: 0,
                        bottomSpacing: progress > 0 ? 0 : rowSpacing,
                        fullContentHeight: accordionHeaderHeight
                    )
                )
                heights.append(accordionHeaderHeight + (progress > 0 ? 0 : rowSpacing))

                if progress > 0 {
                    let contentWidth = max(1, layoutWidth - accordionContentIndent)
                    let layout = layout(for: entry.block, width: contentWidth, theme: theme)
                    for page in layout.pages {
                        let isFirstPage = page.pageIndex == 0
                        let isLastPage = page.pageIndex == layout.pages.count - 1
                        let topSpacing = isFirstPage ? accordionContentTopSpacing : 0
                        let bottomSpacing = isLastPage ? rowSpacing : 0
                        let fullHeight = topSpacing + page.measuredSize.height + bottomSpacing
                        pageEntries.append(
                            PageEntry(
                                entry: entry,
                                page: page,
                                chrome: .accordionContent,
                                topSpacing: topSpacing,
                                bottomSpacing: bottomSpacing,
                                fullContentHeight: fullHeight
                            )
                        )
                        heights.append(max(0, fullHeight * progress))
                    }
                }
            } else {
                let layout = layout(for: entry.block, width: layoutWidth, theme: theme)
                for page in layout.pages {
                    pageEntries.append(
                        PageEntry(
                            entry: entry,
                            page: page,
                            chrome: .plain,
                            topSpacing: 0,
                            bottomSpacing: rowSpacing,
                            fullContentHeight: page.measuredSize.height
                        )
                    )
                    heights.append(page.measuredSize.height + rowSpacing)
                }
            }
        }

        if cachedLayouts.count > max(256, entries.count * 3) {
            pruneLayoutCache()
        }

        heightIndex.replaceAll(with: heights)
        setFrameSize(NSSize(width: documentWidth, height: max(1, heightIndex.totalHeight)))
        clampSelectionToCurrentText()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func layout(
        for block: CodexTrajectoryBlock,
        width: CGFloat,
        theme: CodexTrajectoryTheme
    ) -> CodexTrajectoryBlockLayout {
        let cacheKey = LayoutCacheKey(
            block: block,
            width: Int(width.rounded()),
            themeIdentifier: theme.identifier
        )
        if let cached = cachedLayouts[cacheKey] {
            return cached.layout
        }

        let layout = layoutEngine.layout(
            block: block,
            configuration: CodexTrajectoryLayoutConfiguration(width: width),
            theme: theme
        )
        cachedLayouts[cacheKey] = CachedLayout(block: block, layout: layout)
        return layout
    }

    private func selectablePageRect(
        for pageEntry: PageEntry,
        at index: Int,
        y: CGFloat,
        theme: CodexTrajectoryTheme
    ) -> CGRect? {
        guard let page = pageEntry.page else { return nil }
        switch pageEntry.chrome {
        case .plain:
            return CGRect(
                x: horizontalInset,
                y: y + rowSpacing / 2,
                width: max(1, documentWidth - horizontalInset * 2),
                height: page.measuredSize.height
            )
        case .accordionContent:
            let allocatedHeight = heightIndex.height(at: index) ?? 0
            guard allocatedHeight > 0.5 else { return nil }
            let progress = max(0.01, expansionProgress(for: pageEntry.entry.id))
            return CGRect(
                x: horizontalInset + accordionContentIndent,
                y: y + pageEntry.topSpacing * progress,
                width: max(1, documentWidth - horizontalInset * 2 - accordionContentIndent),
                height: page.measuredSize.height
            )
        case .accordionHeader, .compaction:
            return nil
        }
    }

    private func textEndpoint(at point: CGPoint, allowNearest: Bool) -> TextSelectionEndpoint? {
        let theme = Self.theme(for: effectiveAppearance)
        let lookupRange = heightIndex.indexRange(
            intersectingOffset: visibleRect.minY,
            length: visibleRect.height,
            overscan: allowNearest ? 2_000 : 80
        )
        var nearest: (distance: CGFloat, endpoint: TextSelectionEndpoint)?

        for index in lookupRange {
            guard pageEntries.indices.contains(index) else { continue }
            let pageEntry = pageEntries[index]
            guard let page = pageEntry.page else { continue }
            let y = heightIndex.prefixSum(upTo: index)
            guard let pageRect = selectablePageRect(for: pageEntry, at: index, y: y, theme: theme) else {
                continue
            }

            if pageRect.contains(point),
               let endpoint = textEndpoint(
                   in: pageEntry,
                   pageEntryIndex: index,
                   page: page,
                   pageRect: pageRect,
                   point: point,
                   theme: theme
               ) {
                return endpoint
            }

            guard allowNearest else { continue }
            let dy: CGFloat
            if point.y < pageRect.minY {
                dy = pageRect.minY - point.y
            } else if point.y > pageRect.maxY {
                dy = point.y - pageRect.maxY
            } else {
                dy = 0
            }
            let clampedPoint = CGPoint(
                x: min(max(point.x, pageRect.minX), pageRect.maxX),
                y: min(max(point.y, pageRect.minY), pageRect.maxY)
            )
            if let endpoint = textEndpoint(
                in: pageEntry,
                pageEntryIndex: index,
                page: page,
                pageRect: pageRect,
                point: clampedPoint,
                theme: theme
            ),
                nearest == nil || dy < nearest!.distance {
                nearest = (dy, endpoint)
            }
        }

        return nearest?.endpoint
    }

    private func textEndpoint(
        in pageEntry: PageEntry,
        pageEntryIndex: Int,
        page: CodexTrajectoryLayoutPage,
        pageRect: CGRect,
        point: CGPoint,
        theme: CodexTrajectoryTheme
    ) -> TextSelectionEndpoint? {
        let pageInfo = Self.pageTextInfo(for: pageEntry.entry.block, page: page)
        let pageText = pageInfo.text
        let textLength = (pageText as NSString).length
        guard textLength > 0 else {
            return TextSelectionEndpoint(
                blockID: pageEntry.entry.block.id,
                utf16Offset: pageInfo.globalUTF16Range.lowerBound
            )
        }

        let frame = textFrame(
            text: pageText,
            kind: pageEntry.entry.block.kind,
            pageRect: pageRect,
            theme: theme
        )
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        guard !lines.isEmpty else {
            return TextSelectionEndpoint(
                blockID: pageEntry.entry.block.id,
                utf16Offset: pageInfo.globalUTF16Range.lowerBound
            )
        }
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        let localPoint = CGPoint(x: point.x - pageRect.minX, y: pageRect.maxY - point.y)
        var bestLineIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (lineIndex, line) in lines.enumerated() {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let origin = origins[lineIndex]
            let minY = origin.y - descent - leading / 2
            let maxY = origin.y + ascent + leading / 2
            if localPoint.y >= minY, localPoint.y <= maxY {
                bestLineIndex = lineIndex
                break
            }
            let distance = localPoint.y < minY ? minY - localPoint.y : localPoint.y - maxY
            if distance < bestDistance {
                bestDistance = distance
                bestLineIndex = lineIndex
            }
        }

        let line = lines[bestLineIndex]
        let origin = origins[bestLineIndex]
        let range = CTLineGetStringRange(line)
        let lower = max(0, range.location)
        let upper = min(textLength, lower + max(0, range.length))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let linePoint = CGPoint(
            x: min(max(localPoint.x - origin.x, 0), max(0, width)),
            y: localPoint.y - origin.y
        )
        var offset = CTLineGetStringIndexForPosition(line, linePoint)
        if offset == kCFNotFound {
            offset = linePoint.x <= 0 ? lower : upper
        }
        offset = min(max(offset, lower), upper)
        return TextSelectionEndpoint(
            blockID: pageEntry.entry.block.id,
            utf16Offset: pageInfo.globalUTF16Range.lowerBound + offset
        )
    }

    private func drawSelectionIfNeeded(
        pageEntry: PageEntry,
        pageEntryIndex: Int,
        page: CodexTrajectoryLayoutPage,
        pageRect: CGRect,
        theme: CodexTrajectoryTheme,
        context: CGContext
    ) {
        guard let selection = textSelection, !selection.isEmpty else { return }
        let pageText = Self.pageText(for: pageEntry.entry.block, page: page)
        guard let range = selectedUTF16Range(
            forPageEntryIndex: pageEntryIndex,
            pageEntry: pageEntry,
            page: page,
            pageText: pageText,
            selection: selection
        ) else {
            return
        }

        let frame = textFrame(
            text: pageText,
            kind: pageEntry.entry.block.kind,
            pageRect: pageRect,
            theme: theme
        )
        let rects = selectionRects(
            in: frame,
            selectedRange: range,
            pageRect: pageRect
        )
        guard !rects.isEmpty else { return }

        let fill = Self.color(.selectedTextBackgroundColor, appearance: effectiveAppearance)
            .withAlphaComponent(0.62)
        context.saveGState()
        context.setFillColor(fill.cgColor)
        for rect in rects {
            context.fill(rect)
        }
        context.restoreGState()
    }

    private func selectedUTF16Range(
        forPageEntryIndex pageEntryIndex: Int,
        pageEntry: PageEntry,
        page: CodexTrajectoryLayoutPage,
        pageText: String,
        selection: TextSelection
    ) -> Range<Int>? {
        guard let normalized = normalizedSelection(selection) else { return nil }
        let pageInfo = Self.pageTextInfo(for: pageEntry.entry.block, page: page)
        let pageRange = pageInfo.globalUTF16Range
        let textLength = (pageText as NSString).length
        guard textLength > 0 else { return nil }

        let lowerGlobal: Int
        let upperGlobal: Int
        if normalized.lower.blockID == normalized.upper.blockID {
            guard pageEntry.entry.block.id == normalized.lower.blockID else { return nil }
            lowerGlobal = max(normalized.lower.utf16Offset, pageRange.lowerBound)
            upperGlobal = min(normalized.upper.utf16Offset, pageRange.upperBound)
        } else if pageEntry.entry.block.id == normalized.lower.blockID {
            lowerGlobal = max(normalized.lower.utf16Offset, pageRange.lowerBound)
            upperGlobal = pageRange.upperBound
        } else if pageEntry.entry.block.id == normalized.upper.blockID {
            lowerGlobal = pageRange.lowerBound
            upperGlobal = min(normalized.upper.utf16Offset, pageRange.upperBound)
        } else if pageEntryIndex > normalized.lowerBlockIndex,
                  pageEntryIndex < normalized.upperBlockIndex {
            lowerGlobal = pageRange.lowerBound
            upperGlobal = pageRange.upperBound
        } else {
            return nil
        }

        let lower = min(max(lowerGlobal - pageRange.lowerBound, 0), textLength)
        let upper = min(max(upperGlobal - pageRange.lowerBound, 0), textLength)
        return upper > lower ? lower..<upper : nil
    }

    private func selectionRects(
        in frame: CTFrame,
        selectedRange: Range<Int>,
        pageRect: CGRect
    ) -> [CGRect] {
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        guard !lines.isEmpty else { return [] }
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        var rects: [CGRect] = []
        for (lineIndex, line) in lines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            let lineLower = max(0, lineRange.location)
            let lineUpper = lineLower + max(0, lineRange.length)
            let lower = max(selectedRange.lowerBound, lineLower)
            let upper = min(selectedRange.upperBound, lineUpper)
            guard upper > lower else { continue }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let origin = origins[lineIndex]
            let startX = CTLineGetOffsetForStringIndex(line, lower, nil)
            let endX = CTLineGetOffsetForStringIndex(line, upper, nil)
            let width = max(2, abs(endX - startX))
            let yUpTop = origin.y + ascent + leading / 2
            let yUpBottom = origin.y - descent - leading / 2
            rects.append(
                CGRect(
                    x: pageRect.minX + origin.x + min(startX, endX),
                    y: pageRect.maxY - yUpTop,
                    width: width,
                    height: max(1, yUpTop - yUpBottom)
                )
            )
        }
        return rects
    }

    private func textFrame(
        text: String,
        kind: CodexTrajectoryBlockKind,
        pageRect: CGRect,
        theme: CodexTrajectoryTheme
    ) -> CTFrame {
        let style = theme.style(for: kind)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: style.font,
            kCTForegroundColorAttributeName: style.foregroundColor,
        ]
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary)!
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let insets = theme.contentInsets
        let localTextRect = CGRect(
            x: insets.left,
            y: insets.bottom,
            width: max(0, pageRect.width - insets.left - insets.right),
            height: max(0, pageRect.height - insets.top - insets.bottom)
        )
        let path = CGMutablePath()
        path.addRect(localTextRect)
        return CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )
    }

    private var selectedTranscriptText: String? {
        guard let selection = textSelection, !selection.isEmpty else { return nil }
        guard let normalized = normalizedSelection(selection) else { return nil }

        var chunks: [String] = []
        for index in normalized.lowerBlockIndex...normalized.upperBlockIndex {
            guard pageEntries.indices.contains(index),
                  let page = pageEntries[index].page else {
                continue
            }
            let pageEntry = pageEntries[index]
            switch pageEntry.chrome {
            case .plain, .accordionContent:
                break
            case .accordionHeader, .compaction:
                continue
            }
            let pageText = Self.pageText(for: pageEntry.entry.block, page: page)
            guard let range = selectedUTF16Range(
                forPageEntryIndex: index,
                pageEntry: pageEntry,
                page: page,
                pageText: pageText,
                selection: selection
            ) else {
                continue
            }
            let text = (pageText as NSString).substring(
                with: NSRange(location: range.lowerBound, length: range.count)
            )
            if !text.isEmpty {
                chunks.append(text)
            }
        }
        let text = chunks.joined(separator: "\n").trimmingCharacters(in: .newlines)
        return text.isEmpty ? nil : text
    }

    private func firstTextEndpoint() -> TextSelectionEndpoint? {
        for pageEntry in pageEntries {
            guard let page = pageEntry.page else { continue }
            switch pageEntry.chrome {
            case .plain, .accordionContent:
                let pageInfo = Self.pageTextInfo(for: pageEntry.entry.block, page: page)
                if (pageInfo.text as NSString).length > 0 {
                    return TextSelectionEndpoint(
                        blockID: pageEntry.entry.block.id,
                        utf16Offset: pageInfo.globalUTF16Range.lowerBound
                    )
                }
            case .accordionHeader, .compaction:
                continue
            }
        }
        return nil
    }

    private func lastTextEndpoint() -> TextSelectionEndpoint? {
        for pageEntry in pageEntries.reversed() {
            guard let page = pageEntry.page else { continue }
            switch pageEntry.chrome {
            case .plain, .accordionContent:
                let pageInfo = Self.pageTextInfo(for: pageEntry.entry.block, page: page)
                let length = (pageInfo.text as NSString).length
                if length > 0 {
                    return TextSelectionEndpoint(
                        blockID: pageEntry.entry.block.id,
                        utf16Offset: pageInfo.globalUTF16Range.upperBound
                    )
                }
            case .accordionHeader, .compaction:
                continue
            }
        }
        return nil
    }

    private static func pageText(
        for block: CodexTrajectoryBlock,
        page: CodexTrajectoryLayoutPage
    ) -> String {
        pageTextInfo(for: block, page: page).text
    }

    private static func displayText(for block: CodexTrajectoryBlock) -> String {
        block.displayText.isEmpty ? " " : block.displayText
    }

    private static func pageTextInfo(
        for block: CodexTrajectoryBlock,
        page: CodexTrajectoryLayoutPage
    ) -> (text: String, globalUTF16Range: Range<Int>) {
        let displayText = displayText(for: block)
        guard page.textRange.length > 0 else {
            let offset = globalUTF16Offset(in: displayText, characterOffset: page.textRange.location)
            return ("", offset..<offset)
        }
        let lower = displayText.index(
            displayText.startIndex,
            offsetBy: page.textRange.location,
            limitedBy: displayText.endIndex
        ) ?? displayText.endIndex
        let upper = displayText.index(
            lower,
            offsetBy: page.textRange.length,
            limitedBy: displayText.endIndex
        ) ?? displayText.endIndex
        let text = String(displayText[lower..<upper])
        let lowerOffset = String(displayText[..<lower]).utf16.count
        let upperOffset = String(displayText[..<upper]).utf16.count
        return (text, lowerOffset..<upperOffset)
    }

    private static func globalUTF16Offset(in text: String, characterOffset: Int) -> Int {
        let index = text.index(
            text.startIndex,
            offsetBy: max(0, characterOffset),
            limitedBy: text.endIndex
        ) ?? text.endIndex
        return String(text[..<index]).utf16.count
    }

    private func toggleAccordion(id: String) {
        let current = expansionProgress(for: id)
        let shouldExpand = !expandedAccordionIDs.contains(id)
        if shouldExpand {
            expandedAccordionIDs.insert(id)
        } else {
            expandedAccordionIDs.remove(id)
        }

        expansionAnimations[id] = ExpansionAnimation(
            from: current,
            to: shouldExpand ? 1 : 0,
            startTime: Self.animationTime,
            duration: accordionAnimationDuration
        )
        startAnimationTimer()
        rebuildLayout()
    }

    private func expansionProgress(for id: String) -> CGFloat {
        guard let animation = expansionAnimations[id] else {
            return expandedAccordionIDs.contains(id) ? 1 : 0
        }
        let elapsed = max(0, Self.animationTime - animation.startTime)
        let linear = min(1, elapsed / animation.duration)
        let eased = linear * linear * (3 - 2 * linear)
        return animation.from + (animation.to - animation.from) * eased
    }

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.animationTick()
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func animationTick() {
        let now = Self.animationTime
        let completedIDs = expansionAnimations.compactMap { id, animation -> String? in
            now - animation.startTime >= animation.duration ? id : nil
        }
        for id in completedIDs {
            expansionAnimations.removeValue(forKey: id)
        }
        rebuildLayout()

        if expansionAnimations.isEmpty {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private static var animationTime: TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }

    private func accordionHeaderRect(at y: CGFloat) -> CGRect {
        CGRect(
            x: horizontalInset,
            y: y + rowSpacing / 2,
            width: max(1, documentWidth - horizontalInset * 2),
            height: accordionHeaderHeight
        )
    }

    private func drawCompaction(
        entry: CodexTrajectoryTranscriptDisplayEntry,
        at y: CGFloat,
        context: CGContext
    ) {
        let rect = CGRect(
            x: horizontalInset,
            y: y,
            width: max(1, documentWidth - horizontalInset * 2),
            height: compactionHeight
        )
        let font = CTFontCreateUIFontForLanguage(.system, 12, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let textColor = Self.color(.secondaryLabelColor, appearance: effectiveAppearance)
        let lineColor = Self.color(.separatorColor, appearance: effectiveAppearance)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: textColor.cgColor,
        ]
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, entry.title as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        let textWidth = min(
            rect.width * 0.72,
            max(1, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        )
        let gap: CGFloat = 14
        let centerY = rect.midY
        let textRect = CGRect(
            x: rect.midX - textWidth / 2,
            y: centerY - 8,
            width: textWidth,
            height: 16
        )

        context.saveGState()
        context.setStrokeColor(lineColor.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: rect.minX, y: centerY))
        context.addLine(to: CGPoint(x: max(rect.minX, textRect.minX - gap), y: centerY))
        context.move(to: CGPoint(x: min(rect.maxX, textRect.maxX + gap), y: centerY))
        context.addLine(to: CGPoint(x: rect.maxX, y: centerY))
        context.strokePath()
        context.restoreGState()

        drawTruncatedLine(
            entry.title,
            font: font,
            color: textColor.cgColor,
            rect: textRect,
            context: context
        )
    }

    private func drawAccordionHeader(
        entry: CodexTrajectoryTranscriptDisplayEntry,
        in rect: CGRect,
        context: CGContext
    ) {
        let fill = Self.color(.controlBackgroundColor, appearance: effectiveAppearance)
        let stroke = Self.color(.separatorColor, appearance: effectiveAppearance)
        let primary = Self.color(.labelColor, appearance: effectiveAppearance)
        let secondary = Self.color(.secondaryLabelColor, appearance: effectiveAppearance)
        let tertiary = Self.color(.tertiaryLabelColor, appearance: effectiveAppearance)

        context.saveGState()
        context.setFillColor(fill.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        context.setStrokeColor(stroke.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.strokePath()
        context.restoreGState()

        drawChevron(
            progress: expansionProgress(for: entry.id),
            center: CGPoint(x: rect.minX + 18, y: rect.midY),
            color: secondary.cgColor,
            context: context
        )

        let titleFont = CTFontCreateUIFontForLanguage(.system, 13, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let subtitleFont = CTFontCreateUIFontForLanguage(.system, 12, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let statusFont = CTFontCreateUIFontForLanguage(.system, 12, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        let textX = rect.minX + 34
        let statusWidth: CGFloat = entry.statusText == nil ? 0 : 112
        let titleWidth = max(1, rect.maxX - textX - statusWidth - 12)
        drawTruncatedLine(
            entry.title,
            font: titleFont,
            color: primary.cgColor,
            rect: CGRect(x: textX, y: rect.minY + 6, width: titleWidth, height: 16),
            context: context
        )
        drawTruncatedLine(
            entry.subtitle,
            font: subtitleFont,
            color: tertiary.cgColor,
            rect: CGRect(x: textX, y: rect.minY + 22, width: titleWidth, height: 14),
            context: context
        )

        if let statusText = entry.statusText {
            drawTruncatedLine(
                statusText,
                font: statusFont,
                color: secondary.cgColor,
                rect: CGRect(x: rect.maxX - statusWidth - 12, y: rect.minY + 13, width: statusWidth, height: 15),
                context: context
            )
        }
    }

    private func drawChevron(
        progress: CGFloat,
        center: CGPoint,
        color: CGColor,
        context: CGContext
    ) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat.pi / 2 * progress)
        context.setStrokeColor(color)
        context.setLineWidth(1.7)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: -3.5, y: -5))
        context.addLine(to: CGPoint(x: 3, y: 0))
        context.addLine(to: CGPoint(x: -3.5, y: 5))
        context.strokePath()
        context.restoreGState()
    }

    private func drawAccordionContentBackground(in rect: CGRect, context: CGContext) {
        let fill = Self.color(.windowBackgroundColor, appearance: effectiveAppearance)
        let stroke = Self.color(.separatorColor, appearance: effectiveAppearance)
        context.saveGState()
        context.setFillColor(fill.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        context.setStrokeColor(stroke.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.strokePath()
        context.restoreGState()
    }

    private func drawBackground(
        for kind: CodexTrajectoryBlockKind,
        in rect: CGRect,
        context: CGContext
    ) {
        let fill = Self.backgroundColor(for: kind, appearance: effectiveAppearance)
        context.saveGState()
        context.setFillColor(fill.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    private func drawTruncatedLine(
        _ text: String,
        font: CTFont,
        color: CGColor,
        rect: CGRect,
        context: CGContext
    ) {
        guard rect.width > 1, rect.height > 1, !text.isEmpty else { return }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        let tokenAttributed = CFAttributedStringCreate(kCFAllocatorDefault, "..." as CFString, attributes as CFDictionary)!
        let token = CTLineCreateWithAttributedString(tokenAttributed)
        let displayLine = CTLineCreateTruncatedLine(line, Double(rect.width), .end, token) ?? line
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let lineHeight = ascent + descent + leading
        let baseline = max(descent, (rect.height - lineHeight) / 2 + descent)

        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: 0, y: baseline)
        CTLineDraw(displayLine, context)
        context.restoreGState()
    }

    private func pruneLayoutCache() {
        let activeIDs = Set(entries.map(\.block.id))
        cachedLayouts = cachedLayouts.filter { _, value in
            activeIDs.contains(value.block.id)
        }
    }

    private static func theme(for appearance: NSAppearance) -> CodexTrajectoryTheme {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textFont = CTFontCreateUIFontForLanguage(.system, 13, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let monoFont = CTFontCreateUIFontForLanguage(.userFixedPitch, 12, nil)
            ?? CTFontCreateWithName("Menlo" as CFString, 12, nil)
        let primary = color(.labelColor, appearance: appearance)
        let muted = color(.secondaryLabelColor, appearance: appearance)
        let error = color(isDark ? NSColor.systemRed : NSColor.systemRed, appearance: appearance)
        let fallback = CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary.cgColor)

        return CodexTrajectoryTheme(
            identifier: isDark ? "cmux-dark" : "cmux-light",
            contentInsets: CodexTrajectoryInsets(top: 9, left: 10, bottom: 9, right: 10),
            stylesByKind: [
                .userText: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary.cgColor),
                .assistantText: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary.cgColor),
                .commandOutput: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: primary.cgColor),
                .toolCall: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: muted.cgColor),
                .fileChange: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: primary.cgColor),
                .approvalRequest: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary.cgColor),
                .status: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: muted.cgColor),
                .stderr: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: error.cgColor),
                .systemEvent: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: muted.cgColor),
            ],
            fallbackStyle: fallback
        )
    }

    private static func backgroundColor(
        for kind: CodexTrajectoryBlockKind,
        appearance: NSAppearance
    ) -> NSColor {
        switch kind {
        case .userText:
            return color(NSColor.controlAccentColor.withAlphaComponent(0.10), appearance: appearance)
        case .assistantText:
            return color(.controlBackgroundColor, appearance: appearance)
        case .stderr:
            return color(NSColor.systemRed.withAlphaComponent(0.10), appearance: appearance)
        case .commandOutput, .toolCall, .fileChange, .systemEvent, .status, .approvalRequest:
            return color(.windowBackgroundColor, appearance: appearance)
        }
    }

    private static func color(_ color: NSColor, appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved.usingColorSpace(.sRGB) ?? resolved
    }
}
