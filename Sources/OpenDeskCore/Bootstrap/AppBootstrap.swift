import Foundation

/// Plan 03 §7.6 wiring: launch → open DB → migrate → record audit event.
/// Shared by the GUI and CLI bootstraps so both operate on the same
/// migrated canonical database.
public enum AppBootstrap {
    /// Canonical database location: ~/Library/Application Support/OpenDeskAdmin/opendesk.db
    public static func defaultDatabasePath() -> String {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenDeskAdmin", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("opendesk.db").path
    }

    /// Open and migrate the canonical database. Throws PersistenceError on failure.
    public static func openDatabase(path: String? = nil) throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(path: path ?? defaultDatabasePath())
        let applied = try SQLiteMigrator(db: db).run()
        if !applied.isEmpty {
            let audit = SQLiteAuditRepository(db: db)
            try audit.record(AuditEvent(
                actor: "system",
                action: "database.migrate",
                targets: applied.map(String.init),
                parameters: ["migrations": applied.map(String.init).joined(separator: ",")],
                result: .success,
                correlationID: "bootstrap"
            ))
        }
        return db
    }

    /// Record the launch audit event (Plan 03 exit wiring).
    public static func recordLaunch(db: SQLiteDatabase) {
        do {
            try SQLiteAuditRepository(db: db).record(AuditEvent(
                actor: "system",
                action: "app.launch",
                targets: [],
                result: .success,
                correlationID: "launch"
            ))
        } catch {
            // Launch must not fail because the audit write failed; diagnostics
            // surface it (Plan 18). Never fatal on startup.
        }
    }
}
