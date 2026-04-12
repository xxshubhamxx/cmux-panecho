import AppKit
import Combine
import Foundation

/// Persistent socket bridge that instantly syncs Swift workspace state to the Zig daemon.
/// Replaces the polling-based MobilePresenceCoordinator.
@MainActor
final class WorkspaceDaemonBridge {
    private var tabManager: TabManager?
    private var notificationStore: TerminalNotificationStore?
    private var cancellables = Set<AnyCancellable>()
    private var workspaceCancellables: [UUID: AnyCancellable] = [:]

    private var socketFD: Int32 = -1
    private var syncScheduled = false
    private(set) var lastSyncTime: Date?
    private(set) var syncCount: Int = 0

    var isConnected: Bool { socketFD >= 0 }
    var statusDescription: String { isConnected ? "connected" : "disconnected" }
    var socketPath: String { daemonSocketPath }

    private var daemonSocketPath: String {
        let env = ProcessInfo.processInfo.environment
        if let path = env["CMUXD_UNIX_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("cmux").path ?? "/tmp"
        let tag = env["CMUX_TAG"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tag.isEmpty ? "\(appSupport)/cmuxd.sock" : "\(appSupport)/cmuxd-dev-\(tag).sock"
    }

    // Accept the same init signature as MobilePresenceCoordinator for drop-in replacement
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

        connectSocket()

        // Observe tab array changes (add/remove/reorder)
        tabManager.$tabs
            .sink { [weak self] workspaces in
                self?.rewireWorkspaceObservers(workspaces: workspaces)
                self?.scheduleSyncNow()
            }
            .store(in: &cancellables)

        // Observe selected tab changes
        tabManager.$selectedTabId
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleSyncNow() }
            .store(in: &cancellables)

        // Observe notification changes (preview text, unread count)
        TerminalNotificationStore.shared.$notifications
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleSyncNow() }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        workspaceCancellables.removeAll()
        disconnectSocket()
    }

    // MARK: - Change observation

    private func rewireWorkspaceObservers(workspaces: [Workspace]) {
        workspaceCancellables.removeAll()
        for workspace in workspaces {
            workspaceCancellables[workspace.id] = workspace.objectWillChange
                .sink { [weak self] _ in self?.scheduleSyncNow() }
        }
    }

    // MARK: - Sync (50ms debounce via RunLoop)

    private func scheduleSyncNow() {
        guard !syncScheduled else { return }
        syncScheduled = true
        // Coalesce changes within the same run loop iteration + 50ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.syncScheduled = false
            self?.performSync()
        }
    }

    private func performSync() {
        guard let tabManager, let notificationStore else { return }

        // Build full workspace payload
        let workspaces: [[String: Any]] = tabManager.tabs.map { workspace in
            let preview = workspacePreview(for: workspace)
            // Compute daemon session IDs deterministically from workspace+surface IDs.
            // This works even before the surface's DaemonTerminalBridge is created
            // (e.g. restored workspaces not yet made visible). The bridge uses the
            // same computation, so they match when the bridge eventually starts.
            let terminalPanels = workspace.panels.values.compactMap { $0 as? TerminalPanel }
            let sessionIDs: [String] = terminalPanels.map { panel in
                DaemonTerminalBridge.computeSessionID(
                    workspaceID: workspace.id,
                    surfaceID: panel.surface.id
                )
            }
            var entry: [String: Any] = [
                "id": workspace.id.uuidString.lowercased(),
                "title": workspace.title,
                "directory": workspace.currentDirectory,
                "preview": preview ?? "",
                "phase": workspace.activeRemoteTerminalSessionCount > 0 ? "active" : "idle",
                "color": workspace.customColor ?? "",
                "unread_count": notificationStore.unreadCount(forTabId: workspace.id),
                "pinned": workspace.isPinned,
            ]
            if let primarySessionID = sessionIDs.first {
                entry["session_id"] = primarySessionID
            }
            if sessionIDs.count > 1 {
                entry["session_ids"] = sessionIDs
            }
            entry["pane_count"] = workspace.panels.count
            return entry
        }

        let params: [String: Any] = [
            "selected_workspace_id": tabManager.selectedTabId?.uuidString.lowercased() ?? "",
            "workspaces": workspaces,
        ]

        sendRPC(method: "workspace.sync", params: params)
        lastSyncTime = Date()
        syncCount += 1
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

    // MARK: - Persistent socket

    private func connectSocket() {
        guard socketFD < 0 else { return }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { scheduleReconnect(); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
        daemonSocketPath.withCString { cstr in
            _ = memcpy(&addr.sun_path, cstr, min(Int(strlen(cstr)), pathSize - 1))
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }

        if result != 0 {
            close(fd)
            scheduleReconnect()
            return
        }

        // Set send timeout to avoid blocking forever
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        socketFD = fd

        // Immediately sync current state
        performSync()
    }

    private func disconnectSocket() {
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connectSocket()
        }
    }

    private func sendRPC(method: String, params: [String: Any]) {
        if socketFD < 0 {
            connectSocket()
            return
        }

        let payload: [String: Any] = ["id": 1, "method": method, "params": params]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        data.append(0x0A) // newline delimiter

        let writeResult = data.withUnsafeBytes { ptr -> Int in
            write(socketFD, ptr.baseAddress, ptr.count)
        }

        if writeResult <= 0 {
            // Connection lost
            disconnectSocket()
            scheduleReconnect()
            return
        }

        // Read response (drain it)
        var buf = [UInt8](repeating: 0, count: 4096)
        let readResult = read(socketFD, &buf, buf.count)
        if readResult <= 0 {
            // Connection lost
            disconnectSocket()
            scheduleReconnect()
        }
    }
}
