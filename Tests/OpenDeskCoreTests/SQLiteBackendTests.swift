import XCTest
@testable import OpenDeskCore

final class SQLiteBackendTests: XCTestCase {
    private var dbPath: String!

    override func setUp() {
        super.setUp()
        dbPath = NSTemporaryDirectory() + "opendesk-registry-\(UUID().uuidString).db"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dbPath)
        super.tearDown()
    }

    func testCRUDRoundTrip() throws {
        let backend = try SQLiteBackend(path: dbPath)
        let host = Host(
            hostname: "mac1.local",
            port: 2222,
            username: "admin",
            authMethod: .password,
            groups: ["lab-1", "staff"],
            screenPort: 5901,
            macAddress: "AA:BB:CC:DD:EE:FF",
            lastSeen: Date(timeIntervalSince1970: 1_789_000_000)
        )
        backend.save([host])

        let loaded = backend.loadAll()
        XCTAssertEqual(loaded.count, 1)
        let round = loaded[0]
        XCTAssertEqual(round.id, host.id)
        XCTAssertEqual(round.hostname, "mac1.local")
        XCTAssertEqual(round.port, 2222)
        XCTAssertEqual(round.username, "admin")
        XCTAssertEqual(round.authMethod, .password)
        XCTAssertEqual(round.groups, ["lab-1", "staff"])
        XCTAssertEqual(round.screenPort, 5901)
        XCTAssertEqual(round.macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(round.lastSeen?.timeIntervalSince1970 ?? 0, 1_789_000_000, accuracy: 1)
    }

    func testReplaceSemantics() throws {
        let backend = try SQLiteBackend(path: dbPath)
        let original = Host(hostname: "mac1.local", username: "admin")
        let replacement = Host(hostname: "mac1.local", username: "admin", groups: ["new-group"])
        backend.save([original])
        backend.save([replacement])
        let loaded = backend.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].groups, ["new-group"])
    }

    func testEmptyRosterLoadsEmpty() throws {
        let backend = try SQLiteBackend(path: dbPath)
        XCTAssertTrue(backend.loadAll().isEmpty)
    }

    func testPersistenceAcrossInstances() throws {
        let first = try SQLiteBackend(path: dbPath)
        first.save([Host(hostname: "persist.local", username: "u")])
        let second = try SQLiteBackend(path: dbPath)
        XCTAssertEqual(second.loadAll().first?.hostname, "persist.local")
    }

    func testHostRegistryWithSQLiteBackend() throws {
        let backend = try SQLiteBackend(path: dbPath)
        let registry = HostRegistry(backend: backend)
        registry.add(Host(hostname: "a.local", username: "u", groups: ["lab"]))
        registry.add(Host(hostname: "b.local", username: "u", groups: ["staff"]))

        XCTAssertEqual(registry.loadAll().count, 2)
        XCTAssertEqual(registry.hosts(inGroups: ["lab"]).map(\.hostname), ["a.local"])
        XCTAssertEqual(registry.hosts(inGroups: []).count, 2)

        let host = registry.loadAll()[0]
        registry.remove(id: host.id)
        XCTAssertEqual(registry.loadAll().count, 1)
    }

    func testManyHostsOrdering() throws {
        let backend = try SQLiteBackend(path: dbPath)
        var hosts = (0..<30).map { Host(hostname: String(format: "host-%02d.local", $0), username: "u") }
        // Insert out of order to verify ORDER BY hostname
        hosts.shuffle()
        backend.save(hosts)
        let loaded = backend.loadAll()
        XCTAssertEqual(loaded.count, 30)
        XCTAssertEqual(loaded.map(\.hostname), loaded.map(\.hostname).sorted())
    }

    func testNilMacRoundTripsAsNil() throws {
        let backend = try SQLiteBackend(path: dbPath)
        backend.save([Host(hostname: "nomac.local", username: "u", macAddress: nil)])
        let loaded = backend.loadAll()
        XCTAssertNil(loaded[0].macAddress)
    }
}
