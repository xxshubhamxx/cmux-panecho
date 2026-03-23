import XCTest
import Foundation

final class BrowserPaneNavigationKeybindUITests: XCTestCase {
    private var dataPath = ""
    private var socketPath = ""
    private var launchDiagnosticsPath = ""
    private var launchTag = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        dataPath = "/tmp/cmux-ui-test-goto-split-\(UUID().uuidString).json"
        try? FileManager.default.removeItem(atPath: dataPath)
        socketPath = "/tmp/cmux-ui-test-socket-\(UUID().uuidString).sock"
        try? FileManager.default.removeItem(atPath: socketPath)
        launchDiagnosticsPath = "/tmp/cmux-ui-test-launch-\(UUID().uuidString).json"
        try? FileManager.default.removeItem(atPath: launchDiagnosticsPath)
        launchTag = "ui-tests-browser-nav-\(UUID().uuidString.prefix(8))"

        let diagnosticsPath = launchDiagnosticsPath
        addTeardownBlock { [weak self] in
            guard let self,
                  let contents = try? String(contentsOfFile: diagnosticsPath, encoding: .utf8),
                  !contents.isEmpty else {
                return
            }
            print("UI_TEST_LAUNCH_DIAGNOSTICS_BEGIN")
            print(contents)
            print("UI_TEST_LAUNCH_DIAGNOSTICS_END")
            let attachment = XCTAttachment(string: contents)
            attachment.name = "ui-test-launch-diagnostics"
            attachment.lifetime = .deleteOnSuccess
            self.add(attachment)
        }

