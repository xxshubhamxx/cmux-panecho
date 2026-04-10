import XCTest
import Foundation

final class LatestMacOSLaunchSmokeUITests: XCTestCase {
    private let launchTag = "ui-tests-latest-macos-launch-smoke"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAppLaunchDoesNotCrashOnStartup() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_TAG"] = launchTag
        app.launchEnvironment["CMUX_UI_TEST_MODE"] = "1"

        launchAllowingHeadlessBackgroundState(app)

        XCTAssertTrue(
            waitForAppToStart(app, timeout: 20.0),
            "Expected cmux to start on latest macOS. state=\(app.state.rawValue)"
        )

        XCTAssertTrue(
            waitForNoImmediateCrash(app, duration: 10.0),
            "Expected cmux to remain running for startup stability window. state=\(app.state.rawValue)"
        )

        if isRunning(app) {
            app.terminate()
        }
    }

    private func launchAllowingHeadlessBackgroundState(_ app: XCUIApplication) {
        // Some CI runners launch in background-only mode, which can emit an
        // activation failure even when the process is healthy.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("App activation may fail on headless CI runners", options: options) {
            app.launch()
        }
    }

    private func waitForAppToStart(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isRunning(app) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return isRunning(app)
    }

    private func waitForNoImmediateCrash(_ app: XCUIApplication, duration: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            if !isRunning(app) {
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }

    private func isRunning(_ app: XCUIApplication) -> Bool {
        app.state == .runningForeground || app.state == .runningBackground
    }
}
