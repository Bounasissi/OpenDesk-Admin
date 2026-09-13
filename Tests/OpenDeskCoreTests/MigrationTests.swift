import XCTest
@testable import OpenDeskCore

/// Plan 03 §8: migration test suite — empty DB → latest; version semantics; idempotency.
final class MigrationTests: XCTestCase {

    private func tempDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-migrations-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try SQLiteDatabase(path: dir.appendingPathComponent("test.db").path)
    }

    func testEmptyDatabaseMigratesToLatest() throws {
        let db = try tempDB()
        let runner = SQLiteMigrator(db: db)
        let applied = try runner.run()
        XCTAssertEqual(applied, [1, 2, 3])
        XCTAssertEqual(try runner.currentVersion(), 3)
    }

    func testMigrationsAreIdempotent() throws {
        let db = try tempDB()
        let runner = SQLiteMigrator(db: db)
        XCTAssertEqual(try runner.run().count, 3)
        XCTAssertEqual(try runner.run().count, 0, "second run must apply nothing")
    }

    func testAllCoreTablesExistAfterMigration() throws {
        let db = try tempDB()
        _ = try SQLiteMigrator(db: db).run()
        let expected: Set<String> = [
            "devices", "device_endpoints", "device_capabilities", "credentials",
            "groups", "group_memberships", "smart_groups", "tasks", "task_targets",
            "task_events", "task_templates", "schedules", "sessions",
            "inventory_snapshots", "audit_events", "agent_status", "schema_migrations",
            "host_key_records", "enrollment_tokens", "agent_jobs",
        ]
        let tables = try db.stringColumn("SELECT name FROM sqlite_master WHERE type='table'")
        XCTAssertTrue(expected.isSubset(of: Set(tables)), "missing: \(expected.subtracting(Set(tables)))")
    }

    func testMigrationFailureSurfacesPersistenceError() throws {
        // A database where schema_migrations cannot be created surfaces PersistenceError.
        let db = try tempDB()
        try db.execute("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT)")
        try db.execute("INSERT INTO schema_migrations (version, applied_at) VALUES (999, 'now')") // future version
        let runner = SQLiteMigrator(db: db)
        XCTAssertThrowsError(try runner.run()) { error in
            guard case PersistenceError.schemaVersionMismatch = error else {
                return XCTFail("expected schemaVersionMismatch, got \(error)")
            }
        }
    }
}
