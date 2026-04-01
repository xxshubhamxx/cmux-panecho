import XCTest
import Foundation
import CoreGraphics
import Darwin

private func workspaceDescriptionPollUntil(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.05,
    condition: () -> Bool
) -> Bool {
    let start = ProcessInfo.processInfo.systemUptime
    while true {
        if condition() {
            return true
        }
        if (ProcessInfo.processInfo.systemUptime - start) >= timeout {
            return false
        }
        RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
    }
}

final class WorkspaceDescriptionUITests: XCTestCase {
    private struct WorkspaceContext {
        let workspaceId: String
        let windowId: String
    }

    private var dataPath = ""
    private var socketPath = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        dataPath = "/tmp/cmux-ui-test-workspace-description-\(UUID().uuidString).json"
        socketPath = "/tmp/cmux-ui-test-workspace-description-\(UUID().uuidString).sock"
        try? FileManager.default.removeItem(atPath: dataPath)
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    func testCmdShiftEAllowsImmediateTypingAndSave() {
        let app = configuredApp()
        launchAndEnsureForeground(app)

        guard let context = prepareTerminalFocusedWorkspaceContext(app: app) else { return }

        let description = "Cmd Shift E focus note"
        app.typeKey("e", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            waitForDescriptionPaletteOpen(windowId: context.windowId, timeout: 5.0),
            "Expected Cmd+Shift+E to open the workspace description command palette while terminal is focused. snapshot=\(commandPaletteSnapshot(windowId: context.windowId) ?? [:])"
        )

        app.typeText(description)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(
            waitForWorkspaceDescription(workspaceId: context.workspaceId, expectedDescription: description, timeout: 5.0),
            "Expected immediate typing to save the workspace description. current=\(currentWorkspaceDescription(workspaceId: context.workspaceId) ?? "nil")"
        )
        XCTAssertTrue(
            waitForDescriptionPaletteClosed(windowId: context.windowId, timeout: 5.0),
            "Expected Enter to save and dismiss the workspace description palette"
        )
    }

