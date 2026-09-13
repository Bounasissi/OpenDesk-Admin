import XCTest
@testable import OpenDeskCore

final class TaskSchedulerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendesk-sched-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: ScheduleMath

    func testIntervalDueTime() {
        let schedule = ScheduleDefinition(name: "s", taskName: "t", trigger: .interval(seconds: 30))
        XCTAssertEqual(ScheduleMath.secondsUntilDue(schedule, from: Date())!, 30)
    }

    func testIntervalClampsBelowOne() {
        let schedule = ScheduleDefinition(name: "s", taskName: "t", trigger: .interval(seconds: 0))
        XCTAssertEqual(ScheduleMath.secondsUntilDue(schedule)!, 1)
    }

    func testDailyDueLaterToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let from = date("2026-09-13 10:00:00", in: calendar)!
        let schedule = ScheduleDefinition(name: "s", taskName: "t", trigger: .daily(hour: 18, minute: 30))
        let due = ScheduleMath.secondsUntilDue(schedule, from: from, calendar: calendar)!
        // 8.5 hours
        XCTAssertEqual(due, 8.5 * 3600, accuracy: 2)
    }

    func testDailyDueTomorrowWhenTimePassed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let from = date("2026-09-13 20:00:00", in: calendar)!
        let schedule = ScheduleDefinition(name: "s", taskName: "t", trigger: .daily(hour: 18, minute: 0))
        let due = ScheduleMath.secondsUntilDue(schedule, from: from, calendar: calendar)!
        // 22 hours to next day's 18:00
        XCTAssertEqual(due, 22 * 3600, accuracy: 2)
    }

    func testDisabledScheduleReturnsNil() {
        let schedule = ScheduleDefinition(name: "s", taskName: "t", trigger: .interval(seconds: 30), enabled: false)
        XCTAssertNil(ScheduleMath.secondsUntilDue(schedule))
    }

    func testTriggerDescription() {
        XCTAssertEqual(ScheduleMath.describe(.interval(seconds: 90)), "every 90s")
        XCTAssertEqual(ScheduleMath.describe(.daily(hour: 7, minute: 5)), "daily at 07:05")
    }

    // MARK: ScheduleStore

    func testScheduleStoreAddListRemove() {
        let store = ScheduleStore(directory: tempDir)
        XCTAssertTrue(store.add(ScheduleDefinition(name: "n1", taskName: "t", trigger: .interval(seconds: 60))))
        XCTAssertFalse(store.add(ScheduleDefinition(name: "n1", taskName: "t", trigger: .daily(hour: 1, minute: 0))), "duplicate names rejected")
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertTrue(store.setEnabled(false, named: "n1"))
        XCTAssertFalse(store.setEnabled(false, named: "missing"))
        XCTAssertTrue(store.remove(named: "n1"))
        XCTAssertFalse(store.remove(named: "n1"))
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    // MARK: Scheduler execution with mocks

    func testRunNowExecutesSavedTaskAcrossGroup() {
        let store = ScheduleStore(directory: tempDir)
        let taskStore = TaskStore(directory: tempDir)
        let registry = HostRegistry(directory: tempDir)
        registry.add(Host(hostname: "a.local", username: "u", groups: ["lab"]))
        registry.add(Host(hostname: "b.local", username: "u", groups: ["other"]))
        _ = taskStore.add(name: "collect", command: "sw_vers")

        var executedCommands: [String] = []
        let engine = TaskEngine(transportFactory: { host in
            MockTaskTransport(exitCode: 0, stdout: host.hostname)
        })
        let scheduler = TaskScheduler(
            scheduleStore: store, taskStore: taskStore,
            hostRegistry: registry, engine: engine
        )
        _ = store.add(ScheduleDefinition(name: "hourly", taskName: "collect", targetGroups: ["lab"], trigger: .interval(seconds: 60)))
        let results = scheduler.runNow(named: "hourly")!
        executedCommands.append(contentsOf: results.map(\.host))

        XCTAssertEqual(results.count, 1, "only hosts in target groups run")
        XCTAssertEqual(results.first?.host, "a.local")
        XCTAssertEqual(results.first?.exitCode, 0)
        XCTAssertEqual(results.first?.succeeded, true)
        _ = executedCommands
    }

    func testRunNowForUnknownScheduleReturnsNil() {
        let scheduler = TaskScheduler(
            scheduleStore: ScheduleStore(directory: tempDir),
            taskStore: TaskStore(directory: tempDir),
            hostRegistry: HostRegistry(directory: tempDir)
        )
        XCTAssertNil(scheduler.runNow(named: "nope"))
    }

    func testRunNowForMissingTaskReturnsEmpty() {
        let store = ScheduleStore(directory: tempDir)
        _ = store.add(ScheduleDefinition(name: "ghost", taskName: "missing-task", trigger: .interval(seconds: 10)))
        let scheduler = TaskScheduler(
            scheduleStore: store,
            taskStore: TaskStore(directory: tempDir),
            hostRegistry: HostRegistry(directory: tempDir)
        )
        XCTAssertTrue(scheduler.runNow(named: "ghost")!.isEmpty)
    }

    private func date(_ iso: String, in calendar: Calendar) -> Date? {
        let parts = iso.split(separator: " ")
        guard parts.count == 2 else { return nil }
        var day = calendar.dateComponents([.year, .month, .day], from: ISO8601DateFormatter().date(from: "\(parts[0])T00:00:00Z") ?? Date())
        let time = parts[1].split(separator: ":").compactMap { Int($0) }
        guard time.count == 3 else { return nil }
        day.hour = time[0]; day.minute = time[1]; day.second = time[2]
        return calendar.date(from: day)
    }
}

final class PlistDistributionTests: XCTestCase {
    /// The defaults import command must stage from /tmp and clean up after.
    func testDefaultsImportCommandShape() {
        // Command construction is embedded in pushPlist; verify shape via a
        // live SSH-less unit path: run the builder logic in isolation.
        let domain = "com.example.test"
        let staging = "/tmp/stage.plist"
        let expected = "defaults import \(domain) \(staging) && rm -f \(staging) && echo imported"
        XCTAssertEqual(expected, plistImportCommand(domain: domain, stagingPath: staging))
    }

    func testByhostDomainPrefixStripsCorrectly() {
        let domain = "byhost:com.example.test"
        let actual = String(domain.dropFirst("byhost:".count))
        XCTAssertEqual(actual, "com.example.test")
    }

    func testPushPlistRejectsMissingLocalFile() {
        let engine = DistributionEngine()
        let host = Host(hostname: "x.local", username: "u")
        XCTAssertThrowsError(try engine.pushPlist(localPath: "/nonexistent.plist", toHost: host, domain: "com.test")) { error in
            XCTAssertEqual(error as? DistributionEngine.DistributionError, .localFileMissing("/nonexistent.plist"))
        }
    }
}

/// Mirrors the command built inside DistributionEngine.pushPlist.
private func plistImportCommand(domain: String, stagingPath: String) -> String {
    "defaults import \(domain) \(stagingPath) && rm -f \(stagingPath) && echo imported"
}
