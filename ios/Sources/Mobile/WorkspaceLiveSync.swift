import Combine
import Foundation

@MainActor
protocol WorkspaceLiveSyncing: AnyObject {
    func publisher(teamID: String) -> AnyPublisher<[MobileInboxWorkspaceRow], Never>
}

@MainActor
final class NoOpWorkspaceLiveSync: WorkspaceLiveSyncing {
    func publisher(teamID: String) -> AnyPublisher<[MobileInboxWorkspaceRow], Never> {
        Just([]).eraseToAnyPublisher()
    }
}
