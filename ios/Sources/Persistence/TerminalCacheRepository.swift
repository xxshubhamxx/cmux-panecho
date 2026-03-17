import Foundation

final class TerminalCacheRepository: TerminalSnapshotPersisting {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func load() -> TerminalStoreSnapshot {
        do {
            return try database.readTerminalSnapshot()
        } catch {
            #if DEBUG
            print("Failed to load terminal snapshot from SQLite: \(error)")
            #endif
            return .seed()
        }
    }

    func save(_ snapshot: TerminalStoreSnapshot) throws {
        try database.writeTerminalSnapshot(snapshot)
    }
}
