import Foundation
import OSLog

private let log = Logger(subsystem: "ai.manaflow.cmux.ios", category: "terminal.daemon-connection")

enum TerminalDaemonConnectionEvent: Sendable {
    case connected
    case connectFailed(consecutiveFailures: Int)
    case workspacesJSON(String)
    case disconnected
}

/// Owns one URLSessionWebSocketTask + TerminalRemoteDaemonClient per daemon (host:port).
/// Drives workspace subscription with backoff + reconnect on the connection level.
actor TerminalDaemonConnection {
    let hostname: String
    let port: Int
    let secret: String

    private let wsClient = TerminalWebSocketDaemonClient()
    private var client: TerminalRemoteDaemonClient?
    private var lineTransport: TerminalWebSocketLineTransport?
    private var hello: TerminalRemoteDaemonHello?
    private var connectTask: Task<(TerminalRemoteDaemonClient, TerminalRemoteDaemonHello, TerminalWebSocketLineTransport?), Error>?
    private var subscriptionTask: Task<Void, Never>?
    private var subscribed = false
    private let pushConfigurator: PushNotificationConfigurator
    private var lastPushConfiguration: PushNotificationConfigurator.DaemonConfiguration?
    /// Continuations waiting for the next post-reconnect workspace.subscribe
    /// round to complete. Resumed after the subscribe RPC returns, whether
    /// it succeeded or not — by that point the refresh cycle has made one
    /// full pass and the caller can dismiss its spinner.
    private var pendingSubscribeRoundWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        hostname: String,
        port: Int,
        secret: String,
        pushConfigurator: PushNotificationConfigurator = .shared
    ) {
        self.hostname = hostname
        self.port = port
        self.secret = secret
        self.pushConfigurator = pushConfigurator
    }

    func currentClient() -> TerminalRemoteDaemonClient? { client }
    func currentHello() -> TerminalRemoteDaemonHello? { hello }

    /// Called by `TerminalDaemonConnectionPool.connection(...)` to decide
    /// whether a cached pool entry still matches the requested endpoint.
    /// Returns false if any of host/port/secret differ so the pool can
    /// evict the stale entry. Nonisolated (stored params are `let`)
    /// because the pool lookup path is synchronous.
    nonisolated func matches(hostname: String, port: Int, secret: String) -> Bool {
        self.hostname == hostname
            && self.port == port
            && self.secret == secret
    }

    /// Returns a live client for this daemon, opening a new ws if needed
    /// or replacing a stale one whose transport has failed.
    func acquireClient() async throws -> (TerminalRemoteDaemonClient, TerminalRemoteDaemonHello) {
        if let client, let hello, await !client.isClosed() {
            return (client, hello)
        }
        if client != nil {
            await teardownClient()
        }
        return try await ensureConnected()
    }

    func startWorkspaceSubscription(onEvent: @escaping @Sendable (TerminalDaemonConnectionEvent) -> Void) {
        guard subscriptionTask == nil else { return }
        subscribed = true
        subscriptionTask = Task { [weak self] in
            await self?.runSubscriptionLoop(onEvent: onEvent)
        }
    }

    func stopWorkspaceSubscription() async {
        subscribed = false
        let task = subscriptionTask
        subscriptionTask = nil
        task?.cancel()
        await task?.value
        await teardownClient()
    }

    /// Force an immediate reconnect: tear down the current client so the
    /// subscription loop wakes from `waitForTransportFailure` and goes
    /// through `ensureConnected` again on the next iteration. Used by
    /// scenePhase-active hook and by `kickAndAwaitFirstSync` below.
    func kickReconnect() async {
        await teardownClient()
    }

    /// Pull-to-refresh variant: kicks the connection, then suspends until
    /// the subscription loop completes its next workspace.subscribe round
    /// (success or error). Lets the refreshable spinner dismiss only after
    /// fresh state has arrived instead of after a blind delay.
    func kickAndAwaitFirstSync() async {
        await withCheckedContinuation { continuation in
            pendingSubscribeRoundWaiters.append(continuation)
            Task { await self.teardownClient() }
        }
    }

    private func resumeSubscribeRoundWaiters() {
        guard !pendingSubscribeRoundWaiters.isEmpty else { return }
        let waiters = pendingSubscribeRoundWaiters
        pendingSubscribeRoundWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func workspaceRename(workspaceID: String, title: String) async throws {
        let (client, _) = try await acquireClient()
        try await client.workspaceRename(workspaceID: workspaceID, title: title)
    }

    func workspacePin(workspaceID: String, pinned: Bool) async throws {
        let (client, _) = try await acquireClient()
        try await client.workspacePin(workspaceID: workspaceID, pinned: pinned)
    }

    private func runSubscriptionLoop(onEvent: @escaping @Sendable (TerminalDaemonConnectionEvent) -> Void) async {
        var consecutiveFailures = 0

        while !Task.isCancelled && subscribed {
            let connection: (TerminalRemoteDaemonClient, TerminalRemoteDaemonHello)
            do {
                connection = try await ensureConnected()
            } catch {
                consecutiveFailures += 1
                onEvent(.connectFailed(consecutiveFailures: consecutiveFailures))
                // Unblock any pull-to-refresh waiters so the spinner
                // dismisses even when the daemon can't be reached.
                resumeSubscribeRoundWaiters()
                let delay = min(30.0, 5.0 * pow(2.0, Double(min(consecutiveFailures - 1, 3))))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
            consecutiveFailures = 0
            onEvent(.connected)

            let connectionClient = connection.0
            // Stream workspace.* push events to the caller.
            await connectionClient.setWorkspaceEventHandler { line in
                onEvent(.workspacesJSON(line))
            }

            // Initial subscribe also returns the current workspace list.
            let initialResult: TerminalRemoteDaemonWorkspaceListResult?
            do {
                initialResult = try await connectionClient.workspaceSubscribe()
            } catch {
                log.error("workspace.subscribe failed: \(error.localizedDescription, privacy: .public)")
                initialResult = nil
            }
            if let initialResult, let initialJSON = Self.encodeWorkspaceList(initialResult) {
                onEvent(.workspacesJSON(initialJSON))
            }
            resumeSubscribeRoundWaiters()

            await waitForTransportFailure(client: connectionClient)

            await connectionClient.clearWorkspaceEventHandler()
            await teardownClient()
            onEvent(.disconnected)

            if !subscribed || Task.isCancelled { break }
            // If the next ensureConnected() fails immediately the outer
            // exponential-backoff path (consecutiveFailures) kicks in, so
            // no blanket pause is needed here.
        }
    }

    private func waitForTransportFailure(client: TerminalRemoteDaemonClient) async {
        // The dispatcher marks the client closed and resumes any awaiters
        // as soon as transport.readLine throws, so waiting is purely
        // event-driven — no hello polling needed.
        await client.awaitClose()
    }

    private func ensureConnected() async throws -> (TerminalRemoteDaemonClient, TerminalRemoteDaemonHello) {
        if let client, let hello {
            return (client, hello)
        }
        if let connectTask {
            let (c, h, _) = try await connectTask.value
            return (c, h)
        }
        let task = Task { [hostname, port, secret, wsClient] in
            try await Self.openConnection(
                wsClient: wsClient,
                hostname: hostname,
                port: port,
                secret: secret
            )
        }
        connectTask = task
        do {
            let (newClient, newHello, newLine) = try await task.value
            self.client = newClient
            self.hello = newHello
            self.lineTransport = newLine
            self.connectTask = nil
            // Phase 4.3: configure daemon-side APNs forwarding if the daemon
            // advertises the capability and we have a full configuration.
            // Fire-and-forget so RPC failures don't block connect.
            self.lastPushConfiguration = nil
            Task { [weak self] in
                await self?.applyPushConfigurationIfNeeded()
            }
            return (newClient, newHello)
        } catch {
            self.connectTask = nil
            throw error
        }
    }

    /// Re-run the push configuration check, e.g. after the device token or
    /// UserDefaults values change. No-op if we're not connected or the daemon
    /// doesn't advertise `notifications.remote`.
    func reprovisionRemotePush() async {
        await applyPushConfigurationIfNeeded(forceResend: true)
    }

    private func applyPushConfigurationIfNeeded(forceResend: Bool = false) async {
        guard let client, let hello, await !client.isClosed() else { return }
        guard hello.capabilities.contains("notifications.remote") else {
            #if DEBUG
            log.info("notifications.remote not advertised; skipping push config")
            #endif
            lastPushConfiguration = nil
            return
        }
        guard let config = pushConfigurator.currentConfiguration() else {
            #if DEBUG
            log.info("push config incomplete; remote push disabled")
            #endif
            lastPushConfiguration = nil
            return
        }
        if !forceResend, lastPushConfiguration == config {
            return
        }
        do {
            try await client.configureNotifications(
                endpoint: config.endpoint,
                bearerToken: config.bearerToken,
                deviceTokens: config.deviceTokens
            )
            lastPushConfiguration = config
            #if DEBUG
            log.debug("configured remote push endpoint=\(config.endpoint, privacy: .public) tokens=\(config.deviceTokens.count, privacy: .public)")
            #endif
        } catch {
            #if DEBUG
            log.error("configure_notifications failed: \(String(describing: error), privacy: .public)")
            #endif
        }
    }

    private func teardownClient() async {
        let line = lineTransport
        client = nil
        hello = nil
        lineTransport = nil
        lastPushConfiguration = nil
        await line?.cancel()
    }

    private static func openConnection(
        wsClient: TerminalWebSocketDaemonClient,
        hostname: String,
        port: Int,
        secret: String
    ) async throws -> (TerminalRemoteDaemonClient, TerminalRemoteDaemonHello, TerminalWebSocketLineTransport?) {
        let transport = try await wsClient.connect(host: hostname, port: port, secret: secret)
        let client = TerminalRemoteDaemonClient(transport: transport)
        let hello = try await client.sendHello()
        return (client, hello, transport as? TerminalWebSocketLineTransport)
    }

    private static func encodeWorkspaceList(_ result: TerminalRemoteDaemonWorkspaceListResult) -> String? {
        // Re-encode the typed result back into the JSON envelope shape that
        // `handleWorkspaceResponse` already parses ({"result": {"workspaces": [...]}}).
        // The simpler path is to just serialize the workspaces inline.
        let workspaces = result.workspaces.map { ws -> [String: Any] in
            var entry: [String: Any] = [
                "id": ws.id,
                "title": ws.title,
                "directory": ws.directory,
                "pane_count": ws.paneCount,
                "created_at": ws.createdAt,
                "last_activity_at": ws.lastActivityAt,
            ]
            if let sid = ws.sessionID { entry["session_id"] = sid }
            if let preview = ws.preview { entry["preview"] = preview }
            if let unread = ws.unreadCount { entry["unread_count"] = unread }
            if let pinned = ws.pinned { entry["pinned"] = pinned }
            if let panes = ws.panes {
                entry["panes"] = panes.map { p -> [String: Any] in
                    var pd: [String: Any] = ["id": p.id]
                    if let sid = p.sessionID { pd["session_id"] = sid }
                    if let t = p.title { pd["title"] = t }
                    if let d = p.directory { pd["directory"] = d }
                    return pd
                }
            }
            return entry
        }
        let envelope: [String: Any] = [
            "result": [
                "workspaces": workspaces,
                "selected_workspace_id": result.selectedWorkspaceID as Any,
                "change_seq": result.changeSeq,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
