import XCTest
@testable import OpenDeskCore

/// Plan 16 §3 hardening-sweep tests: filesystem permission enforcement and
/// path traversal defense on transfer paths.
final class SecuritySweepTests: XCTestCase {

    func testDatabaseFileCreatedUserOnly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-sec-sweep-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("perm.db").path
        _ = try SQLiteDatabase(path: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        // Owner read/write only (no group/other access) — 0o600 family.
        let mode = permissions?.uint16Value ?? 0
        XCTAssertEqual(mode & 0o077, 0, "database file must not be group/world accessible (mode: \(String(mode, radix: 8)))")
    }

    func testPathTraversalRejected() {
        // Remote paths that escape the intended destination are rejected.
        XCTAssertThrowsError(try validateTransferPath(remotePath: "/tmp/staging/../../etc/passwd", base: "/tmp/staging"))
        XCTAssertThrowsError(try validateTransferPath(remotePath: "/tmp/staging/~/secrets", base: "/tmp/staging"))
        XCTAssertNoThrow(try validateTransferPath(remotePath: "/tmp/staging/tool.pkg", base: "/tmp/staging"))
        XCTAssertNoThrow(try validateTransferPath(remotePath: "/tmp/staging/sub/dir/file.txt", base: "/tmp/staging"))
    }

    func testCommandParameterizationNoRawInterpolation() {
        // Durable runner commands come from typed parameters; the shell command
        // is carried verbatim but the RUNNER never composes shell from
        // untrusted concatenation — verify the command extraction path.
        let db = try! tempDB()
        let runner = DurableTaskRunner(db: db, transport: FakeTransport())
        let task = try! runner.submit(
            type: "exec.command",
            deviceIDs: [],
            parameters: #"{"command": "sw_vers"}"#
        )
        let command = runner.commandFor(task: try! runner.tasksLoad(task.id), device: Device(hostname: "x", lifecycle: .online))
        XCTAssertEqual(command, "sw_vers", "command extracted verbatim from typed JSON, never rebuilt from concatenation")
    }

    private func tempDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-sec3-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("t.db").path)
        _ = try SQLiteMigrator(db: db).run()
        return db
    }
}
