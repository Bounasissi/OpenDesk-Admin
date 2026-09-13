import XCTest
@testable import OpenDeskCore

/// Plan 08 A1.1 durable-behavior tests: offline waits, reconnect executes,
/// restart survives, partial fleet failure survives, duplicate prevented,
/// cancellation persisted. Plan 08 A1.2: schedules in the canonical DB.
final class DurableTaskTests: XCTestCase {

    private func tempDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-durable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("t.db").path)
        _ = try SQLiteMigrator(db: db).run()
        return db
    }

    private func onlineDevice(_ db: SQLiteDatabase, hostname: String, online: Bool) throws -> Device {
        let device = Device(hostname: hostname, lifecycle: online ? .online : .offline)
        try SQLiteDeviceRepository(db: db).upsert(device)
        return device
    }

    // MARK: Offline target waits (not failed)

    func testOfflineTargetWaitsForReconnect() throws {
        let db = try tempDB()
        let device = try onlineDevice(db, hostname: "sleepy", online: false)
        let transport = FakeTransport()
        let runner = DurableTaskRunner(db: db, transport: transport)
        let task = try runner.submit(type: "exec.command", deviceIDs: [device.id], parameters: #"{"command": "uptime"}"#)
        try runner.dispatchPending()
        let loaded = try SQLiteTaskRepository(db: db).load(task.id)
        XCTAssertEqual(loaded?.state, .waitingForTarget, "offline target waits, not fails")
    }

    // MARK: Reconnect executes

    func testReconnectExecutesPendingTask() throws {
        let db = try tempDB()
        let device = try onlineDevice(db, hostname: "wakey", online: false)
        let transport = FakeTransport()
        let runner = DurableTaskRunner(db: db, transport: transport)
        let task = try runner.submit(type: "exec.command", deviceIDs: [device.id], parameters: #"{"command": "uptime"}"#)
        try runner.dispatchPending()
        XCTAssertEqual(try SQLiteTaskRepository(db: db).load(task.id)?.state, .waitingForTarget)

        // Target comes back online; the next dispatch cycle executes.
        var back = device
        back.lifecycle = .online
        try SQLiteDeviceRepository(db: db).upsert(back)
        try runner.dispatchPending()
        let loaded = try SQLiteTaskRepository(db: db).load(task.id)
        XCTAssertEqual(loaded?.state, .success)
        XCTAssertEqual(transport.executedCommands, ["uptime"])
    }

    // MARK: Restart survives

    func testTaskStateSurvivesAppRestart() throws {
        let db = try tempDB()
        let device = try onlineDevice(db, hostname: "a", online: false)
        let runner = DurableTaskRunner(db: db, transport: FakeTransport())
        let task = try runner.submit(type: "exec.command", deviceIDs: [device.id], parameters: "{}")
        try runner.dispatchPending()

        // "Restart": new runner over the same database.
        let fresh = DurableTaskRunner(db: db, transport: FakeTransport())
        let pending = try fresh.resumeAfterRestart()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, task.id)
        XCTAssertEqual(pending.first?.state, .waitingForTarget)
    }

    // MARK: Partial fleet failure survives (per-target independence)

    func testPartialFleetFailureSurvives() throws {
        let db = try tempDB()
        let good = try onlineDevice(db, hostname: "good", online: true)
        let bad = try onlineDevice(db, hostname: "bad", online: true)
        let transport = FakeTransport(failHosts: ["bad"])
        let runner = DurableTaskRunner(db: db, transport: transport)
        let task = try runner.submit(type: "exec.command", deviceIDs: [good.id, bad.id], parameters: "{}")
        try runner.dispatchPending()
        let repo = SQLiteTaskRepository(db: db)
        let loaded = try repo.load(task.id)
        // Mixed outcome finalizes the task record as failed (per-target
        // results retain both outcomes; retries create new work — Plan 08 §6).
        XCTAssertEqual(loaded?.state, .failed)
        let results = try db.query("SELECT device_id, state FROM task_targets WHERE task_id = ?", bindings: [task.id.rawValue])
        XCTAssertEqual(results.count, 2, "per-target results recorded")
        let states = Set(results.compactMap { $0.opt("state") })
        XCTAssertTrue(states.contains("success"))
        XCTAssertTrue(states.contains("failed"))
    }

    // MARK: Duplicate execution prevented (idempotency key)

    func testDuplicateExecutionPrevented() throws {
        let db = try tempDB()
        let device = try onlineDevice(db, hostname: "x", online: true)
        let runner = DurableTaskRunner(db: db, transport: FakeTransport())
        _ = try runner.submit(type: "pkg.install", deviceIDs: [device.id], idempotencyKey: "install-vim-1", parameters: "{}")
        XCTAssertThrowsError(try runner.submit(type: "pkg.install", deviceIDs: [device.id], idempotencyKey: "install-vim-1", parameters: "{}")) { error in
            guard case PersistenceError.duplicateIdempotencyKey = error else {
                return XCTFail("expected duplicateIdempotencyKey, got \(error)")
            }
        }
    }

    // MARK: Cancellation persisted

    func testCancellationPersistedAcrossRestart() throws {
        let db = try tempDB()
        let device = try onlineDevice(db, hostname: "c", online: false)
        let runner = DurableTaskRunner(db: db, transport: FakeTransport())
        let task = try runner.submit(type: "exec.command", deviceIDs: [device.id], parameters: "{}")
        try runner.cancel(taskID: task.id)
        // Reload through a fresh runner ("restart") — cancellation survives.
        let fresh = DurableTaskRunner(db: db, transport: FakeTransport())
        let pending = try fresh.resumeAfterRestart()
        XCTAssertTrue(pending.isEmpty, "cancelled task is terminal; not resumed")
        XCTAssertEqual(try SQLiteTaskRepository(db: db).load(task.id)?.state, .cancelled)
    }

    // MARK: Scheduler persistence (Plan 08 A1.2 — canonical DB)

    func testSchedulePersistsInCanonicalDatabase() throws {
        let db = try tempDB()
        let repo = SQLiteScheduleRepository(db: db)
        let schedule = ScheduleDefinitionDB(
            taskTemplateID: nil,
            kind: .rrule,
            rrule: "FREQ=WEEKLY;BYDAY=FR;BYHOUR=22",
            runAt: nil,
            predicate: nil,
            enabled: true
        )
        try repo.upsert(schedule)
        let loaded = try repo.load(schedule.id)
        XCTAssertEqual(loaded?.kind, .rrule)
        XCTAssertEqual(loaded?.rrule, "FREQ=WEEKLY;BYDAY=FR;BYHOUR=22")
        XCTAssertEqual(loaded?.enabled, true)
        // JSON schedules remain importable for one release cycle (A1.2 migration path).
        let jsonPayload = #"{"name":"backup","taskName":"backup","trigger":{"daily":{"hour":3,"minute":0}}}"#
        let migrated = try ScheduleDefinitionDB.fromLegacyJSON(jsonPayload)
        XCTAssertEqual(migrated.kind, .once)
        XCTAssertEqual(migrated.predicate, "legacy.daily.3:0", "legacy trigger preserved as a marker for the Plan 08 scheduler")
    }
}

/// Fake remote transport for durable-runner tests.
final class FakeTransport: RemoteTransport, @unchecked Sendable {
    let failHosts: Set<String>
    private(set) var executedCommands: [String] = []

    init(failHosts: Set<String> = []) {
        self.failHosts = failHosts
    }

    func execute(device: Device, command: String) -> ExecOutcome {
        executedCommands.append(command)
        if failHosts.contains(device.hostname) {
            return ExecOutcome(exitCode: 1, stdout: "", stderr: "simulated failure")
        }
        return ExecOutcome(exitCode: 0, stdout: "ok", stderr: "")
    }
}
