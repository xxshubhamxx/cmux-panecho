import AppKit
import Combine
import Foundation

/// Observes TabManager/workspace/notification changes and pushes `workspace.sync`
/// through the single shared `DaemonConnection`. Keeps the class name so existing
/// AppDelegate / TerminalController call sites stay intact; all socket I/O is
/// owned by `DaemonConnection.shared`.
@MainActor
final class WorkspaceDaemonBridge {
    private var tabManager: TabManager?
    private var notificationStore: TerminalNotificationStore?
    private var cancellables = Set<AnyCancellable>()
    private var workspaceCancellables: [UUID: AnyCancellable] = [:]
    private var panelCancellables: [UUID: AnyCancellable] = [:]
    private var panelSetCancellables: [UUID: AnyCancellable] = [:]

    private var syncScheduled = false
    private(set) var lastSyncTime: Date?
    private(set) var syncCount: Int = 0

    /// True while applying a daemon-sourced workspace.changed event. Suppresses
    /// the workspace.sync echo that observing @Published fields would otherwise
    /// trigger, preventing a ping-pong loop.
    private var applyingDaemonState = false

    /// Feature flags for Phase 2.2 field migrations. Default off. When on for
    /// a given field, the daemon owns it end-to-end: writes go via RPC, the
    /// field is excluded from workspace.sync, and incoming workspace.changed
    /// pushes are applied to local state. Flipping a flag off rolls back to
    /// the local-only behavior without redeploy.
    static let flagFieldPinned = "cmux.daemon.field.pinned"
    static let flagFieldCustomTitle = "cmux.daemon.field.customTitle"
    static let flagFieldCustomColor = "cmux.daemon.field.customColor"
    /// When on, the daemon owns workspace existence end-to-end: macOS-initiated
    /// creates/closes also fire `workspace.create` / `workspace.close` RPCs and
    /// daemon-pushed workspace.changed events add/remove local Workspace objects
    /// (deduped via DaemonConnection's pending_creates / pending_deletes).
    static let flagFieldExistence = "cmux.daemon.field.existence"

    static var pinnedOwnedByDaemon: Bool {
        UserDefaults.standard.bool(forKey: flagFieldPinned)
    }
    static var customTitleOwnedByDaemon: Bool {
        UserDefaults.standard.bool(forKey: flagFieldCustomTitle)
    }
    static var customColorOwnedByDaemon: Bool {
        UserDefaults.standard.bool(forKey: flagFieldCustomColor)
    }
    static var existenceOwnedByDaemon: Bool {
        UserDefaults.standard.bool(forKey: flagFieldExistence)
    }

    private var connection: DaemonConnection { DaemonConnection.shared }

    var isConnected: Bool { connection.isConnected }
    var statusDescription: String { connection.statusDescription }
    var socketPath: String { connection.currentSocketPath }

    init(
        authProvider: AnyObject? = nil,
        authChangePublisher: AnyPublisher<Void, Never>? = nil,
        heartbeatPublisher: AnyObject? = nil
    ) {}

    func start(tabManager: TabManager) {
        guard self.tabManager !== tabManager else { return }
        self.tabManager = tabManager
        self.notificationStore = .shared
        cancellables.removeAll()
        workspaceCancellables.removeAll()

        connection.setWorkspaceSyncProvider { [weak self] in
            guard let self else { return nil }
            return self.buildSyncParams()
        }

        connection.setWorkspaceChangedHandler { [weak self] payload in
            DispatchQueue.main.async {
                self?.applyWorkspaceChanged(payload)
            }
        }

        tabManager.$tabs
            .sink { [weak self] workspaces in
                self?.rewireWorkspaceObservers(workspaces: workspaces)
                self?.scheduleSyncNow()
            }
            .store(in: &cancellables)

        tabManager.$selectedTabId
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleSyncNow() }
            .store(in: &cancellables)