    func testClickingDescriptionEditorAllowsTypingAndSave() {
        let app = configuredApp()
        launchAndEnsureForeground(app)

        guard let context = prepareTerminalFocusedWorkspaceContext(app: app) else { return }

        let description = "Clicked description note"
        app.typeKey("e", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            waitForDescriptionPaletteOpen(windowId: context.windowId, timeout: 5.0),
            "Expected Cmd+Shift+E to open the workspace description command palette while terminal is focused. snapshot=\(commandPaletteSnapshot(windowId: context.windowId) ?? [:])"
        )

        clickDescriptionEditor(in: app)
        app.typeText(description)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(
            waitForWorkspaceDescription(workspaceId: context.workspaceId, expectedDescription: description, timeout: 5.0),
            "Expected clicking the description editor to allow typing and save the workspace description. current=\(currentWorkspaceDescription(workspaceId: context.workspaceId) ?? "nil")"
        )
        XCTAssertTrue(
            waitForDescriptionPaletteClosed(windowId: context.windowId, timeout: 5.0),
            "Expected Enter to save and dismiss the workspace description palette after clicking"
        )
    }

    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        return app
    }

    private func prepareTerminalFocusedWorkspaceContext(app: XCUIApplication) -> WorkspaceContext? {
        XCTAssertTrue(
            waitForData(keys: ["terminalPaneId", "webViewFocused"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return nil
        }

        XCTAssertEqual(setup["webViewFocused"], "true", "Expected WKWebView to be first responder for this test")

        guard let expectedTerminalPaneId = setup["terminalPaneId"] else {
            XCTFail("Missing terminalPaneId in goto_split setup data")
            return nil
        }

        XCTAssertTrue(waitForSocketReady(timeout: 5.0), "Expected control socket to become ready")

        app.typeKey("h", modifierFlags: [.command, .control])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["lastMoveDirection"] == "left" && data["focusedPaneId"] == expectedTerminalPaneId
            },
            "Expected Cmd+Ctrl+H to move focus to the terminal pane before opening the description palette"
        )

        guard let context = currentWorkspaceContext() else {
            XCTFail("Missing workspace context after focusing the terminal pane")
            return nil
        }

        return context
    }

    private func clickDescriptionEditor(in app: XCUIApplication) {
        if let editor = firstExistingElement(
            candidates: descriptionEditorCandidates(in: app),
            timeout: 1.5
        ) {
            editor.click()
            return
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5.0), "Expected app window for description editor click target")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).click()
    }

    private func descriptionEditorCandidates(in app: XCUIApplication) -> [XCUIElement] {
        [
            app.textViews["CommandPaletteWorkspaceDescriptionEditor"],
            app.scrollViews["CommandPaletteWorkspaceDescriptionEditor"],
            app.otherElements["CommandPaletteWorkspaceDescriptionEditor"],
            app.staticTexts["Workspace description"],
        ]
    }

    private func firstExistingElement(
        candidates: [XCUIElement],
        timeout: TimeInterval
    ) -> XCUIElement? {
        var match: XCUIElement?
        let found = workspaceDescriptionPollUntil(timeout: timeout) {
            for candidate in candidates where candidate.exists {
                match = candidate
                return true
            }
            return false
        }
        return found ? match : nil
    }

    private func launchAndEnsureForeground(_ app: XCUIApplication, timeout: TimeInterval = 12.0) {
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("App activation may fail on headless runners", options: options) {
            app.launch()
        }

        if app.state == .runningForeground {
            return
        }

        let activated = workspaceDescriptionPollUntil(timeout: timeout) {
            app.activate()
            return app.state == .runningForeground || app.state == .runningBackground
        }
        XCTAssertTrue(activated, "App failed to start. state=\(app.state.rawValue)")
    }

    private func waitForData(keys: [String], timeout: TimeInterval) -> Bool {
        workspaceDescriptionPollUntil(timeout: timeout) {
            guard let data = self.loadData() else { return false }
            return keys.allSatisfy { data[$0] != nil }
        }
    }

    private func waitForDataMatch(timeout: TimeInterval, predicate: @escaping ([String: String]) -> Bool) -> Bool {
        workspaceDescriptionPollUntil(timeout: timeout) {
            guard let data = self.loadData() else { return false }
            return predicate(data)
        }
    }

    private func loadData() -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dataPath)) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
    }

    private func waitForSocketReady(timeout: TimeInterval) -> Bool {
        workspaceDescriptionPollUntil(timeout: timeout) {
            self.socketCommand("ping") == "PONG"
        }
    }

    private func currentWorkspaceContext() -> WorkspaceContext? {
        guard let envelope = socketJSON(method: "workspace.current", params: [:]),
              let ok = envelope["ok"] as? Bool,
              ok,
              let result = envelope["result"] as? [String: Any],
              let workspaceId = result["workspace_id"] as? String,
              let windowId = result["window_id"] as? String else {
            return nil
        }
        return WorkspaceContext(workspaceId: workspaceId, windowId: windowId)
    }

    private func currentWorkspaceDescription(workspaceId: String) -> String? {
        guard let envelope = socketJSON(method: "workspace.current", params: [:]),
              let ok = envelope["ok"] as? Bool,
              ok,
              let result = envelope["result"] as? [String: Any],
              let currentWorkspaceId = result["workspace_id"] as? String,
              currentWorkspaceId == workspaceId,
              let workspace = result["workspace"] as? [String: Any] else {
            return nil
        }
        return workspace["description"] as? String
    }

    private func waitForWorkspaceDescription(
        workspaceId: String,
        expectedDescription: String,
        timeout: TimeInterval
    ) -> Bool {
        workspaceDescriptionPollUntil(timeout: timeout) {
            self.currentWorkspaceDescription(workspaceId: workspaceId) == expectedDescription
        }
    }

    private func waitForDescriptionPaletteOpen(windowId: String, timeout: TimeInterval) -> Bool {
        workspaceDescriptionPollUntil(timeout: timeout) {
            guard let snapshot = self.commandPaletteSnapshot(windowId: windowId) else { return false }
            return (snapshot["visible"] as? Bool) == true
                && (snapshot["mode"] as? String) == "workspace_description_input"
        }
    }

    private func waitForDescriptionPaletteClosed(windowId: String, timeout: TimeInterval) -> Bool {
        workspaceDescriptionPollUntil(timeout: timeout) {
            guard let snapshot = self.commandPaletteSnapshot(windowId: windowId) else { return false }
            return (snapshot["visible"] as? Bool) != true
        }
    }

    private func commandPaletteSnapshot(windowId: String) -> [String: Any]? {
        let envelope = socketJSON(
            method: "debug.command_palette.results",
            params: [
                "window_id": windowId,
                "limit": 20,
            ]
        )
        guard let ok = envelope?["ok"] as? Bool, ok else { return nil }
        return envelope?["result"] as? [String: Any]
    }

    private func socketCommand(_ command: String) -> String? {
        ControlSocketClient(path: socketPath, responseTimeout: 2.0).sendLine(command)
    }

    private func socketJSON(method: String, params: [String: Any]) -> [String: Any]? {
        let request: [String: Any] = [
            "id": UUID().uuidString,
            "method": method,
            "params": params,
        ]
        return ControlSocketClient(path: socketPath, responseTimeout: 2.0).sendJSON(request)
    }

    private final class ControlSocketClient {
        private let path: String
        private let responseTimeout: TimeInterval

        init(path: String, responseTimeout: TimeInterval) {
            self.path = path
            self.responseTimeout = responseTimeout
        }

        func sendJSON(_ object: [String: Any]) -> [String: Any]? {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  let line = String(data: data, encoding: .utf8),
                  let response = sendLine(line),
                  let responseData = response.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                return nil
            }
            return parsed
        }

        func sendLine(_ line: String) -> String? {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }
            defer { close(fd) }

