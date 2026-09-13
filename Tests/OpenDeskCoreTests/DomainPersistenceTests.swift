import XCTest
import Foundation
@testable import OpenDeskCore

/// Plan 03 §8: domain round-trip persistence tests + Plan 03 §6 error-type tests.
final class DomainPersistenceTests: XCTestCase {

    private func tempDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-domain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("test.db").path)
        _ = try SQLiteMigrator(db: db).run()
        return db
    }

    // MARK: Device round trip

    func testDeviceCreateLoadRoundTrip() throws {
        let db = try tempDB()
        let repo = SQLiteDeviceRepository(db: db)
        let device = Device(
            id: DeviceID(),
            hostname: "lab-01.local",
            lifecycle: .online,
            stableSignals: [.sshHostKey("SHA256:abc")],
            endpoints: [Endpoint(host: "10.0.0.5", port: 5900, transport: .rfb)]
        )
        try repo.upsert(device)
        let loaded = try repo.load(device.id)
        XCTAssertEqual(loaded?.hostname, "lab-01.local")
        XCTAssertEqual(loaded?.lifecycle, .online)
        XCTAssertEqual(loaded?.endpoints.first?.host, "10.0.0.5")
        XCTAssertEqual(loaded?.endpoints.first?.transport, .rfb)
    }

    func testDeviceLifecycleTransitionsPersist() throws {
        let db = try tempDB()
        let repo = SQLiteDeviceRepository(db: db)
        let device = Device(id: DeviceID(), hostname: "h", lifecycle: .unknown)
        try repo.upsert(device)
        var loaded = try XCTUnwrap(repo.load(device.id))
        loaded.lifecycle = .degraded
        try repo.upsert(loaded)
        XCTAssertEqual(try repo.load(device.id)?.lifecycle, .degraded)
    }

    // MARK: Task round trip

    func testTaskCreateAndStateEventPersistence() throws {
        let db = try tempDB()
        let repo = SQLiteTaskRepository(db: db)
        let task = TaskRecord(
            id: TaskID(),
            type: "exec.command",
            state: .created,
            idempotencyKey: "exec-abc-1",
            correlationID: "corr-1"
        )
        try repo.insert(task)
        try repo.recordTransition(taskID: task.id, from: .created, to: .queued, detail: "queued for dispatch")
        let loaded = try repo.load(task.id)
        XCTAssertEqual(loaded?.state, .queued)
        XCTAssertEqual(loaded?.idempotencyKey, "exec-abc-1")
        let events = try repo.events(for: task.id)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].toState, .queued)
    }

    func testTerminalTaskStateIsImmutable() throws {
        let db = try tempDB()
        let repo = SQLiteTaskRepository(db: db)
        let task = TaskRecord(id: TaskID(), type: "exec.command", state: .success)
        try repo.insert(task)
        XCTAssertThrowsError(try repo.recordTransition(taskID: task.id, from: .success, to: .running, detail: "illegal")) { error in
            guard case PersistenceError.terminalStateImmutable = error else {
                return XCTFail("expected terminalStateImmutable, got \(error)")
            }
        }
    }

    func testDuplicateIdempotencyKeyRejected() throws {
        let db = try tempDB()
        let repo = SQLiteTaskRepository(db: db)
        let a = TaskRecord(id: TaskID(), type: "exec.command", state: .created, idempotencyKey: "dup-key")
        try repo.insert(a)
        let b = TaskRecord(id: TaskID(), type: "exec.command", state: .created, idempotencyKey: "dup-key")
        XCTAssertThrowsError(try repo.insert(b)) { error in
            guard case PersistenceError.duplicateIdempotencyKey = error else {
                return XCTFail("expected duplicateIdempotencyKey, got \(error)")
            }
        }
    }

    // MARK: Audit event

    func testAuditEventPersistsRedactedParameters() throws {
        let db = try tempDB()
        let repo = SQLiteAuditRepository(db: db)
        let event = AuditEvent(
            actor: "admin",
            action: "device.add",
            targets: ["lab-01.local"],
            parameters: ["username": "admin", "note": "no secrets here"],
            result: .success,
            correlationID: "corr-42"
        )
        try repo.record(event)
        let events = try repo.recent(limit: 10)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].action, "device.add")
        XCTAssertEqual(events[0].correlationID, "corr-42")
        XCTAssertFalse(events[0].parametersJSON.contains("password"), "no secret fields expected in parameters")
    }

    // MARK: Smart group definition persistence (Plan 04 A1.3: definitions are source of truth)

    func testSmartGroupPredicateDefinitionPersists() throws {
        let db = try tempDB()
        let repo = SQLiteSmartGroupRepository(db: db)
        let group = SmartGroup(
            id: GroupID(),
            name: "arm64-lab",
            predicate: SmartGroupPredicate(
                op: .and,
                clauses: [.init(field: "architecture", op: .eq, value: "arm64")]
            )
        )
        try repo.upsert(group)
        let loaded = try repo.load(group.id)
        XCTAssertEqual(loaded?.name, "arm64-lab")
        XCTAssertEqual(loaded?.predicate, group.predicate)
    }

    // MARK: Errors (Plan 03 §6)

    func testTypedErrorsCarryUserSafeAndInternalDescriptions() {
        let errors: [any OpenDeskError] = [
            TransportError.connectionRefused(host: "h"),
            AuthenticationError.hostKeyMismatch(fingerprint: "SHA256:x"),
            AuthorizationError.permission(.power),
            TaskExecutionError.nonZeroExit(code: 2, taskID: TaskID()),
            PersistenceError.migrationFailed(step: 1, reason: "disk full"),
            ProtocolError.violation("bad banner"),
            PermissionError.screenRecordingNotGranted,
            ConfigurationError.missingValue("admin port"),
        ]
        for error in errors {
            let user = error.userSafeDescription
            let internalDiagnostics = String(describing: error)
            XCTAssertFalse(user.isEmpty, "\(error) must provide a user-safe description")
            XCTAssertNotEqual(user, internalDiagnostics, "user-safe text must differ from raw diagnostics")
        }
    }
}
