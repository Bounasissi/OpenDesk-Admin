import XCTest
@testable import OpenDeskCore

final class HostRegistryTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendesk-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAddAndLoadHosts() {
        let registry = HostRegistry(directory: tempDir)
        registry.add(Host(hostname: "mac1.local", username: "admin", groups: ["lab"]))
        registry.add(Host(hostname: "mac2.local", username: "admin"))
        let hosts = registry.loadAll()
        XCTAssertEqual(hosts.count, 2)
        XCTAssertTrue(hosts.contains { $0.hostname == "mac1.local" })
    }

    func testAddIsIdempotentPerHostnameUser() {
        let registry = HostRegistry(directory: tempDir)
        registry.add(Host(hostname: "mac1.local", username: "admin"))
        registry.add(Host(hostname: "mac1.local", username: "admin"))
        XCTAssertEqual(registry.loadAll().count, 1)
    }

    func testRemoveHost() {
        let registry = HostRegistry(directory: tempDir)
        let host = Host(hostname: "mac1.local", username: "admin")
        registry.add(host)
        registry.remove(id: host.id)
        XCTAssertTrue(registry.loadAll().isEmpty)
    }

    func testFilterByGroups() {
        let registry = HostRegistry(directory: tempDir)
        registry.add(Host(hostname: "a.local", username: "u", groups: ["lab-1"]))
        registry.add(Host(hostname: "b.local", username: "u", groups: ["lab-2"]))
        registry.add(Host(hostname: "c.local", username: "u", groups: ["lab-1", "staff"]))

        XCTAssertEqual(registry.hosts(inGroups: ["lab-1"]).count, 2)
        XCTAssertEqual(registry.hosts(inGroups: ["staff"]).count, 1)
        XCTAssertEqual(registry.hosts(inGroups: []).count, 3) // empty = all
    }

    func testPersistenceAcrossInstances() {
        HostRegistry(directory: tempDir).add(Host(hostname: "persist.local", username: "u"))
        let reloaded = HostRegistry(directory: tempDir).loadAll()
        XCTAssertEqual(reloaded.first?.hostname, "persist.local")
    }
}

final class TaskResultTests: XCTestCase {
    func testSucceededOnlyWhenExitZeroAndNoError() {
        let ok = TaskResult(taskId: UUID(), host: "h", exitCode: 0, durationMs: 1)
        XCTAssertTrue(ok.succeeded)

        let failed = TaskResult(taskId: UUID(), host: "h", exitCode: 1, stderr: "boom", durationMs: 1)
        XCTAssertFalse(failed.succeeded)

        let errored = TaskResult(taskId: UUID(), host: "h", exitCode: 0, errorDescription: "timeout", durationMs: 1)
        XCTAssertFalse(errored.succeeded)
    }
}
