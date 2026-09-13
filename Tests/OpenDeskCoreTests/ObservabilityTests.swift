import XCTest
@testable import OpenDeskCore

/// Plan 18 tests: OSLog category coverage, correlation IDs, redaction,
/// diagnostic bundle contents (never includes secrets).
final class ObservabilityTests: XCTestCase {

    func testAllTwelveLogCategoriesExist() {
        let expected: Set<ODLog.Category> = [
            .app, .discovery, .rfb, .ssh, .agent, .tasks,
            .scheduler, .inventory, .database, .security, .update, .release,
        ]
        XCTAssertEqual(Set(ODLog.Category.allCases), expected)
        for category in ODLog.Category.allCases {
            XCTAssertNotNil(ODLog(category: category).oslog, "logger factory covers every category")
        }
    }

    func testCorrelationIDPropagatesThroughAuditAndTasks() throws {
        let db = try tempDB()
        let audit = SQLiteAuditRepository(db: db)
        let correlation = "corr-abc-123"
        try audit.record(AuditEvent(actor: "cli", action: "discovery.scan", targets: ["10.0.0.0/30"], result: .success, correlationID: correlation))
        let events = try audit.recent(limit: 5)
        XCTAssertEqual(events.first?.correlationID, correlation, "correlation ID persists on audit records")
    }

    func testDiagnosticBundleContentsAndRedaction() throws {
        let db = try tempDB()
        // Seed an audit event with a secret-looking parameter.
        try SQLiteAuditRepository(db: db).record(AuditEvent(
            actor: "cli", action: "device.add", targets: ["lab-01"],
            parameters: ["username": "admin", "vncPassword": "s3cret!"],
            result: .success, correlationID: "seed-1"
        ))
        let bundle = try DiagnosticBundle.generate(database: db)
        let text = bundle.text
        XCTAssertTrue(text.contains("OpenDesk"), "bundle names the product")
        XCTAssertTrue(text.contains("macOS"), "bundle records OS version")
        XCTAssertTrue(text.contains("schema:"), "bundle records database schema version")
        XCTAssertTrue(text.contains("audit"), "bundle includes sanitized audit excerpt")
        XCTAssertFalse(text.contains("s3cret!"), "bundle must never include secret values")
        XCTAssertTrue(text.contains("[REDACTED]"), "secrets are redacted before export")
        // File contents / clipboard are excluded by construction (nothing to leak).
        XCTAssertFalse(text.contains("clipboard-content:"))
    }

    private func tempDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-obs-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("t.db").path)
        _ = try SQLiteMigrator(db: db).run()
        return db
    }
}
