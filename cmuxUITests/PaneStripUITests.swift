import XCTest
import Foundation

private func paneStripPollUntil(
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

final class PaneStripUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testInitialTerminalIsVisible() {
        let payload = runPaneStripScenario("initial_terminal_visible")
        assertPassingPaneStripPayload(payload, scenario: "initial_terminal_visible")
    }

    func testInitialTerminalRendersAfterInput() {
        let payload = runPaneStripScenario("initial_terminal_renders_after_input")
        assertPassingPaneStripPayload(payload, scenario: "initial_terminal_renders_after_input")
    }

    func testInitialTerminalRecoversAfterLateActivation() {
        let payload = runPaneStripScenario("initial_terminal_recovers_after_late_activation")
        assertPassingPaneStripPayload(payload, scenario: "initial_terminal_recovers_after_late_activation")
    }

    func testFocusRevealRightKeepsTerminalsVisibleAndAligned() {
        let payload = runPaneStripScenario("focus_reveal_right")
        assertPassingPaneStripPayload(payload, scenario: "focus_reveal_right")
    }

    func testViewportPanRightKeepsTerminalsVisibleAndAligned() {
        let payload = runPaneStripScenario("pan_viewport_right")
        assertPassingPaneStripPayload(payload, scenario: "pan_viewport_right")
    }

    func testOpenPaneRightKeepsTerminalsVisibleAndNonOverlapping() {
        let payload = runPaneStripScenario("open_pane_right")
        assertPassingPaneStripPayload(payload, scenario: "open_pane_right")
    }

    func testBrowserFocusRevealRightKeepsBrowserAlignedWithPaneMotion() {
        let payload = runPaneStripScenario("browser_focus_reveal_right")
        assertPassingPaneStripPayload(payload, scenario: "browser_focus_reveal_right")
    }

    @discardableResult
    private func runPaneStripScenario(_ scenario: String, frameCount: Int = 24) -> [String: String] {
        let app = XCUIApplication()
        let dataPath = "/tmp/cmux-ui-test-pane-strip-\(scenario)-\(UUID().uuidString).json"
        let diagnosticsPath = "/tmp/cmux-ui-test-pane-strip-diag-\(scenario)-\(UUID().uuidString).json"
        try? FileManager.default.removeItem(atPath: dataPath)
        try? FileManager.default.removeItem(atPath: diagnosticsPath)

        app.launchEnvironment["CMUX_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_DIAGNOSTICS_PATH"] = diagnosticsPath
        app.launchEnvironment["CMUX_UI_TEST_PANE_STRIP_MOTION_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_PANE_STRIP_MOTION_PATH"] = dataPath
        app.launchEnvironment["CMUX_UI_TEST_PANE_STRIP_MOTION_SCENARIO"] = scenario
        app.launchEnvironment["CMUX_UI_TEST_PANE_STRIP_MOTION_FRAME_COUNT"] = String(frameCount)
        if scenario == "initial_terminal_recovers_after_late_activation" {
            app.launchEnvironment["CMUX_UI_TEST_PANE_STRIP_LAUNCH_MODE"] = "hide_then_reactivate"
        }
        launchAndActivate(app)
        defer {
            if app.state != .notRunning {
                app.terminate()
            }
        }

        guard let payload = waitForJSONKey("done", equals: "1", atPath: dataPath, timeout: 20.0) else {
            XCTFail(
                "Timed out waiting for pane-strip motion output for \(scenario). " +
                "data=\(loadJSON(atPath: dataPath) ?? [:]) diagnostics=\(loadJSON(atPath: diagnosticsPath) ?? [:])"
            )
            return [:]
        }

        attachScreenshot(named: "pane-strip-\(scenario)")
        attachPayload(payload, named: "pane-strip-\(scenario)-payload")
        return payload
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachPayload(_ payload: [String: String], named name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertPassingPaneStripPayload(_ payload: [String: String], scenario: String) {
        if let setupError = payload["setupError"], !setupError.isEmpty {
            XCTFail("\(scenario) setup failed: \(setupError). payload=\(payload)")
            return
        }

        XCTAssertEqual(payload["status"], "ok", "\(scenario) should finish with ok status. payload=\(payload)")
        XCTAssertEqual(payload["visibilityFailureSeen"], "0", "\(scenario) reported a visibility failure. payload=\(payload)")
        XCTAssertEqual(payload["alignmentFailureSeen"], "0", "\(scenario) reported an alignment failure. payload=\(payload)")
        XCTAssertEqual(payload["hostedOverlapFailureSeen"], "0", "\(scenario) reported hosted overlap. payload=\(payload)")
        XCTAssertEqual(payload["occlusionFailureSeen"], "0", "\(scenario) reported hit-test occlusion. payload=\(payload)")
        XCTAssertEqual(payload["blankFrameSeen"], "0", "\(scenario) reported a blank frame. payload=\(payload)")
        XCTAssertEqual(payload["sizeMismatchSeen"], "0", "\(scenario) reported an IOSurface size mismatch. payload=\(payload)")
    }

    private func waitForJSONKey(
        _ key: String,
        equals expected: String,
        atPath path: String,
        timeout: TimeInterval
    ) -> [String: String]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = loadJSON(atPath: path), data[key] == expected {
                return data
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if let data = loadJSON(atPath: path), data[key] == expected {
            return data
        }

        return nil
    }

    private func loadJSON(atPath path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return object
    }

    private func launchAndActivate(_ app: XCUIApplication, activateTimeout: TimeInterval = 12.0) {
        app.launch()
        XCTAssertTrue(
            ensureForegroundAfterLaunch(app, timeout: activateTimeout),
            "App did not reach runningForeground before pane-strip capture. state=\(app.state.rawValue)"
        )
    }

    private func ensureForegroundAfterLaunch(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        if app.wait(for: .runningForeground, timeout: timeout) {
            return true
        }
        if app.state == .runningBackground {
            app.activate()
            return app.wait(for: .runningForeground, timeout: 6.0)
        }
        return false
    }
}