        TerminalNotificationStore.shared.$notifications
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleSyncNow() }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        workspaceCancellables.removeAll()
        panelCancellables.removeAll()
        panelSetCancellables.removeAll()
        connection.setWorkspaceChangedHandler(nil)
    }

    // MARK: - Applying daemon-sourced workspace state

    /// Apply a `workspace.changed` payload from the daemon to local Workspace
    /// objects. Each field is gated by a UserDefaults feature flag (default off)
    /// so Phase 2.2 can migrate them one at a time with rollback.
    private func applyWorkspaceChanged(_ payload: [String: Any]) {
        guard let tabManager else { return }
        guard let workspaces = payload["workspaces"] as? [[String: Any]] else { return }

        let applyPinned = Self.pinnedOwnedByDaemon
        let applyTitle = Self.customTitleOwnedByDaemon
        let applyColor = Self.customColorOwnedByDaemon
        let applyExistence = Self.existenceOwnedByDaemon
        guard applyPinned || applyTitle || applyColor || applyExistence else { return }

        let byID: [UUID: Workspace] = Dictionary(
            uniqueKeysWithValues: tabManager.tabs.compactMap { ws in (ws.id, ws) }
        )

        applyingDaemonState = true
        defer { applyingDaemonState = false }

        // Track ids the daemon currently knows about so we can reconcile both
        // pending_deletes and the local removal pass below.
        var daemonIDStrings: Set<String> = []
        var daemonUUIDs: Set<UUID> = []

        for entry in workspaces {
            guard let idString = entry["id"] as? String,
                  let id = UUID(uuidString: idString) else { continue }
            let normalizedID = id.uuidString.lowercased()
            daemonIDStrings.insert(normalizedID)
            daemonUUIDs.insert(id)

            // 1) Existence path: instantiate local Workspace if missing.
            if let ws = byID[id] {
                // If macOS-initiated this create, drop the pending entry now
                // that the daemon has acknowledged it. Field updates fall
                // through to the existing per-field handlers below.
                _ = connection.consumePendingCreate(workspaceID: id)
                applyFields(
                    to: ws,
                    entry: entry,
                    applyPinned: applyPinned,
                    applyTitle: applyTitle,
                    applyColor: applyColor
                )
            } else if applyExistence {
                // No local match. Suppress re-instantiation if we have a
                // pending close (daemon hasn't caught up yet) or if the
                // macOS app initiated a create whose echo arrived before the
                // local Workspace was inserted (rare; defensive).
                if connection.isPendingDelete(workspaceID: id) { continue }
                if connection.consumePendingCreate(workspaceID: id) { continue }

                let title = (entry["title"] as? String) ?? ""
                let directory = (entry["directory"] as? String) ?? ""
                let color = (entry["color"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedColor = (color?.isEmpty == false) ? color : nil
                let pinned = (entry["pinned"] as? Bool) ?? false
                tabManager.addWorkspaceFromDaemon(
                    id: id,
                    title: title,
                    directory: directory.isEmpty ? nil : directory,
                    color: normalizedColor,
                    pinned: pinned
                )
            }
        }

        // 2) Existence path: close any local workspace the daemon no longer
        // knows about (and that we are not already trying to close locally).
        if applyExistence {
            let toClose = tabManager.tabs.filter { ws in
                !daemonUUIDs.contains(ws.id)
                    && !connection.isPendingDelete(workspaceID: ws.id)
            }
            for ws in toClose {
                tabManager.closeWorkspaceFromDaemon(ws)
            }
        }

        // 3) Reconcile pending_deletes against the daemon's current view.
        connection.reconcilePendingDeletes(currentDaemonIDs: daemonIDStrings)
    }

    private func applyFields(
        to ws: Workspace,
        entry: [String: Any],
        applyPinned: Bool,
        applyTitle: Bool,
        applyColor: Bool
    ) {
        if applyPinned, let pinned = entry["pinned"] as? Bool, ws.isPinned != pinned {
            ws.isPinned = pinned
        }
        if applyTitle, let title = entry["title"] as? String, ws.title != title {
            ws.title = title
        }
        if applyColor {
            let color = (entry["color"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = (color?.isEmpty == false) ? color : nil
            if ws.customColor != normalized {
                ws.customColor = normalized
            }
        }
    }

    private func rewireWorkspaceObservers(workspaces: [Workspace]) {
        workspaceCancellables.removeAll()
        panelCancellables.removeAll()
        panelSetCancellables.removeAll()
        for workspace in workspaces {
            workspaceCancellables[workspace.id] = workspace.objectWillChange
                .sink { [weak self] _ in self?.scheduleSyncNow() }
            panelSetCancellables[workspace.id] = workspace.$panels
                .sink { [weak self] panels in
                    self?.rewirePanelObservers(panels)
                    self?.scheduleSyncNow()
                }
        }
    }

    private func rewirePanelObservers(_ panels: [UUID: any Panel]) {
        panelCancellables.removeAll()
        for panel in panels.values {
            if let terminal = panel as? TerminalPanel {
                panelCancellables[panel.id] = terminal.objectWillChange
                    .sink { [weak self] _ in self?.scheduleSyncNow() }
            }
        }
    }

    private func scheduleSyncNow() {
        guard !applyingDaemonState else { return }
        guard !syncScheduled else { return }
        syncScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.syncScheduled = false
            self?.performSync()
        }
    }

    private func performSync() {
        guard let params = buildSyncParams() else { return }
        connection.sendWorkspaceSync(params)
        lastSyncTime = Date()
        syncCount += 1
    }

    private func buildSyncParams() -> [String: Any]? {
        guard let tabManager, let notificationStore else { return nil }

        let workspaces: [[String: Any]] = tabManager.tabs.map { workspace in
            let preview = workspacePreview(for: workspace)
            let terminalPanels = workspace.panels.values.compactMap { $0 as? TerminalPanel }
            let sessionIDs: [String] = terminalPanels.map { panel in
                panel.surface.savedDaemonSessionID
                    ?? DaemonConnection.computeSessionID(
                        workspaceID: workspace.id,
                        surfaceID: panel.surface.id
                    )
            }
            let paneInfos: [[String: Any]] = terminalPanels.map { panel in
                let customTitle = workspace.panelCustomTitles[panel.id]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedTitle = (customTitle?.isEmpty == false ? customTitle : nil)
                    ?? panel.title
                let paneSID = panel.surface.savedDaemonSessionID
                    ?? DaemonConnection.computeSessionID(
                        workspaceID: workspace.id,
                        surfaceID: panel.surface.id
                    )
                return [
                    "session_id": paneSID,
                    "title": resolvedTitle,
                    "directory": panel.directory,
                ]
            }
            var entry: [String: Any] = [
                "id": workspace.id.uuidString.lowercased(),
                "directory": workspace.currentDirectory,
                "preview": preview ?? "",
                "phase": workspace.activeRemoteTerminalSessionCount > 0 ? "active" : "idle",
                "unread_count": notificationStore.unreadCount(forTabId: workspace.id),
                "panes": paneInfos,
            ]
            if !Self.customTitleOwnedByDaemon {
                entry["title"] = workspace.title
            }
            if !Self.customColorOwnedByDaemon {
                entry["color"] = workspace.customColor ?? ""
            }
            if !Self.pinnedOwnedByDaemon {
                entry["pinned"] = workspace.isPinned
            }
            if let primarySessionID = sessionIDs.first {
                entry["session_id"] = primarySessionID
            }
            if sessionIDs.count > 1 {
                entry["session_ids"] = sessionIDs
            }
            entry["pane_count"] = workspace.panels.count
            return entry
        }

        return [
            "selected_workspace_id": tabManager.selectedTabId?.uuidString.lowercased() ?? "",
            "workspaces": workspaces,
        ]
    }

    private func workspacePreview(for workspace: Workspace) -> String? {
        guard let notificationStore else { return workspace.currentDirectory }
        let notification = notificationStore.latestNotification(forTabId: workspace.id)
        for candidate in [notification?.body, notification?.subtitle, workspace.currentDirectory] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
