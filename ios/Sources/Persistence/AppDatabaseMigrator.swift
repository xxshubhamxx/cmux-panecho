import GRDB

enum AppDatabaseMigrator {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_terminal_cache") { db in
            try db.create(table: "hosts") { table in
                table.column("host_id", .text).notNull().primaryKey()
                table.column("stable_id", .text).notNull()
                table.column("name", .text).notNull()
                table.column("hostname", .text).notNull()
                table.column("port", .integer).notNull()
                table.column("username", .text).notNull()
                table.column("symbol_name", .text).notNull()
                table.column("palette", .text).notNull()
                table.column("bootstrap_command", .text).notNull()
                table.column("trusted_host_key", .text)
                table.column("pending_host_key", .text)
                table.column("sort_index", .integer).notNull().defaults(to: 0)
                table.column("source", .text).notNull()
                table.column("transport_preference", .text).notNull()
                table.column("ssh_authentication_method", .text).notNull()
                table.column("team_id", .text)
                table.column("server_id", .text)
                table.column("allows_ssh_fallback", .boolean).notNull().defaults(to: true)
                table.column("direct_tls_pins_json", .text).notNull().defaults(to: "[]")
            }

            try db.create(table: "workspaces") { table in
                table.column("workspace_id", .text).notNull().primaryKey()
                table.column("host_id", .text).notNull()
                table.column("title", .text).notNull()
                table.column("tmux_session_name", .text).notNull()
                table.column("preview", .text).notNull().defaults(to: "")
                table.column("last_activity_at", .double).notNull()
                table.column("unread", .boolean).notNull().defaults(to: false)
                table.column("phase", .text).notNull()
                table.column("last_error", .text)
                table.column("backend_identity_json", .text)
                table.column("backend_metadata_json", .text)
                table.column("remote_daemon_resume_state_json", .text)
                table.column("latest_event_seq", .integer).notNull().defaults(to: 0)
                table.column("last_read_event_seq", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "app_metadata") { table in
                table.column("key", .text).notNull().primaryKey()
                table.column("string_value", .text)
            }
        }

        return migrator
    }

    static func importLegacySnapshotIfNeeded(
        from legacyStore: TerminalSnapshotPersisting,
        into database: AppDatabase
    ) throws {
        if try database.hasImportedLegacySnapshot {
            return
        }

        if try database.hasPersistedTerminalSnapshot {
            try database.markLegacySnapshotImported()
            return
        }

        try database.writeTerminalSnapshot(legacyStore.load())
        try database.markLegacySnapshotImported()
    }
}
