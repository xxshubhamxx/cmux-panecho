import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "ai.manaflow.cmux.ios", category: "inbox.sync")

@MainActor
protocol UnifiedInboxWorkspaceSyncing: AnyObject {
    var workspaceItemsPublisher: AnyPublisher<[UnifiedInboxItem], Never> { get }
    func connect(teamID: String)
}

@MainActor
final class UnifiedInboxSyncService: UnifiedInboxWorkspaceSyncing {
    private let inboxCacheRepository: InboxCacheRepository?
    private let workspaceLiveSync: WorkspaceLiveSyncing
    private let subject: CurrentValueSubject<[UnifiedInboxItem], Never>
    private var cancellables = Set<AnyCancellable>()
    private var activeTeamID: String?
    private var hasAcceptedLiveSnapshot = false
    private var emptySnapshotFallbackTask: Task<Void, Never>?

    init(
        inboxCacheRepository: InboxCacheRepository?,
        workspaceLiveSync: WorkspaceLiveSyncing? = nil
    ) {
        self.inboxCacheRepository = inboxCacheRepository
        self.workspaceLiveSync = workspaceLiveSync ?? NoOpWorkspaceLiveSync()
        let cachedWorkspaceItems = (try? inboxCacheRepository?.load().filter { $0.kind == .workspace }) ?? []
        self.subject = CurrentValueSubject(cachedWorkspaceItems)
    }

    convenience init(
        inboxCacheRepository: InboxCacheRepository?,
        publisherFactory: @MainActor @escaping (String) -> AnyPublisher<[MobileInboxWorkspaceRow], Never>
    ) {
        self.init(
            inboxCacheRepository: inboxCacheRepository,
            workspaceLiveSync: ClosureWorkspaceLiveSync(publisherFactory: publisherFactory)
        )
    }

    var workspaceItemsPublisher: AnyPublisher<[UnifiedInboxItem], Never> {
        subject.eraseToAnyPublisher()
    }

    func connect(teamID: String) {
        guard activeTeamID != teamID else { return }
        activeTeamID = teamID
        hasAcceptedLiveSnapshot = false
        cancellables.removeAll()
        emptySnapshotFallbackTask?.cancel()

        workspaceLiveSync.publisher(teamID: teamID)
            .map { rows in
                rows.map { UnifiedInboxItem(workspaceRow: $0, teamID: teamID) }
            }
            .sink { [weak self] items in
                self?.handleLiveWorkspaceItems(items)
            }
            .store(in: &cancellables)

        // If no live snapshot is accepted within 5 seconds, force-accept
        // the next one (even if empty) to clear stale cached data. Kept as
        // a task so a reconnect to a different team cancels the previous
        // fallback instead of firing against the new team.
        emptySnapshotFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, !self.hasAcceptedLiveSnapshot else { return }
            self.hasAcceptedLiveSnapshot = true
            self.subject.send([])
            try? self.inboxCacheRepository?.save([])
        }
    }

    private func handleLiveWorkspaceItems(_ items: [UnifiedInboxItem]) {
        if shouldIgnoreInitialEmptySnapshot(items) {
            return
        }
        hasAcceptedLiveSnapshot = true
        subject.send(items)
        guard let inboxCacheRepository else { return }

        do {
            try inboxCacheRepository.save(items)
        } catch {
            #if DEBUG
            log.error("Failed to persist live workspace inbox items: \(error.localizedDescription, privacy: .public)")
            #endif
        }
    }

    private func shouldIgnoreInitialEmptySnapshot(_ items: [UnifiedInboxItem]) -> Bool {
        !hasAcceptedLiveSnapshot && items.isEmpty && !subject.value.isEmpty
    }

    nonisolated static func mergeItems(
        conversationItems: [UnifiedInboxItem],
        workspaceItems: [UnifiedInboxItem]
    ) -> [UnifiedInboxItem] {
        sort(items: conversationItems + workspaceItems)
    }

    nonisolated static func sort(items: [UnifiedInboxItem]) -> [UnifiedInboxItem] {
        items.sorted { lhs, rhs in
            if lhs.sortDate != rhs.sortDate {
                return lhs.sortDate > rhs.sortDate
            }
            if lhs.kind != rhs.kind {
                return lhs.kind == .workspace && rhs.kind == .conversation
            }
            return lhs.id < rhs.id
        }
    }
}

@MainActor
private final class ClosureWorkspaceLiveSync: WorkspaceLiveSyncing {
    private let publisherFactory: @MainActor (String) -> AnyPublisher<[MobileInboxWorkspaceRow], Never>

    init(
        publisherFactory: @MainActor @escaping (String) -> AnyPublisher<[MobileInboxWorkspaceRow], Never>
    ) {
        self.publisherFactory = publisherFactory
    }

    func publisher(teamID: String) -> AnyPublisher<[MobileInboxWorkspaceRow], Never> {
        publisherFactory(teamID)
    }
}
