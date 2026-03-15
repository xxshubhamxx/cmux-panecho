import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class GhosttyScrollbarSyncPlanTests: XCTestCase {
    func testPreservesStoredTopVisibleRowWhenNewOutputArrives() {
        let plan = ghosttyScrollViewportSyncPlan(
            scrollbar: GhosttyScrollbar(total: 105, offset: 10, len: 20),
            storedTopVisibleRow: 70,
            isExplicitViewportChange: false
        )

        XCTAssertEqual(plan.targetTopVisibleRow, 70)
        XCTAssertEqual(plan.targetRowFromBottom, 15)
        XCTAssertEqual(plan.storedTopVisibleRow, 70)
    }

    func testExplicitViewportChangeUsesIncomingScrollbarPosition() {
        let plan = ghosttyScrollViewportSyncPlan(
            scrollbar: GhosttyScrollbar(total: 100, offset: 15, len: 20),
            storedTopVisibleRow: 70,
            isExplicitViewportChange: true
        )

        XCTAssertEqual(plan.targetTopVisibleRow, 65)
        XCTAssertEqual(plan.targetRowFromBottom, 15)
        XCTAssertEqual(plan.storedTopVisibleRow, 65)
    }

    func testBottomPositionClearsStoredAnchor() {
        let plan = ghosttyScrollViewportSyncPlan(
            scrollbar: GhosttyScrollbar(total: 100, offset: 0, len: 20),
            storedTopVisibleRow: 70,
            isExplicitViewportChange: true
        )

        XCTAssertEqual(plan.targetTopVisibleRow, 80)
        XCTAssertEqual(plan.targetRowFromBottom, 0)
        XCTAssertNil(plan.storedTopVisibleRow)
    }

    func testInternalScrollCorrectionDoesNotMarkExplicitViewportChange() {
        XCTAssertFalse(
            ghosttyShouldMarkExplicitViewportChange(
                action: "scroll_to_row:15",
                source: .internalCorrection
            )
        )
        XCTAssertTrue(
            ghosttyShouldMarkExplicitViewportChange(
                action: "scroll_to_row:15",
                source: .userInteraction
            )
        )
    }

    func testScrollWheelStartsExplicitViewportChange() {
        XCTAssertTrue(ghosttyShouldBeginExplicitViewportChange(for: .scrollWheel))
    }

    func testExplicitViewportChangeIsConsumedByFirstScrollbarUpdate() {
        let first = ghosttyConsumeExplicitViewportChange(
            pendingExplicitViewportChange: true
        )

        XCTAssertTrue(first.isExplicitViewportChange)
        XCTAssertFalse(first.remainingPendingExplicitViewportChange)

        let second = ghosttyConsumeExplicitViewportChange(
            pendingExplicitViewportChange: first.remainingPendingExplicitViewportChange
        )

        XCTAssertFalse(second.isExplicitViewportChange)
    }

    func testAutomaticFocusRestoreIsSuppressedWhileReviewingScrollback() {
        XCTAssertFalse(ghosttyShouldRestoreAutomaticTerminalFocus(storedTopVisibleRow: 70))
        XCTAssertTrue(ghosttyShouldRestoreAutomaticTerminalFocus(storedTopVisibleRow: nil))
    }

    func testAutomaticEnsureFocusReassertIsSuppressedWhileReviewingScrollback() {
        XCTAssertFalse(
            ghosttyShouldAutomaticallyReassertTerminalFocus(
                storedTopVisibleRow: 70,
                focusRequestSource: .automaticEnsureFocus
            )
        )
        XCTAssertTrue(
            ghosttyShouldAutomaticallyReassertTerminalFocus(
                storedTopVisibleRow: 70,
                focusRequestSource: .explicitUserAction
            )
        )
    }

    func testAutomaticFirstResponderAcquisitionIsSuppressedWhileReviewingScrollback() {
        XCTAssertFalse(
            ghosttyShouldApplyTerminalSurfaceFocusOnFirstResponderAcquisition(
                storedTopVisibleRow: 70,
                acquisitionSource: .automaticWindowActivation
            )
        )
        XCTAssertTrue(
            ghosttyShouldApplyTerminalSurfaceFocusOnFirstResponderAcquisition(
                storedTopVisibleRow: 70,
                acquisitionSource: .directSurfaceInteraction
            )
        )
    }

    func testFailedScrollCorrectionDispatchKeepsRetryStateClear() {
        let failed = ghosttyScrollCorrectionDispatchState(
            previousLastSentRow: 4,
            previousPendingAnchorCorrectionRow: nil,
            targetRowFromBottom: 15,
            dispatchSucceeded: false
        )

        XCTAssertEqual(failed.lastSentRow, 4)
        XCTAssertNil(failed.pendingAnchorCorrectionRow)

        let succeeded = ghosttyScrollCorrectionDispatchState(
            previousLastSentRow: 4,
            previousPendingAnchorCorrectionRow: nil,
            targetRowFromBottom: 15,
            dispatchSucceeded: true
        )

        XCTAssertEqual(succeeded.lastSentRow, 15)
        XCTAssertEqual(succeeded.pendingAnchorCorrectionRow, 15)
    }
}