#if os(macOS)
            var noSigPipe: Int32 = 1
            _ = withUnsafePointer(to: &noSigPipe) { ptr in
                setsockopt(
                    fd,
                    SOL_SOCKET,
                    SO_NOSIGPIPE,
                    ptr,
                    socklen_t(MemoryLayout<Int32>.size)
                )
            }
#endif

            var addr = sockaddr_un()
            memset(&addr, 0, MemoryLayout<sockaddr_un>.size)
            addr.sun_family = sa_family_t(AF_UNIX)

            let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
            let bytes = Array(path.utf8CString)
            guard bytes.count <= maxLen else { return nil }
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                memset(raw, 0, maxLen)
                for index in 0..<bytes.count {
                    raw[index] = bytes[index]
                }
            }

            let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 0
            let addrLen = socklen_t(pathOffset + bytes.count)
#if os(macOS)
            addr.sun_len = UInt8(min(Int(addrLen), 255))
#endif

            let connected = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(fd, sa, addrLen)
                }
            }
            guard connected == 0 else { return nil }

            let payload = line + "\n"
            let wrote: Bool = payload.withCString { cString in
                var remaining = strlen(cString)
                var pointer = UnsafeRawPointer(cString)
                while remaining > 0 {
                    let written = write(fd, pointer, remaining)
                    if written <= 0 { return false }
                    remaining -= written
                    pointer = pointer.advanced(by: written)
                }
                return true
            }
            guard wrote else { return nil }

            let deadline = Date().addingTimeInterval(responseTimeout)
            var buffer = [UInt8](repeating: 0, count: 4096)
            var accumulator = ""
            while Date() < deadline {
                var pollDescriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&pollDescriptor, 1, 100)
                if ready < 0 {
                    return nil
                }
                if ready == 0 {
                    continue
                }

                let count = read(fd, &buffer, buffer.count)
                if count <= 0 { break }
                if let chunk = String(bytes: buffer[0..<count], encoding: .utf8) {
                    accumulator.append(chunk)
                    if let newline = accumulator.firstIndex(of: "\n") {
                        return String(accumulator[..<newline])
                    }
                }
            }

            return accumulator.isEmpty ? nil : accumulator.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