        let cleanup = XCUIApplication()
        cleanup.terminate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    func testCmdCtrlHMovesLeftWhenWebViewFocused() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["terminalPaneId", "browserPaneId", "webViewFocused"], timeout: 10.0),
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

        // Trigger pane navigation via the actual key event path (while WebKit is first responder).
        app.typeKey("h", modifierFlags: [.command, .control])

        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["lastMoveDirection"] == "left" && data["focusedPaneId"] == expectedTerminalPaneId
            },
            "Expected Cmd+Ctrl+H to move focus to left pane (terminal)"
        )
    }

    func testCmdCtrlHMovesLeftWhenWebViewFocusedUsingGhosttyConfigKeybind() {
        // Write a test Ghostty config in the preferred macOS location so GhosttyKit loads it at app startup.
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            XCTFail("Missing Application Support directory")
            return
        }

        let ghosttyDir = appSupport.appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)
        let configURL = ghosttyDir.appendingPathComponent("config.ghostty", isDirectory: false)

        do {
            try fileManager.createDirectory(at: ghosttyDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create Ghostty app support dir: \(error)")
            return
        }

        let originalConfigData = try? Data(contentsOf: configURL)
        addTeardownBlock {
            if let originalConfigData {
                try? originalConfigData.write(to: configURL, options: .atomic)
            } else {
                try? fileManager.removeItem(at: configURL)
            }
        }

        let home = fileManager.homeDirectoryForCurrentUser
        let configContents = """
        # cmux ui test
        working-directory = \(home.path)
        keybind = cmd+ctrl+h=goto_split:left
        """
        do {
            try configContents.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to write Ghostty config: \(error)")
            return
        }

        let app = XCUIApplication()
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_USE_GHOSTTY_CONFIG"] = "1"
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["terminalPaneId", "browserPaneId", "webViewFocused", "ghosttyGotoSplitLeftShortcut"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        XCTAssertEqual(setup["webViewFocused"], "true", "Expected WKWebView to be first responder for this test")
        XCTAssertFalse((setup["ghosttyGotoSplitLeftShortcut"] ?? "").isEmpty, "Expected Ghostty trigger metadata to be present")

        guard let expectedTerminalPaneId = setup["terminalPaneId"] else {
            XCTFail("Missing terminalPaneId in goto_split setup data")
            return
        }

        // Trigger pane navigation via the actual key event path (while WebKit is first responder).
        app.typeKey("h", modifierFlags: [.command, .control])

        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["lastMoveDirection"] == "left" && data["focusedPaneId"] == expectedTerminalPaneId
            },
            "Expected Cmd+Ctrl+H to move focus to left pane (terminal) via Ghostty config trigger"
        )
    }

    func testEscapeLeavesOmnibarAndFocusesWebView() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["browserPanelId", "webViewFocused"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        XCTAssertEqual(setup["webViewFocused"], "true", "Expected WKWebView to be first responder for this test")

        // Cmd+L focuses the omnibar (so WebKit is no longer first responder).
        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["webViewFocusedAfterAddressBarFocus"] == "false"
            },
            "Expected Cmd+L to focus omnibar (WebKit not first responder)"
        )

        // Escape should leave the omnibar and focus WebKit again.
        // Send Escape twice: the first may only clear suggestions/editing state
        // (Chrome-like two-stage escape), the second triggers blur to WebView.
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        if !waitForDataMatch(timeout: 2.0, predicate: { $0["webViewFocusedAfterAddressBarExit"] == "true" }) {
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        }
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["webViewFocusedAfterAddressBarExit"] == "true"
            },
            "Expected Escape to return focus to WebKit"
        )
    }

    func testEscapeRestoresFocusedPageInputAfterCmdL() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_INPUT_SETUP"] = "1"
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(
                keys: [
                    "browserPanelId",
                    "webViewFocused",
                    "webInputFocusSeeded",
                    "webInputFocusElementId",
                    "webInputFocusSecondaryElementId",
                    "webInputFocusSecondaryClickOffsetX",
                    "webInputFocusSecondaryClickOffsetY"
                ],
                timeout: 12.0
            ),
            "Expected setup data including focused page input to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        XCTAssertEqual(setup["webViewFocused"], "true", "Expected WKWebView to be first responder for this test")
        XCTAssertEqual(setup["webInputFocusSeeded"], "true", "Expected test page input to be focused before Cmd+L")

        guard let expectedInputId = setup["webInputFocusElementId"], !expectedInputId.isEmpty else {
            XCTFail("Missing webInputFocusElementId in setup data")
            return
        }
        guard let expectedSecondaryInputId = setup["webInputFocusSecondaryElementId"], !expectedSecondaryInputId.isEmpty else {
            XCTFail("Missing webInputFocusSecondaryElementId in setup data")
            return
        }
        guard let secondaryClickOffsetXRaw = setup["webInputFocusSecondaryClickOffsetX"],
              let secondaryClickOffsetYRaw = setup["webInputFocusSecondaryClickOffsetY"],
              let secondaryClickOffsetX = Double(secondaryClickOffsetXRaw),
              let secondaryClickOffsetY = Double(secondaryClickOffsetYRaw) else {
            XCTFail(
                "Missing or invalid secondary input click offsets in setup data. " +
                "webInputFocusSecondaryClickOffsetX=\(setup["webInputFocusSecondaryClickOffsetX"] ?? "nil") " +
                "webInputFocusSecondaryClickOffsetY=\(setup["webInputFocusSecondaryClickOffsetY"] ?? "nil")"
            )
            return
        }

        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["webViewFocusedAfterAddressBarFocus"] == "false"
            },
            "Expected Cmd+L to focus omnibar"
        )

        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        if !waitForDataMatch(timeout: 2.0, predicate: { data in
            data["webViewFocusedAfterAddressBarExit"] == "true" &&
                data["addressBarExitActiveElementId"] == expectedInputId &&
                data["addressBarExitActiveElementEditable"] == "true"
        }) {
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        }

        let restoredExpectedInput = waitForDataMatch(timeout: 6.0) { data in
            data["webViewFocusedAfterAddressBarExit"] == "true" &&
                data["addressBarExitActiveElementId"] == expectedInputId &&
                data["addressBarExitActiveElementEditable"] == "true"
        }
        if !restoredExpectedInput {
            let snapshot = loadData() ?? [:]
            XCTFail(
                "Expected Escape to restore focus to the previously focused page input. " +
                "expectedInputId=\(expectedInputId) " +
                "webViewFocusedAfterAddressBarExit=\(snapshot["webViewFocusedAfterAddressBarExit"] ?? "nil") " +
                "addressBarExitActiveElementId=\(snapshot["addressBarExitActiveElementId"] ?? "nil") " +
                "addressBarExitActiveElementTag=\(snapshot["addressBarExitActiveElementTag"] ?? "nil") " +
                "addressBarExitActiveElementType=\(snapshot["addressBarExitActiveElementType"] ?? "nil") " +
                "addressBarExitActiveElementEditable=\(snapshot["addressBarExitActiveElementEditable"] ?? "nil") " +
                "addressBarExitTrackedFocusStateId=\(snapshot["addressBarExitTrackedFocusStateId"] ?? "nil") " +
                "addressBarExitFocusTrackerInstalled=\(snapshot["addressBarExitFocusTrackerInstalled"] ?? "nil") " +
                "addressBarFocusActiveElementId=\(snapshot["addressBarFocusActiveElementId"] ?? "nil") " +
                "addressBarFocusTrackedFocusStateId=\(snapshot["addressBarFocusTrackedFocusStateId"] ?? "nil") " +
                "addressBarFocusFocusTrackerInstalled=\(snapshot["addressBarFocusFocusTrackerInstalled"] ?? "nil") " +
                "webInputFocusElementId=\(snapshot["webInputFocusElementId"] ?? "nil") " +
                "webInputFocusTrackerInstalled=\(snapshot["webInputFocusTrackerInstalled"] ?? "nil") " +
                "webInputFocusTrackedStateId=\(snapshot["webInputFocusTrackedStateId"] ?? "nil")"
            )
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 6.0),
            "Expected app window for post-escape click regression check"
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        window
            .coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0))
            .withOffset(CGVector(dx: secondaryClickOffsetX, dy: secondaryClickOffsetY))
            .click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        app.typeKey("l", modifierFlags: [.command])
        let clickMovedFocusToSecondary = waitForDataMatch(timeout: 6.0) { data in
            data["webViewFocusedAfterAddressBarFocus"] == "false" &&
                data["addressBarFocusActiveElementId"] == expectedSecondaryInputId &&
                data["addressBarFocusActiveElementEditable"] == "true"
        }
        if !clickMovedFocusToSecondary {
            let snapshot = loadData() ?? [:]
            XCTFail(
                "Expected post-escape click to focus secondary page input before Cmd+L. " +
                "secondaryInputId=\(expectedSecondaryInputId) " +
                "addressBarFocusActiveElementId=\(snapshot["addressBarFocusActiveElementId"] ?? "nil") " +
                "addressBarFocusActiveElementTag=\(snapshot["addressBarFocusActiveElementTag"] ?? "nil") " +
                "addressBarFocusActiveElementType=\(snapshot["addressBarFocusActiveElementType"] ?? "nil") " +
                "addressBarFocusActiveElementEditable=\(snapshot["addressBarFocusActiveElementEditable"] ?? "nil") " +
                "addressBarFocusTrackedFocusStateId=\(snapshot["addressBarFocusTrackedFocusStateId"] ?? "nil") " +
                "addressBarFocusFocusTrackerInstalled=\(snapshot["addressBarFocusFocusTrackerInstalled"] ?? "nil")"
            )
        }

        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        if !waitForDataMatch(timeout: 2.0, predicate: { data in
            data["webViewFocusedAfterAddressBarExit"] == "true" &&
                data["addressBarExitActiveElementId"] == expectedSecondaryInputId &&
                data["addressBarExitActiveElementEditable"] == "true"
        }) {
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        }

        XCTAssertTrue(
            waitForDataMatch(timeout: 6.0) { data in
                data["webViewFocusedAfterAddressBarExit"] == "true" &&
                    data["addressBarExitActiveElementId"] == expectedSecondaryInputId &&
                    data["addressBarExitActiveElementEditable"] == "true"
            },
            "Expected Escape to restore focus to the clicked secondary page input"
        )
    }

    func testArrowKeysReachClickedPageInputAfterCmdL() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_INPUT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_ARROW_SETUP"] = "1"
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(
                keys: [
                    "browserPanelId",
                    "webViewFocused",
                    "webInputFocusSeeded",
                    "webInputFocusElementId",
                    "webInputFocusSecondaryElementId",
                    "webInputFocusPrimaryClickOffsetX",
                    "webInputFocusPrimaryClickOffsetY",
                    "webInputFocusSecondaryClickOffsetX",
                    "webInputFocusSecondaryClickOffsetY"
                ],
                timeout: 20.0
            ),
            "Expected focused page input setup data to be written. data=\(String(describing: loadData()))"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        XCTAssertEqual(setup["webInputFocusSeeded"], "true", "Expected test page input to be focused before arrow-key checks")

        guard let primaryInputId = setup["webInputFocusElementId"], !primaryInputId.isEmpty else {
            XCTFail("Missing webInputFocusElementId in setup data")
            return
        }
        guard let secondaryInputId = setup["webInputFocusSecondaryElementId"], !secondaryInputId.isEmpty else {
            XCTFail("Missing webInputFocusSecondaryElementId in setup data")
            return
        }
        guard let primaryClickOffsetXRaw = setup["webInputFocusPrimaryClickOffsetX"],
              let primaryClickOffsetYRaw = setup["webInputFocusPrimaryClickOffsetY"],
              let primaryClickOffsetX = Double(primaryClickOffsetXRaw),
              let primaryClickOffsetY = Double(primaryClickOffsetYRaw) else {
            XCTFail(
                "Missing or invalid primary input click offsets in setup data. " +
                "webInputFocusPrimaryClickOffsetX=\(setup["webInputFocusPrimaryClickOffsetX"] ?? "nil") " +
                "webInputFocusPrimaryClickOffsetY=\(setup["webInputFocusPrimaryClickOffsetY"] ?? "nil")"
            )
            return
        }
        guard let secondaryClickOffsetXRaw = setup["webInputFocusSecondaryClickOffsetX"],
              let secondaryClickOffsetYRaw = setup["webInputFocusSecondaryClickOffsetY"],
              let secondaryClickOffsetX = Double(secondaryClickOffsetXRaw),
              let secondaryClickOffsetY = Double(secondaryClickOffsetYRaw) else {
            XCTFail(
                "Missing or invalid secondary input click offsets in setup data. " +
                "webInputFocusSecondaryClickOffsetX=\(setup["webInputFocusSecondaryClickOffsetX"] ?? "nil") " +
                "webInputFocusSecondaryClickOffsetY=\(setup["webInputFocusSecondaryClickOffsetY"] ?? "nil")"
            )
            return
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5.0), "Expected main window before arrow-key regression check")

        window
            .coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0))
            .withOffset(CGVector(dx: primaryClickOffsetX, dy: primaryClickOffsetY))
            .click()

        guard let initialArrowSnapshot = waitForDataSnapshot(
            timeout: 8.0,
            predicate: { data in
                data["browserArrowInstalled"] == "true" &&
                    data["browserArrowActiveElementId"] == primaryInputId &&
                    data["browserArrowDownCount"] == "0" &&
                    data["browserArrowUpCount"] == "0"
            }
        ) else {
            XCTFail(
                "Expected arrow recorder to initialize with the primary page input focused. " +
                "data=\(String(describing: loadData()))"
            )
            return
        }
        let initialDownCount = Int(initialArrowSnapshot["browserArrowDownCount"] ?? "") ?? -1
        let initialUpCount = Int(initialArrowSnapshot["browserArrowUpCount"] ?? "") ?? -1

        simulateShortcut("down", app: app)
        guard let baselineDownSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserArrowActiveElementId"] == primaryInputId &&
                    data["browserArrowDownCount"] == "\(initialDownCount + 1)" &&
                    data["browserArrowUpCount"] == "\(initialUpCount)"
            }
        ) else {
            XCTFail(
                "Expected baseline Down Arrow to reach the primary page input. " +
                "data=\(String(describing: loadData()))"
            )
            return
        }
        let baselineDownCount = Int(baselineDownSnapshot["browserArrowDownCount"] ?? "") ?? -1
        let baselineUpCount = Int(baselineDownSnapshot["browserArrowUpCount"] ?? "") ?? -1

        simulateShortcut("up", app: app)
        guard let baselineUpSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserArrowActiveElementId"] == primaryInputId &&
                    data["browserArrowDownCount"] == "\(baselineDownCount)" &&
                    data["browserArrowUpCount"] == "\(baselineUpCount + 1)"
            }
        ) else {
            XCTFail(
                "Expected baseline Up Arrow to reach the primary page input. " +
                "data=\(String(describing: loadData()))"
            )
            return
        }
        let baselineUpCountAfterUp = Int(baselineUpSnapshot["browserArrowUpCount"] ?? "") ?? -1

        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["webViewFocusedAfterAddressBarFocus"] == "false"
            },
            "Expected Cmd+L to focus the omnibar before the page-click arrow-key check"
        )

        window
            .coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0))
            .withOffset(CGVector(dx: secondaryClickOffsetX, dy: secondaryClickOffsetY))
            .click()

        guard waitForDataMatch(
            timeout: 5.0,
            predicate: { data in
                data["browserArrowActiveElementId"] == secondaryInputId
            }
        ) else {
            XCTFail(
                "Expected clicking the page to focus the secondary page input before sending arrows. " +
                "data=\(String(describing: loadData()))"
            )
            return
        }

        simulateShortcut("down", app: app)
        guard let postCmdLDownSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserArrowActiveElementId"] == secondaryInputId &&
                    data["browserArrowDownCount"] == "\(baselineDownCount + 1)" &&
                    data["browserArrowUpCount"] == "\(baselineUpCountAfterUp)"
            }
        ) else {
            XCTFail(
                "Expected Down Arrow after Cmd+L and page click to reach the secondary page input. " +
                "data=\(String(describing: loadData()))"
            )
            return
        }
        let postCmdLDownCount = Int(postCmdLDownSnapshot["browserArrowDownCount"] ?? "") ?? -1

        simulateShortcut("up", app: app)
        guard let postCmdLUpSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserArrowActiveElementId"] == secondaryInputId &&
                    data["browserArrowDownCount"] == "\(postCmdLDownCount)" &&
                    data["browserArrowUpCount"] == "\(baselineUpCountAfterUp + 1)"
            }
        ) else {
            XCTFail(
                "Expected Up Arrow after Cmd+L and page click to reach the secondary page input. " +
                "postCmdLDownSnapshot=\(postCmdLDownSnapshot) " +
                "data=\(String(describing: loadData()))"
            )
            return
        }

        XCTAssertEqual(postCmdLUpSnapshot["browserArrowActiveElementId"], secondaryInputId, "Expected the clicked secondary page input to remain focused")
    }

    func testArrowKeysReachClickedContentEditableAfterCmdL() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_INPUT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_ARROW_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_CONTENTEDITABLE_SETUP"] = "1"
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(
                keys: [
                    "webInputFocusSeeded",
                    "webContentEditableSeeded",
                    "webContentEditableElementId",
                    "webContentEditableClickOffsetX",
                    "webContentEditableClickOffsetY"
                ],
                timeout: 20.0
            ),
            "Expected focused page input setup data before contenteditable regression check. data=\(String(describing: loadData()))"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        XCTAssertEqual(setup["webInputFocusSeeded"], "true", "Expected test page inputs to be seeded before contenteditable regression check")
        XCTAssertEqual(setup["webContentEditableSeeded"], "true", "Expected contenteditable fixture to be seeded before contenteditable regression check")
        guard let editorId = setup["webContentEditableElementId"], !editorId.isEmpty else {
            XCTFail("Missing webContentEditableElementId in setup data")
            return
        }
        guard let editorClickOffsetXRaw = setup["webContentEditableClickOffsetX"],
              let editorClickOffsetYRaw = setup["webContentEditableClickOffsetY"],
              let editorClickOffsetX = Double(editorClickOffsetXRaw),
              let editorClickOffsetY = Double(editorClickOffsetYRaw) else {
            XCTFail(
                "Missing or invalid contenteditable click offsets in setup data. " +
                "webContentEditableClickOffsetX=\(setup["webContentEditableClickOffsetX"] ?? "nil") " +
                "webContentEditableClickOffsetY=\(setup["webContentEditableClickOffsetY"] ?? "nil")"
            )
            return
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5.0), "Expected main window before contenteditable regression check")

        window
            .coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0))
            .withOffset(CGVector(dx: editorClickOffsetX, dy: editorClickOffsetY))
            .click()

        guard let initialSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableInstalled"] == "true" &&
                    data["browserContentEditableActiveElementId"] == editorId &&
                    data["browserContentEditableDownCount"] == "0" &&
                    data["browserContentEditableUpCount"] == "0" &&
                    data["browserContentEditableCommandShiftDownCount"] == "0" &&
                    data["browserContentEditableCommandShiftUpCount"] == "0"
            }
        ) else {
            XCTFail("Expected contenteditable fixture to be focused before baseline arrows. data=\(String(describing: loadData()))")
            return
        }
        let initialDownCount = Int(initialSnapshot["browserContentEditableDownCount"] ?? "") ?? -1
        let initialUpCount = Int(initialSnapshot["browserContentEditableUpCount"] ?? "") ?? -1
        let initialCommandShiftDownCount = Int(initialSnapshot["browserContentEditableCommandShiftDownCount"] ?? "") ?? -1
        let initialCommandShiftUpCount = Int(initialSnapshot["browserContentEditableCommandShiftUpCount"] ?? "") ?? -1

        simulateShortcut("down", app: app)
        guard let baselineDownSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableActiveElementId"] == editorId &&
                    data["browserContentEditableDownCount"] == "\(initialDownCount + 1)" &&
                    data["browserContentEditableUpCount"] == "\(initialUpCount)"
            }
        ) else {
            XCTFail("Expected baseline Down Arrow to reach the contenteditable fixture. data=\(String(describing: loadData()))")
            return
        }
        let baselineDownCount = Int(baselineDownSnapshot["browserContentEditableDownCount"] ?? "") ?? -1

        simulateShortcut("up", app: app)
        guard let baselineUpSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableActiveElementId"] == editorId &&
                    data["browserContentEditableDownCount"] == "\(baselineDownCount)" &&
                    data["browserContentEditableUpCount"] == "\(initialUpCount + 1)"
            }
        ) else {
            XCTFail("Expected baseline Up Arrow to reach the contenteditable fixture. data=\(String(describing: loadData()))")
            return
        }
        let baselineUpCount = Int(baselineUpSnapshot["browserContentEditableUpCount"] ?? "") ?? -1

        simulateShortcut("cmdShiftDown", app: app)
        guard let baselineCommandShiftDownSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableActiveElementId"] == editorId &&
                    data["browserContentEditableCommandShiftDownCount"] == "\(initialCommandShiftDownCount + 1)" &&
                    data["browserContentEditableCommandShiftUpCount"] == "\(initialCommandShiftUpCount)"
            }
        ) else {
            XCTFail("Expected baseline Cmd+Shift+Down to reach the contenteditable fixture. data=\(String(describing: loadData()))")
            return
        }
        let baselineCommandShiftDownCount = Int(baselineCommandShiftDownSnapshot["browserContentEditableCommandShiftDownCount"] ?? "") ?? -1

        simulateShortcut("cmdShiftUp", app: app)
        guard let baselineCommandShiftUpSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableActiveElementId"] == editorId &&
                    data["browserContentEditableCommandShiftDownCount"] == "\(baselineCommandShiftDownCount)" &&
                    data["browserContentEditableCommandShiftUpCount"] == "\(initialCommandShiftUpCount + 1)"
            }
        ) else {
            XCTFail("Expected baseline Cmd+Shift+Up to reach the contenteditable fixture. data=\(String(describing: loadData()))")
            return
        }
        let baselineCommandShiftUpCount = Int(baselineCommandShiftUpSnapshot["browserContentEditableCommandShiftUpCount"] ?? "") ?? -1

        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["webViewFocusedAfterAddressBarFocus"] == "false"
            },
            "Expected Cmd+L to focus omnibar before the contenteditable click path"
        )

        window
            .coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0))
            .withOffset(CGVector(dx: editorClickOffsetX, dy: editorClickOffsetY))
            .click()

        guard waitForDataMatch(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableActiveElementId"] == editorId
            }
        ) else {
            XCTFail("Expected clicking the page to re-focus the contenteditable fixture after Cmd+L. data=\(String(describing: loadData()))")
            return
        }

        simulateShortcut("down", app: app)
        guard let postCmdLDownSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableActiveElementId"] == editorId &&
                    data["browserContentEditableDownCount"] == "\(baselineDownCount + 1)" &&
                    data["browserContentEditableUpCount"] == "\(baselineUpCount)" &&
                    data["browserContentEditableCommandShiftDownCount"] == "\(baselineCommandShiftDownCount)" &&
                    data["browserContentEditableCommandShiftUpCount"] == "\(baselineCommandShiftUpCount)"
            }
        ) else {
            XCTFail("Expected Down Arrow after Cmd+L to reach the contenteditable fixture. data=\(String(describing: loadData()))")
            return
        }
        let postCmdLDownCount = Int(postCmdLDownSnapshot["browserContentEditableDownCount"] ?? "") ?? -1

        simulateShortcut("up", app: app)
        guard let postCmdLUpSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableActiveElementId"] == editorId &&
                    data["browserContentEditableDownCount"] == "\(postCmdLDownCount)" &&
                    data["browserContentEditableUpCount"] == "\(baselineUpCount + 1)"
            }
        ) else {
            XCTFail("Expected Up Arrow after Cmd+L to reach the contenteditable fixture. data=\(String(describing: loadData()))")
            return
        }
        let postCmdLUpCount = Int(postCmdLUpSnapshot["browserContentEditableUpCount"] ?? "") ?? -1

        simulateShortcut("cmdShiftDown", app: app)
        guard let postCmdLCommandShiftDownSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableActiveElementId"] == editorId &&
                    data["browserContentEditableDownCount"] == "\(postCmdLDownCount)" &&
                    data["browserContentEditableUpCount"] == "\(postCmdLUpCount)" &&
                    data["browserContentEditableCommandShiftDownCount"] == "\(baselineCommandShiftDownCount + 1)" &&
                    data["browserContentEditableCommandShiftUpCount"] == "\(baselineCommandShiftUpCount)"
            }
        ) else {
            XCTFail("Expected Cmd+Shift+Down after Cmd+L to reach the contenteditable fixture. data=\(String(describing: loadData()))")
            return
        }
        let postCmdLCommandShiftDownCount = Int(postCmdLCommandShiftDownSnapshot["browserContentEditableCommandShiftDownCount"] ?? "") ?? -1

        simulateShortcut("cmdShiftUp", app: app)
        guard let postCmdLCommandShiftUpSnapshot = waitForDataSnapshot(
            timeout: 5.0,
            predicate: { data in
                data["browserContentEditableActiveElementId"] == editorId &&
                    data["browserContentEditableDownCount"] == "\(postCmdLDownCount)" &&
                    data["browserContentEditableUpCount"] == "\(postCmdLUpCount)" &&
                    data["browserContentEditableCommandShiftDownCount"] == "\(postCmdLCommandShiftDownCount)" &&
                    data["browserContentEditableCommandShiftUpCount"] == "\(baselineCommandShiftUpCount + 1)"
            }
        ) else {
            XCTFail("Expected Cmd+Shift+Up after Cmd+L to reach the contenteditable fixture. data=\(String(describing: loadData()))")
            return
        }

        XCTAssertEqual(
            postCmdLCommandShiftUpSnapshot["browserContentEditableActiveElementId"],
            editorId,
            "Expected the clicked contenteditable fixture to remain focused after Cmd+Shift+arrows"
        )
    }

    func testCmdLOpensBrowserWhenTerminalFocused() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["browserPanelId", "terminalPaneId", "webViewFocused"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        guard let originalBrowserPanelId = setup["browserPanelId"] else {
            XCTFail("Missing browserPanelId in goto_split setup data")
            return
        }

        guard let expectedTerminalPaneId = setup["terminalPaneId"] else {
            XCTFail("Missing terminalPaneId in goto_split setup data")
            return
        }

        // Move focus to the terminal pane first.
        app.typeKey("h", modifierFlags: [.command, .control])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["lastMoveDirection"] == "left" && data["focusedPaneId"] == expectedTerminalPaneId
            },
            "Expected Cmd+Ctrl+H to move focus to left pane (terminal)"
        )

        // Cmd+L should open a browser in the focused pane, then focus omnibar.
        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                guard data["webViewFocusedAfterAddressBarFocus"] == "false" else { return false }
                guard let focusedAddressPanelId = data["webViewFocusedAfterAddressBarFocusPanelId"] else { return false }
                return focusedAddressPanelId != originalBrowserPanelId
            },
            "Expected Cmd+L on terminal focus to open a new browser and focus omnibar"
        )
    }

    func testClickingOmnibarFocusesBrowserPane() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["browserPanelId", "terminalPaneId", "webViewFocused"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        guard let expectedBrowserPanelId = setup["browserPanelId"] else {
            XCTFail("Missing browserPanelId in goto_split setup data")
            return
        }

        guard let expectedTerminalPaneId = setup["terminalPaneId"] else {
            XCTFail("Missing terminalPaneId in goto_split setup data")
            return
        }

        // Move focus away from browser to terminal first.
        app.typeKey("h", modifierFlags: [.command, .control])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["lastMoveDirection"] == "left" && data["focusedPaneId"] == expectedTerminalPaneId
            },
            "Expected Cmd+Ctrl+H to move focus to left pane (terminal)"
        )

        let omnibar = app.textFields["BrowserOmnibarTextField"].firstMatch
        XCTAssertTrue(omnibar.waitForExistence(timeout: 6.0), "Expected browser omnibar text field")
        omnibar.click()

        // Cmd+L behavior is context-aware:
        // - If terminal is focused: opens a new browser and focuses that new omnibar.
        // - If browser is focused: focuses current browser omnibar.
        // After clicking the omnibar, Cmd+L should stay on the existing browser panel.
        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                guard data["webViewFocusedAfterAddressBarFocus"] == "false" else { return false }
                return data["webViewFocusedAfterAddressBarFocusPanelId"] == expectedBrowserPanelId
            },
            "Expected omnibar click to focus browser panel so Cmd+L stays on that browser"
        )
    }

    func testClickingBrowserDismissesCommandPaletteAndKeepsBrowserFocus() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["browserPanelId", "terminalPaneId", "webViewFocused"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        guard let expectedBrowserPanelId = setup["browserPanelId"] else {
            XCTFail("Missing browserPanelId in goto_split setup data")
            return
        }

        guard let expectedTerminalPaneId = setup["terminalPaneId"] else {
            XCTFail("Missing terminalPaneId in goto_split setup data")
            return
        }

        // Move focus away from browser to terminal first so Cmd+R opens the rename overlay.
        app.typeKey("h", modifierFlags: [.command, .control])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["lastMoveDirection"] == "left" && data["focusedPaneId"] == expectedTerminalPaneId
            },
            "Expected Cmd+Ctrl+H to move focus to left pane (terminal)"
        )

        let renameField = app.textFields["CommandPaletteRenameField"].firstMatch
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(
            renameField.waitForExistence(timeout: 5.0),
            "Expected Cmd+R to open the rename command palette while terminal is focused"
        )

        let browserPane = app.otherElements["BrowserPanelContent.\(expectedBrowserPanelId)"].firstMatch
        XCTAssertTrue(browserPane.waitForExistence(timeout: 5.0), "Expected browser pane content for click target")
        browserPane.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            waitForNonExistence(renameField, timeout: 5.0),
            "Expected clicking the browser pane to dismiss the command palette"
        )

        // Cmd+L behavior is context-aware:
        // - If terminal is still focused: opens a new browser in that pane.
        // - If the original browser took focus: focuses that existing browser's omnibar.
        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                guard data["webViewFocusedAfterAddressBarFocus"] == "false" else { return false }
                return data["webViewFocusedAfterAddressBarFocusPanelId"] == expectedBrowserPanelId
            },
            "Expected clicking browser content to dismiss the palette and keep focus on the existing browser pane"
        )
    }

    func testCmdDSplitsRightWhenWebViewFocused() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["webViewFocused", "initialPaneCount"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        XCTAssertEqual(setup["webViewFocused"], "true", "Expected WKWebView to be first responder for this test")
        let initialPaneCount = Int(setup["initialPaneCount"] ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(initialPaneCount, 2, "Expected at least two panes before split. data=\(setup)")

        app.typeKey("d", modifierFlags: [.command])

        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                guard data["lastSplitDirection"] == "right" else { return false }
                guard let paneCountAfter = Int(data["paneCountAfterSplit"] ?? "") else { return false }
                return paneCountAfter == initialPaneCount + 1
            },
            "Expected Cmd+D to split right while WKWebView is first responder"
        )
    }

    func testCmdShiftDSplitsDownWhenWebViewFocused() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["webViewFocused", "initialPaneCount"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        XCTAssertEqual(setup["webViewFocused"], "true", "Expected WKWebView to be first responder for this test")
        let initialPaneCount = Int(setup["initialPaneCount"] ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(initialPaneCount, 2, "Expected at least two panes before split. data=\(setup)")

        app.typeKey("d", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                guard data["lastSplitDirection"] == "down" else { return false }
                guard let paneCountAfter = Int(data["paneCountAfterSplit"] ?? "") else { return false }
                return paneCountAfter == initialPaneCount + 1
            },
            "Expected Cmd+Shift+D to split down while WKWebView is first responder"
        )
    }

    func testCmdShiftEnterKeepsBrowserOmnibarHittableAcrossZoomRoundTripWhenWebViewFocused() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["browserPanelId", "webViewFocused"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        guard let browserPanelId = setup["browserPanelId"] else {
            XCTFail("Missing browserPanelId in goto_split setup data")
            return
        }

        XCTAssertEqual(setup["webViewFocused"], "true", "Expected WKWebView to be first responder for this test")

        let omnibar = app.textFields["BrowserOmnibarTextField"].firstMatch
        let pill = app.descendants(matching: .any).matching(identifier: "BrowserOmnibarPill").firstMatch
        XCTAssertTrue(omnibar.waitForExistence(timeout: 6.0), "Expected browser omnibar text field before zoom")
        XCTAssertTrue(pill.waitForExistence(timeout: 6.0), "Expected browser omnibar pill before zoom")

        // Reproduce the loaded-page state from the bug report before toggling zoom.
        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(waitForElementToBecomeHittable(pill, timeout: 6.0), "Expected browser omnibar pill before navigation")
        pill.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        app.typeText(zoomRoundTripPageURL)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(
            waitForOmnibarToContain(omnibar, value: "data:text/html", timeout: 8.0),
            "Expected browser to finish navigating to the regression page before zoom. value=\(String(describing: omnibar.value))"
        )

        let browserPane = app.otherElements["BrowserPanelContent.\(browserPanelId)"].firstMatch
        XCTAssertTrue(browserPane.waitForExistence(timeout: 6.0), "Expected browser pane content before zoom")
        browserPane.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForDataMatch(timeout: 8.0) { data in
                data["splitZoomedAfterToggle"] == "true" &&
                    data["otherTerminalHostHiddenAfterToggle"] == "true" &&
                    data["otherTerminalVisibleFlagAfterToggle"] == "false"
            },
            "Expected Cmd+Shift+Enter zoom-in to hide the non-browser terminal portal. data=\(loadData() ?? [:])"
        )
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForDataMatch(timeout: 8.0) { data in
                data["splitZoomedAfterToggle"] == "false" &&
                    data["otherTerminalHostHiddenAfterToggle"] == "false" &&
                    data["otherTerminalVisibleFlagAfterToggle"] == "true"
            },
            "Expected Cmd+Shift+Enter zoom-out to restore the non-browser terminal portal. data=\(loadData() ?? [:])"
        )

        XCTAssertTrue(omnibar.waitForExistence(timeout: 6.0), "Expected browser omnibar text field after Cmd+Shift+Enter zoom round-trip")
        XCTAssertTrue(pill.waitForExistence(timeout: 6.0), "Expected browser omnibar pill after Cmd+Shift+Enter zoom round-trip")
        XCTAssertTrue(
            waitForElementToBecomeHittable(pill, timeout: 6.0),
            "Expected browser omnibar to stay hittable after Cmd+Shift+Enter zoom round-trip"
        )
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 6.0), "Expected browser web area after Cmd+Shift+Enter")
        XCTAssertLessThanOrEqual(
            pill.frame.maxY,
            page.frame.minY + 12,
            "Expected browser omnibar to remain above the web content after Cmd+Shift+Enter. pill=\(pill.frame) page=\(page.frame)"
        )

        pill.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        app.typeText("issue1144")

        XCTAssertTrue(
            waitForOmnibarToContain(omnibar, value: "issue1144", timeout: 4.0),
            "Expected browser omnibar to stay editable after Cmd+Shift+Enter. value=\(String(describing: omnibar.value))"
        )
    }

    func testCmdShiftEnterHidesBrowserPortalWhenTerminalPaneZooms() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["terminalPaneId", "browserPanelId", "webViewFocused"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        guard let expectedTerminalPaneId = setup["terminalPaneId"] else {
            XCTFail("Missing terminalPaneId in goto_split setup data")
            return
        }

        app.typeKey("h", modifierFlags: [.command, .control])

        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["focusedPaneId"] == expectedTerminalPaneId && data["focusedPanelKind"] == "terminal"
            },
            "Expected Cmd+Ctrl+H to focus the terminal pane before zoom. data=\(loadData() ?? [:])"
        )

        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForDataMatch(timeout: 8.0) { data in
                data["splitZoomedAfterToggle"] == "true" &&
                    data["browserContainerHiddenAfterToggle"] == "true" &&
                    data["browserVisibleFlagAfterToggle"] == "false"
            },
            "Expected Cmd+Shift+Enter zoom-in on the terminal pane to hide the browser portal. data=\(loadData() ?? [:])"
        )

        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForDataMatch(timeout: 8.0) { data in
                data["splitZoomedAfterToggle"] == "false" &&
                    data["browserContainerHiddenAfterToggle"] == "false" &&
                    data["browserVisibleFlagAfterToggle"] == "true"
            },
            "Expected Cmd+Shift+Enter zoom-out from the terminal pane to restore the browser portal. data=\(loadData() ?? [:])"
        )
    }

    func testCmdDSplitsRightWhenOmnibarFocused() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["webViewFocused", "initialPaneCount"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        let initialPaneCount = Int(setup["initialPaneCount"] ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(initialPaneCount, 2, "Expected at least two panes before split. data=\(setup)")

        // Focus browser omnibar (WebKit no longer first responder).
        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["webViewFocusedAfterAddressBarFocus"] == "false"
            },
            "Expected Cmd+L to focus omnibar before split"
        )

        app.typeKey("d", modifierFlags: [.command])

        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                guard data["lastSplitDirection"] == "right" else { return false }
                guard let paneCountAfter = Int(data["paneCountAfterSplit"] ?? "") else { return false }
                return paneCountAfter == initialPaneCount + 1
            },
            "Expected Cmd+D to split right while omnibar is first responder"
        )
    }

    func testCmdShiftDSplitsDownWhenOmnibarFocused() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        launchAndEnsureForeground(app)

        XCTAssertTrue(
            waitForData(keys: ["webViewFocused", "initialPaneCount"], timeout: 10.0),
            "Expected goto_split setup data to be written"
        )

        guard let setup = loadData() else {
            XCTFail("Missing goto_split setup data")
            return
        }

        let initialPaneCount = Int(setup["initialPaneCount"] ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(initialPaneCount, 2, "Expected at least two panes before split. data=\(setup)")

        // Focus browser omnibar (WebKit no longer first responder).
        app.typeKey("l", modifierFlags: [.command])
        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                data["webViewFocusedAfterAddressBarFocus"] == "false"
            },
            "Expected Cmd+L to focus omnibar before split"
        )

        app.typeKey("d", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            waitForDataMatch(timeout: 5.0) { data in
                guard data["lastSplitDirection"] == "down" else { return false }
                guard let paneCountAfter = Int(data["paneCountAfterSplit"] ?? "") else { return false }
                return paneCountAfter == initialPaneCount + 1
            },
            "Expected Cmd+Shift+D to split down while omnibar is first responder"
        )
    }

    func testCmdOptionPaneSwitchPreservesFindFieldFocus() {
        runFindFocusPersistenceScenario(route: .cmdOptionArrows, useAutofocusRacePage: false)
    }

    func testCmdCtrlPaneSwitchPreservesFindFieldFocus() {
        runFindFocusPersistenceScenario(route: .cmdCtrlLetters, useAutofocusRacePage: false)
    }

    func testCmdOptionPaneSwitchPreservesFindFieldFocusDuringPageAutofocusRace() {
        runFindFocusPersistenceScenario(route: .cmdOptionArrows, useAutofocusRacePage: true)
    }

    private enum FindFocusRoute {
        case cmdOptionArrows
        case cmdCtrlLetters
    }

    private func runFindFocusPersistenceScenario(route: FindFocusRoute, useAutofocusRacePage: Bool) {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_RECORD_ONLY"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = dataPath
        if route == .cmdCtrlLetters {
            app.launchEnvironment["CMUX_UI_TEST_FOCUS_SHORTCUTS"] = "1"
        }
        launchAndEnsureForeground(app)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10.0), "Expected main window to exist")

        // Repro setup: split, open browser split, navigate to example.com.
        app.typeKey("d", modifierFlags: [.command])
        focusRightPaneForFindScenario(app, route: route)

        app.typeKey("l", modifierFlags: [.command, .shift])
        let omnibar = app.textFields["BrowserOmnibarTextField"].firstMatch
        XCTAssertTrue(omnibar.waitForExistence(timeout: 8.0), "Expected browser omnibar after Cmd+Shift+L")

        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        if useAutofocusRacePage {
            app.typeText(autofocusRacePageURL)
        } else {
            app.typeText("example.com")
        }
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        if useAutofocusRacePage {
            XCTAssertTrue(
                waitForOmnibarToContain(omnibar, value: "data:text/html", timeout: 8.0),
                "Expected browser navigation to data URL before running find flow. value=\(String(describing: omnibar.value))"
            )
        } else {
            XCTAssertTrue(
                waitForOmnibarToContainExampleDomain(omnibar, timeout: 8.0),
                "Expected browser navigation to example domain before running find flow. value=\(String(describing: omnibar.value))"
            )
        }

        // Left terminal: Cmd+F then type "la".
        focusLeftPaneForFindScenario(app, route: route)
        XCTAssertTrue(
            waitForDataMatch(timeout: 6.0) { data in
                data["focusedPanelKind"] == "terminal"
            },
            "Expected left terminal pane to be focused before terminal find. data=\(String(describing: loadData()))"
        )
        app.typeKey("f", modifierFlags: [.command])
        app.typeText("la")

        // Right browser: Cmd+F then type "am".
        focusRightPaneForFindScenario(app, route: route)
        XCTAssertTrue(
            waitForDataMatch(timeout: 6.0) { data in
                data["lastMoveDirection"] == "right"
                    && data["focusedPanelKind"] == "browser"
                    && data["terminalFindNeedle"] == "la"
            },
            "Expected terminal find query to persist as 'la' after focusing browser pane. data=\(String(describing: loadData()))"
        )
        app.typeKey("f", modifierFlags: [.command])
        app.typeText("am")

        if useAutofocusRacePage {
            XCTAssertTrue(
                waitForOmnibarToContain(omnibar, value: "#focused", timeout: 5.0),
                "Expected autofocus race page to signal focus handoff via URL hash. value=\(String(describing: omnibar.value))"
            )
        }

        // Left terminal: typing should keep going into terminal find field.
        focusLeftPaneForFindScenario(app, route: route)
        XCTAssertTrue(
            waitForDataMatch(timeout: 6.0) { data in
                data["lastMoveDirection"] == "left"
                    && data["focusedPanelKind"] == "terminal"
                    && data["browserFindNeedle"] == "am"
            },
            "Expected browser find query to persist as 'am' after returning left. data=\(String(describing: loadData()))"
        )
        app.typeText("foo")

        // Right browser: typing should keep going into browser find field.
        focusRightPaneForFindScenario(app, route: route)
        XCTAssertTrue(
            waitForDataMatch(timeout: 6.0) { data in
                data["lastMoveDirection"] == "right"
                    && data["focusedPanelKind"] == "browser"
                    && data["terminalFindNeedle"] == "lafoo"
            },
            "Expected terminal find query to stay focused and become 'lafoo'. data=\(String(describing: loadData()))"
        )
        app.typeText("do")

        // Move left once more so the recorder captures browser find state after typing.
        focusLeftPaneForFindScenario(app, route: route)
        XCTAssertTrue(
            waitForDataMatch(timeout: 6.0) { data in
                data["lastMoveDirection"] == "left"
                    && data["focusedPanelKind"] == "terminal"
                    && data["browserFindNeedle"] == "amdo"
            },
            "Expected browser find query to stay focused and become 'amdo'. data=\(String(describing: loadData()))"
        )
    }

    private func focusLeftPaneForFindScenario(_ app: XCUIApplication, route: FindFocusRoute) {
        switch route {
        case .cmdOptionArrows:
            app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: [.command, .option])
        case .cmdCtrlLetters:
            app.typeKey("h", modifierFlags: [.command, .control])
        }
    }

    private func focusRightPaneForFindScenario(_ app: XCUIApplication, route: FindFocusRoute) {
        switch route {
        case .cmdOptionArrows:
            app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [.command, .option])
        case .cmdCtrlLetters:
            app.typeKey("l", modifierFlags: [.command, .control])
        }
    }

    private func waitForOmnibarToContainExampleDomain(_ omnibar: XCUIElement, timeout: TimeInterval) -> Bool {
        waitForCondition(timeout: timeout) {
            let value = (omnibar.value as? String) ?? ""
            return value.contains("example.com") || value.contains("example.org")
        }
    }

    private func waitForOmnibarToContain(_ omnibar: XCUIElement, value expectedSubstring: String, timeout: TimeInterval) -> Bool {
        waitForCondition(timeout: timeout) {
            let value = (omnibar.value as? String) ?? ""
            return value.contains(expectedSubstring)
        }
    }

    private func waitForElementToBecomeHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        waitForCondition(timeout: timeout) {
            element.exists && element.isHittable
        }
    }

    private var autofocusRacePageURL: String {
        "data:text/html,%3Cinput%20id%3D%22q%22%3E%3Cscript%3EsetTimeout%28function%28%29%7Bdocument.getElementById%28%22q%22%29.focus%28%29%3Blocation.hash%3D%22focused%22%3B%7D%2C700%29%3B%3C%2Fscript%3E"
    }

    private var zoomRoundTripPageURL: String {
        "data:text/html,%3Ctitle%3EIssue%201144%3C/title%3E%3Cbody%20style%3D%22margin:0;background:%231d1f24;color:white;font-family:system-ui;height:2200px%22%3E%3Cmain%20style%3D%22padding:32px%22%3E%3Ch1%3EIssue%201144%20Regression%20Page%3C/h1%3E%3Cp%3EZoom%20should%20not%20leave%20stale%20split%20chrome%20above%20the%20browser%20omnibar.%3C/p%3E%3C/main%3E%3C/body%3E"
    }

    private func launchAndEnsureForeground(_ app: XCUIApplication, timeout: TimeInterval = 12.0) {
        prepareLaunchEnvironment(app)
        app.launch()
        XCTAssertTrue(
            ensureForegroundAfterLaunch(app, timeout: timeout),
            "Expected app to launch in foreground. state=\(app.state.rawValue)"
        )
    }

    private func prepareLaunchEnvironment(_ app: XCUIApplication) {
        if app.launchEnvironment["CMUX_UI_TEST_MODE"] == nil {
            app.launchEnvironment["CMUX_UI_TEST_MODE"] = "1"
        }
        if app.launchEnvironment["CMUX_TAG"] == nil {
            app.launchEnvironment["CMUX_TAG"] = launchTag
        }
        if app.launchEnvironment["CMUX_UI_TEST_DIAGNOSTICS_PATH"] == nil {
            app.launchEnvironment["CMUX_UI_TEST_DIAGNOSTICS_PATH"] = launchDiagnosticsPath
        }
        if app.launchEnvironment["CMUX_SOCKET_PATH"] != nil,
           app.launchEnvironment["CMUX_UI_TEST_SOCKET_SANITY"] == nil {
            app.launchEnvironment["CMUX_UI_TEST_SOCKET_SANITY"] = "1"
        }
        if app.launchEnvironment["CMUX_SOCKET_PATH"] != nil {
            if app.launchEnvironment["CMUX_ALLOW_SOCKET_OVERRIDE"] == nil {
                app.launchEnvironment["CMUX_ALLOW_SOCKET_OVERRIDE"] = "1"
            }
            if !app.launchArguments.contains("-socketControlMode") {
                app.launchArguments += ["-socketControlMode", "allowAll"]
            }
            if app.launchEnvironment["CMUX_SOCKET_ENABLE"] == nil {
                app.launchEnvironment["CMUX_SOCKET_ENABLE"] = "1"
            }
            if app.launchEnvironment["CMUX_SOCKET_MODE"] == nil {
                app.launchEnvironment["CMUX_SOCKET_MODE"] = "allowAll"
            }
        }
    }

    private func ensureForegroundAfterLaunch(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        if app.wait(for: .runningForeground, timeout: timeout) {
            return true
        }

        let activationDeadline = Date().addingTimeInterval(12.0)
        while app.state == .runningBackground && Date() < activationDeadline {
            app.activate()
            if app.wait(for: .runningForeground, timeout: 2.0) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return app.state == .runningForeground
    }

    private func waitForData(keys: [String], timeout: TimeInterval) -> Bool {
        waitForCondition(timeout: timeout) {
            guard let data = self.loadData() else { return false }
            return keys.allSatisfy { data[$0] != nil }
        }
    }

    private func waitForDataMatch(timeout: TimeInterval, predicate: @escaping ([String: String]) -> Bool) -> Bool {
        waitForCondition(timeout: timeout) {
            guard let data = self.loadData() else { return false }
            return predicate(data)
        }
    }

    private func waitForDataSnapshot(
        timeout: TimeInterval,
        predicate: @escaping ([String: String]) -> Bool
    ) -> [String: String]? {
        var matched: [String: String]?
        let didMatch = waitForCondition(timeout: timeout) {
            guard let data = self.loadData(), predicate(data) else { return false }
            matched = data
            return true
        }
        return didMatch ? matched : nil
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func simulateShortcut(_ combo: String, app: XCUIApplication) {
        switch combo {
        case "down":
            app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])
        case "up":
            app.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: [])
        case "cmdShiftDown":
            app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [.command, .shift])
        case "cmdShiftUp":
            app.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: [.command, .shift])
        default:
            XCTFail("Unsupported test shortcut combo \(combo)")
        }
    }

    private func loadData() -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dataPath)) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
    }

    private struct BrowserArrowReport: CustomStringConvertible {
        let down: Int
        let up: Int
        let active: String
        let selectionStart: Int?
        let selectionEnd: Int?

        var description: String {
            "BrowserArrowReport(down: \(down), up: \(up), active: \(active), selectionStart: \(selectionStart.map(String.init) ?? "nil"), selectionEnd: \(selectionEnd.map(String.init) ?? "nil"))"
        }
    }

    private struct BrowserArrowHarness {
        let report: BrowserArrowReport
        let primaryInputId: String
        let secondaryInputId: String
        let secondaryCenterX: Double
        let secondaryCenterY: Double
    }

    private struct BrowserArrowHarnessInstallResult {
        let harness: BrowserArrowHarness?
        let diagnostic: String
    }

    private func installBrowserArrowHarness(surfaceId: String) -> BrowserArrowHarnessInstallResult {
        let readyResult = browserWaitForArrowHarness(surfaceId: surfaceId)
        guard readyResult.terminationStatus == 0 else {
            return BrowserArrowHarnessInstallResult(
                harness: nil,
                diagnostic: "browser wait failed with status=\(readyResult.terminationStatus) stdout=\(readyResult.stdout) stderr=\(readyResult.stderr)"
            )
        }

        let script = """
        (() => {
          const root = document.body || document.documentElement;
          if (!root) {
            return JSON.stringify({ error: "missing-root" });
          }
          const ensureInput = (id, value) => {
            const existing = document.getElementById(id);
            const input = (existing && existing.tagName && existing.tagName.toLowerCase() === "input")
              ? existing
              : (() => {
                  const created = document.createElement("input");
                  created.id = id;
                  created.type = "text";
                  created.value = value;
                  return created;
                })();
            input.autocapitalize = "off";
            input.autocomplete = "off";
            input.spellcheck = false;
            input.style.display = "block";
            input.style.width = "100%";
            input.style.margin = "0";
            input.style.padding = "8px 10px";
            input.style.border = "1px solid #5f6368";
            input.style.borderRadius = "6px";
            input.style.boxSizing = "border-box";
            input.style.fontSize = "14px";
            input.style.fontFamily = "system-ui, -apple-system, sans-serif";
            input.style.background = "white";
            input.style.color = "black";
            return input;
          };
          let container = document.getElementById("cmux-ui-test-arrow-container");
          if (!container || !container.tagName || container.tagName.toLowerCase() !== "div") {
            container = document.createElement("div");
            container.id = "cmux-ui-test-arrow-container";
            root.appendChild(container);
          }
          container.style.position = "fixed";
          container.style.left = "24px";
          container.style.top = "24px";
          container.style.width = "min(520px, calc(100vw - 48px))";
          container.style.display = "grid";
          container.style.rowGap = "12px";
          container.style.padding = "12px";
          container.style.background = "rgba(255,255,255,0.92)";
          container.style.border = "1px solid rgba(95,99,104,0.55)";
          container.style.borderRadius = "8px";
          container.style.boxShadow = "0 2px 10px rgba(0,0,0,0.2)";
          container.style.zIndex = "2147483647";
          const primary = ensureInput("cmux-ui-test-arrow-input-primary", "cmux-ui-arrow-primary");
          const secondary = ensureInput("cmux-ui-test-arrow-input-secondary", "cmux-ui-arrow-secondary");
          if (primary.parentElement !== container) {
            container.appendChild(primary);
          }
          if (secondary.parentElement !== container) {
            container.appendChild(secondary);
          }
          if (!window.__cmuxArrowKeyReport) {
            window.__cmuxArrowKeyReport = { down: 0, up: 0 };
          }
          const updateSelection = () => {
            const active = document.activeElement;
            return {
              down: window.__cmuxArrowKeyReport.down,
              up: window.__cmuxArrowKeyReport.up,
              active: active && typeof active.id === "string" ? active.id : "",
              selectionStart: active && typeof active.selectionStart === "number" ? active.selectionStart : null,
              selectionEnd: active && typeof active.selectionEnd === "number" ? active.selectionEnd : null
            };
          };
          const install = (element) => {
            if (!element || element.__cmuxArrowKeyReportInstalled) return;
            element.__cmuxArrowKeyReportInstalled = true;
            element.addEventListener("keydown", (event) => {
              if (event.key === "ArrowDown") window.__cmuxArrowKeyReport.down += 1;
              if (event.key === "ArrowUp") window.__cmuxArrowKeyReport.up += 1;
            }, true);
          };
          install(primary);
          install(secondary);
          primary.focus({ preventScroll: true });
          if (typeof primary.setSelectionRange === "function") {
            const end = primary.value.length;
            primary.setSelectionRange(end, end);
          }
          const secondaryRect = secondary.getBoundingClientRect();
          const viewportWidth = Math.max(Number(window.innerWidth) || 0, 1);
          const viewportHeight = Math.max(Number(window.innerHeight) || 0, 1);
          const secondaryCenterX = Math.min(
            0.98,
            Math.max(0.02, (secondaryRect.left + (secondaryRect.width / 2)) / viewportWidth)
          );
          const secondaryCenterY = Math.min(
            0.98,
            Math.max(0.02, (secondaryRect.top + (secondaryRect.height / 2)) / viewportHeight)
          );
          const base = updateSelection();
          window.cmuxArrowReport = () => updateSelection();
          return JSON.stringify({
            down: base.down,
            up: base.up,
            active: base.active,
            selectionStart: base.selectionStart,
            selectionEnd: base.selectionEnd,
            primaryId: primary.id || "",
            secondaryId: secondary.id || "",
            secondaryCenterX,
            secondaryCenterY
          });
        })();
        """
        guard let evalOutput = browserEval(surfaceId: surfaceId, script: script) else {
            return BrowserArrowHarnessInstallResult(
                harness: nil,
                diagnostic: "browser eval failed via control socket"
            )
        }
        guard !evalOutput.isEmpty else {
            return BrowserArrowHarnessInstallResult(
                harness: nil,
                diagnostic: "browser eval returned empty payload"
            )
        }
        guard let data = evalOutput.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return BrowserArrowHarnessInstallResult(
                harness: nil,
                diagnostic: "browser eval returned non-JSON payload=\(evalOutput)"
            )
        }

        let primaryInputId = (payload["primaryId"] as? String) ?? ""
        let secondaryInputId = (payload["secondaryId"] as? String) ?? ""
        let secondaryCenterX = (payload["secondaryCenterX"] as? NSNumber)?.doubleValue ?? -1
        let secondaryCenterY = (payload["secondaryCenterY"] as? NSNumber)?.doubleValue ?? -1
        guard !primaryInputId.isEmpty,
              !secondaryInputId.isEmpty,
              secondaryCenterX > 0,
              secondaryCenterX < 1,
              secondaryCenterY > 0,
              secondaryCenterY < 1 else {
            return BrowserArrowHarnessInstallResult(
                harness: nil,
                diagnostic: "browser eval returned incomplete payload=\(payload)"
            )
        }

        return BrowserArrowHarnessInstallResult(
            harness: BrowserArrowHarness(
                report: BrowserArrowReport(
                    down: (payload["down"] as? NSNumber)?.intValue ?? 0,
                    up: (payload["up"] as? NSNumber)?.intValue ?? 0,
                    active: (payload["active"] as? String) ?? "",
                    selectionStart: (payload["selectionStart"] as? NSNumber)?.intValue,
                    selectionEnd: (payload["selectionEnd"] as? NSNumber)?.intValue
                ),
                primaryInputId: primaryInputId,
                secondaryInputId: secondaryInputId,
                secondaryCenterX: secondaryCenterX,
                secondaryCenterY: secondaryCenterY
            ),
            diagnostic: "ok"
        )
    }

    private func browserWaitForArrowHarness(surfaceId: String) -> (terminationStatus: Int32, stdout: String, stderr: String) {
        var lastValue = "nil"
        let didBecomeReady = waitForCondition(timeout: 8.0) {
            guard let value = self.browserEval(
                surfaceId: surfaceId,
                script: """
                (() => {
                  const ready = String(document.readyState || '') === 'complete';
                  const hasRoot = !!(document.body || document.documentElement);
                  return ready && hasRoot ? '1' : '0';
                })()
                """
            ) else {
                lastValue = "nil"
                return false
            }
            lastValue = value
            return value == "1"
        }
        if didBecomeReady {
            return (terminationStatus: 0, stdout: lastValue, stderr: "")
        }
        return (terminationStatus: 1, stdout: lastValue, stderr: "DOM readiness check did not pass")
    }

    private func waitForBrowserArrowReport(
        surfaceId: String,
        timeout: TimeInterval,
        predicate: @escaping (BrowserArrowReport) -> Bool
    ) -> BrowserArrowReport? {
        var matchedReport: BrowserArrowReport?
        let didMatch = waitForCondition(timeout: timeout) {
            guard let report = self.browserArrowReport(surfaceId: surfaceId) else {
                return false
            }
            guard predicate(report) else { return false }
            matchedReport = report
            return true
        }
        return didMatch ? matchedReport : nil
    }

    private func browserArrowReport(surfaceId: String, script: String? = nil) -> BrowserArrowReport? {
        let reportScript = script ?? "JSON.stringify(window.cmuxArrowReport ? window.cmuxArrowReport() : null)"
        guard let raw = browserEval(surfaceId: surfaceId, script: reportScript),
              let data = raw.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return BrowserArrowReport(
            down: (payload["down"] as? NSNumber)?.intValue ?? 0,
            up: (payload["up"] as? NSNumber)?.intValue ?? 0,
            active: (payload["active"] as? String) ?? "",
            selectionStart: (payload["selectionStart"] as? NSNumber)?.intValue,
            selectionEnd: (payload["selectionEnd"] as? NSNumber)?.intValue
        )
    }

    private func browserEval(surfaceId: String, script: String) -> String? {
        guard let response = browserSocketJSON(
            method: "browser.eval",
            params: [
                "surface_id": surfaceId,
                "script": script
            ]
        )
        else {
            return nil
        }
        guard (response["ok"] as? Bool) == true,
              let result = response["result"] as? [String: Any],
              let value = result["value"] else {
            return nil
        }
        if value is NSNull {
            return "null"
        }
        if let stringValue = value as? String {
            return stringValue
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return json
    }

    private func browserSocketJSON(
        method: String,
        params: [String: Any],
        responseTimeout: TimeInterval = 8.0
    ) -> [String: Any]? {
        let request: [String: Any] = [
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]
        return ControlSocketClient(path: socketPath, responseTimeout: responseTimeout).sendJSON(request)
    }

    private func browserSocketErrorDescription(_ response: [String: Any]) -> String {
        guard let error = response["error"] as? [String: Any] else {
            return "Unknown error"
        }
        let code = (error["code"] as? String) ?? "unknown"
        let message = (error["message"] as? String) ?? "missing message"
        if let data = error["data"],
           JSONSerialization.isValidJSONObject(data),
           let encoded = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: encoded, encoding: .utf8) {
            return "\(code): \(message) data=\(json)"
        }
        return "\(code): \(message)"
    }

    private func browserSocketResultDescription(_ response: [String: Any]) -> String? {
        guard let result = response["result"] else { return nil }
        guard JSONSerialization.isValidJSONObject(result),
              let data = try? JSONSerialization.data(withJSONObject: result),
              let json = String(data: data, encoding: .utf8) else {
            return String(describing: result)
        }
        return json
    }

    private func javaScriptLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let arrayLiteral = String(data: data, encoding: .utf8),
              arrayLiteral.count >= 2 else {
            return "null"
        }
        return String(arrayLiteral.dropFirst().dropLast())
    }

    private func waitForCondition(timeout: TimeInterval, predicate: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in predicate() },
            object: nil
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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

            var socketTimeout = timeval(
                tv_sec: Int(responseTimeout.rounded(.down)),
                tv_usec: Int32(((responseTimeout - floor(responseTimeout)) * 1_000_000).rounded())
            )

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
            _ = withUnsafePointer(to: &socketTimeout) { ptr in
                setsockopt(
                    fd,
                    SOL_SOCKET,
                    SO_RCVTIMEO,
                    ptr,
                    socklen_t(MemoryLayout<timeval>.size)
                )
            }
            _ = withUnsafePointer(to: &socketTimeout) { ptr in
                setsockopt(
                    fd,
                    SOL_SOCKET,
                    SO_SNDTIMEO,
                    ptr,
                    socklen_t(MemoryLayout<timeval>.size)
                )
            }

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
            let payloadBytes = Array(payload.utf8)
            let written = payloadBytes.withUnsafeBytes { bytes -> ssize_t in
                guard let baseAddress = bytes.baseAddress else { return -1 }
                return send(fd, baseAddress, payloadBytes.count, 0)
            }
            guard written == payloadBytes.count else { return nil }

            var buffer = [UInt8](repeating: 0, count: 4096)
            var response = Data()
            while true {
                let count = recv(fd, &buffer, buffer.count, 0)
                if count <= 0 { break }
                response.append(buffer, count: count)
                if buffer[..<count].contains(UInt8(ascii: "\n")) {
                    break
                }
            }

            guard !response.isEmpty,
                  let raw = String(data: response, encoding: .utf8) else {
                return nil
            }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

}
