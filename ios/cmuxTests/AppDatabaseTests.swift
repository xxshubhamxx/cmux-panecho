import XCTest
@testable import cmux_DEV

final class AppDatabaseTests: XCTestCase {
    func testUnreadStateRoundTripsThroughDatabase() throws {
        let db = try AppDatabase.inMemory()
        try db.writeWorkspace(
            id: "ws_123",
            title: "orb / cmux",
            latestEventSeq: 4,
            lastReadEventSeq: 2
        )
        let row = try db.readWorkspace(id: "ws_123")
        XCTAssertEqual(row?.isUnread, true)
    }

    func testImportsLegacyTerminalSnapshot() throws {
        let host = TerminalHost(
            name: "Mac Mini",
            hostname: "cmux-macmini",
            username: "cmux",
            symbolName: "desktopcomputer",
            palette: .mint,
            source: .discovered,
            transportPreference: .remoteDaemon,
            sshAuthenticationMethod: .privateKey,
            teamID: "team_123",
            serverID: "server_123",
            allowsSSHFallback: false,
            directTLSPins: ["pin_a", "pin_b"]
        )
        let workspace = TerminalWorkspace(
            hostID: host.id,
            title: "orb / cmux",
            tmuxSessionName: "cmux-orb",
            preview: "feature/inbox",
            lastActivity: Date(timeIntervalSince1970: 1_710_000_000),
            unread: true,
            phase: .connected,
            lastError: "boom",
            backendIdentity: TerminalWorkspaceBackendIdentity(
                teamID: "team_123",
                taskID: "task_123",
                taskRunID: "task_run_123",
                workspaceName: "orb-123",
                descriptor: "Orb #123"
            ),
            backendMetadata: TerminalWorkspaceBackendMetadata(preview: "feature/inbox"),
            remoteDaemonResumeState: TerminalRemoteDaemonResumeState(
                sessionID: "session_123",
                attachmentID: "attachment_123",
                readOffset: 42
            )
        )
        let legacySnapshot = TerminalStoreSnapshot(
            hosts: [host],
            workspaces: [workspace],
            selectedWorkspaceID: workspace.id
        )
        let legacyStore = InMemoryTerminalSnapshotStore(snapshot: legacySnapshot)
        let db = try AppDatabase.inMemory()

        try AppDatabaseMigrator.importLegacySnapshotIfNeeded(from: legacyStore, into: db)

        XCTAssertEqual(try db.fetchHostCount(), 1)
        XCTAssertEqual(try db.readTerminalSnapshot(), legacySnapshot)
    }
}
