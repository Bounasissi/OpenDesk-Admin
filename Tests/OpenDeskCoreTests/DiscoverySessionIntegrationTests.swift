import XCTest
@testable import OpenDeskCore

/// §25 gap #26 + Plan 17 §4-5: GUI-discovery concurrency wired into the
/// central observe session manager, plus resource-leak monitoring over a
/// sustained churn workload.
final class DiscoverySessionIntegrationTests: XCTestCase {

    func testDiscoveredDevicesBecomeSessionsWithoutDuplicateOwnership() throws {
        // A discovery burst (concurrent observations) resolves into exactly one
        // session per device in the central manager — no double-ownership.
        let manager = ObserveSessionManager(maxSessions: 16)
        let devices = (0..<8).map { Device(hostname: "fleet-\($0)", lifecycle: .online) }
        var sessionIDs: [SessionID] = []
        let lock = NSLock()
        let group = DispatchGroup()
        // Concurrent opens (the GUI wiring opens sessions as discovery resolves).
        for device in devices {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                if let record = try? manager.open(device: device) {
                    lock.lock()
                    sessionIDs.append(record.id)
                    lock.unlock()
                }
            }
        }
        group.wait()
        XCTAssertEqual(manager.sessionCount, 8, "8 devices → 8 sessions under concurrency")
        XCTAssertEqual(Set(sessionIDs).count, 8, "session IDs unique — no duplicate ownership")
        // Grid plan for the observed count is valid at tier thumbnail.
        let plan = try ObserveSessionManager.gridPlan(columns: 8)
        XCTAssertEqual(plan.visibleSessions, 8)
    }

    func testSustainedSessionChurnIsBounded() throws {
        // Plan 17 §5 (resource leak monitoring): repeated open/close cycles
        // must not grow session-table state beyond the live set.
        let manager = ObserveSessionManager(maxSessions: 16)
        let startMemory = MemoryFootprint.snapshot().residentBytes
        for cycle in 0..<200 {
            let session = try manager.open(device: Device(hostname: "churn-\(cycle)", lifecycle: .online))
            try manager.close(sessionID: session.id)
            _ = cycle
        }
        XCTAssertEqual(manager.sessionCount, 0, "all sessions closed — no residual ownership")
        let growth = MemoryFootprint.snapshot().residentBytes - startMemory
        XCTAssertLessThan(growth, 32 * 1_048_576, "churn must be memory-bounded (growth: \(growth / 1_048_576)MB)")
    }

    func testFailureInjectionTransportFailureKeepsFleetRunning() throws {
        // Plan 17 §6 (failure injection): a transport hard-failure on one
        // target must not tear down the fleet task state.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-fail-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("t.db").path)
        _ = try SQLiteMigrator(db: db).run()
        let good = Device(hostname: "good-host", lifecycle: .online)
        let bad = Device(hostname: "bad-host", lifecycle: .online)
        try SQLiteDeviceRepository(db: db).upsert(good)
        try SQLiteDeviceRepository(db: db).upsert(bad)
        let runner = DurableTaskRunner(db: db, transport: FakeTransport(failHosts: ["bad-host"]))
        let task = try runner.submit(type: "exec.command", deviceIDs: [good.id, bad.id], parameters: #"{"command":"true"}"#)
        try runner.dispatchPending()
        let repo = SQLiteTaskRepository(db: db)
        XCTAssertEqual(try repo.load(task.id)?.state, .failed, "all-targets-failed-criteria documented")
        let targets = try db.query("SELECT device_id, state FROM task_targets WHERE task_id = ?", bindings: [task.id.rawValue])
        let states = Set(targets.compactMap { $0.opt("state") })
        XCTAssertTrue(states.contains("success"), "good target's result retained after bad target failure")
        XCTAssertTrue(states.contains("failed"))
        // Re-dispatch after "failure" must not re-execute terminal tasks.
        let executedAgain = try runner.dispatchPending()
        XCTAssertTrue(executedAgain.isEmpty, "terminal task not re-executed")
    }
}
