import XCTest
import Foundation
import CoreGraphics

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
    private var dataPath = ""
    private var launchTag = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        dataPath = "/tmp/cmux-ui-test-workspace-description-\(UUID().uuidString).json"
        launchTag = "ui-tests-workspace-description-\(UUID().uuidString.lowercased())"
        try? FileManager.default.removeItem(atPath: dataPath)
    }

    func testCmdShiftEAllowsImmediateTypingAndSave() {
        let app = configuredApp()
        launchAndEnsureForeground(app)
        prepareTerminalFocusedWorkspace(app)

        let description = "Cmd Shift E focus note \(String(UUID().uuidString.prefix(8)))"
        app.typeKey("e", modifierFlags: [.command, .shift])

        let editor = requireDescriptionEditor(
            in: app,
            timeout: 5.0,
            failureMessage: "Expected Cmd+Shift+E to open the workspace description editor while terminal is focused"
        )

        app.typeText(description)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(
            waitForNonExistence(editor, timeout: 5.0),
            "Expected Enter to save and dismiss the workspace description editor"
        )
        XCTAssertTrue(
            app.staticTexts[description].firstMatch.waitForExistence(timeout: 5.0),
            "Expected immediate typing to save the workspace description into the sidebar"
        )
    }

    func testClickingDescriptionEditorAllowsTypingAndSave() {
        let app = configuredApp()
        launchAndEnsureForeground(app)
        prepareTerminalFocusedWorkspace(app)

        let description = "Clicked description note \(String(UUID().uuidString.prefix(8)))"
        app.typeKey("e", modifierFlags: [.command, .shift])

        let editor = requireDescriptionEditor(
            in: app,
            timeout: 5.0,
            failureMessage: "Expected Cmd+Shift+E to open the workspace description editor while terminal is focused"
        )

        clickDescriptionEditor(editor, in: app)
        app.typeText(description)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(
            waitForNonExistence(editor, timeout: 5.0),
            "Expected Enter to save and dismiss the workspace description editor after clicking"
        )
        XCTAssertTrue(
            app.staticTexts[description].firstMatch.waitForExistence(timeout: 5.0),
            "Expected clicking the description editor to allow typing and save the workspace description"
        )
    }

    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        app.launchEnvironment["CMUX_TAG"] = launchTag
        return app
    }

    private func prepareTerminalFocusedWorkspace(_ app: XCUIApplication) {
        XCTAssertTrue(
            waitForData(keys: ["terminalPaneId", "webViewFocused"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        XCTAssertEqual(setup["webViewFocused"], "true", "Expected WKWebView to be first responder for this test")

        guard let expectedTerminalPaneId = setup["terminalPaneId"] else {
            XCTFail("Missing terminalPaneId in goto_split setup data")
            return
        }

        app.typeKey("h", modifierFlags: [.command, .control])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["lastMoveDirection"] == "left" && data["focusedPaneId"] == expectedTerminalPaneId
            },
            "Expected Cmd+Ctrl+H to move focus to the terminal pane before opening the description editor"
        )
    }

    private func requireDescriptionEditor(
        in app: XCUIApplication,
        timeout: TimeInterval,
        failureMessage: String
    ) -> XCUIElement {
        guard let editor = firstExistingElement(
            candidates: descriptionEditorCandidates(in: app),
            timeout: timeout
        ) else {
            XCTFail(failureMessage)
            return app.textViews["CommandPaletteWorkspaceDescriptionEditor"].firstMatch
        }
        return editor
    }

    private func clickDescriptionEditor(_ editor: XCUIElement, in app: XCUIApplication) {
        if editor.exists {
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
        XCTExpectFailure("App activation may fail on headless CI runners", options: options) {
            app.launch()
        }

        if app.state == .runningForeground { return }
        if app.state == .runningBackground { return }

        XCTFail("App failed to start. state=\(app.state.rawValue)")
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

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func loadData() -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dataPath)) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
    }
}
