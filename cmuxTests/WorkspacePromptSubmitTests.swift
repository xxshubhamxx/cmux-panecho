import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class WorkspacePromptSubmitTests: XCTestCase {
    func testPromptSubmitRecordsMessageAndMovesWorkspaceToTopWhenIMessageModeEnabled() throws {
        let manager = TabManager()
        let first = manager.tabs[0]
        let second = manager.addWorkspace(select: false, placementOverride: .end)
        let third = manager.addWorkspace(select: false, placementOverride: .end)
        manager.selectWorkspace(second)

        let outcome = try XCTUnwrap(
            manager.handlePromptSubmit(
                workspaceId: third.id,
                message: "  implement this\n\nnow  ",
                iMessageModeEnabled: true
            )
        )

        XCTAssertTrue(outcome.messageRecorded)
        XCTAssertTrue(outcome.reordered)
        XCTAssertEqual(outcome.index, 0)
        XCTAssertEqual(manager.tabs.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(manager.selectedTabId, second.id)
        XCTAssertEqual(third.latestSubmittedMessage, "implement this now")
    }

    func testPromptSubmitDoesNothingWhenIMessageModeDisabled() throws {
        let manager = TabManager()
        let first = manager.tabs[0]
        let second = manager.addWorkspace(select: false, placementOverride: .end)
        let third = manager.addWorkspace(select: false, placementOverride: .end)

        let outcome = try XCTUnwrap(
            manager.handlePromptSubmit(
                workspaceId: third.id,
                message: "do not show",
                iMessageModeEnabled: false
            )
        )

        XCTAssertFalse(outcome.messageRecorded)
        XCTAssertFalse(outcome.reordered)
        XCTAssertEqual(outcome.index, 2)
        XCTAssertEqual(manager.tabs.map(\.id), [first.id, second.id, third.id])
        XCTAssertNil(third.latestSubmittedMessage)
    }
}
