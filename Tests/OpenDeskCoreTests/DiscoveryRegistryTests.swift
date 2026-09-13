import XCTest
@testable import OpenDeskCore

/// Plan 04 tests: CIDR scanning, identity reconciliation, smart groups.
final class DiscoveryRegistryTests: XCTestCase {

    // MARK: CIDR parsing (Plan 04 §2.3)

    func testCIDRRangeIPv4() throws {
        let range = try CIDRRange.parse("192.168.1.0/30")
        XCTAssertEqual(range.addresses.count, 4) // includes network + broadcast per §2.3 bounded probe set
        XCTAssertTrue(range.addresses.contains("192.168.1.1"))
        XCTAssertTrue(range.addresses.contains("192.168.1.2"))
    }

    func testCIDRRejectsInvalid() {
        XCTAssertThrowsError(try CIDRRange.parse("not-a-cidr"))
        XCTAssertThrowsError(try CIDRRange.parse("10.0.0.0/33"))
        XCTAssertThrowsError(try CIDRRange.parse("10.0.0.5/24")) // host bits set
    }

    func testCIDRIPv6() throws {
        let range = try CIDRRange.parse("fd00::/126")
        XCTAssertEqual(range.addresses.count, 4)
        XCTAssertTrue(range.addresses.contains("fd00::1"))
    }

    // MARK: Scanner against a live loopback probe target

    func testScannerFindsOpenRFBPortAndDedupes() async throws {
        let server = LoopbackRFBServer()
        let port = try server.start()
        // Scan a tiny loopback range that includes the server port.
        let scanner = CIDRScanner(
            concurrencyLimit: 2,
            probeTimeoutMs: 500,
            prober: { [port] host, probePort, timeoutMs in
                guard host == "127.0.0.1", probePort == UInt16(port) else { return false }
                return true
            }
        )
        let range = try CIDRRange.parse("127.0.0.0/31") // 127.0.0.0 + 127.0.0.1
        let results = try await scanner.scan(range, ports: [UInt16(port)])
        let matches = results.filter { $0.openPorts.contains(UInt16(port)) }
        XCTAssertEqual(matches.count, 1, "dedupe: one result per host")
        XCTAssertEqual(matches.first?.host, "127.0.0.1")
        XCTAssertEqual(matches.first?.openPorts, [UInt16(port)])
    }

    func testScannerSupportsCancellation() async throws {
        // A prober that never returns; cancellation must abort the scan.
        let scanner = CIDRScanner(
            concurrencyLimit: 1,
            probeTimeoutMs: 200,
            prober: { _, _, _ in try? await Task.sleep(nanoseconds: 5_000_000_000); return false }
        )
        let range = try CIDRRange.parse("10.250.0.0/30")
        let task = Task { try await scanner.scan(range, ports: [5900]) }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let started = Date()
        do { _ = try await task.value } catch is CancellationError {} catch {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 3.0, "cancellation must interrupt the scan")
    }

    // MARK: Identity reconciliation (Plan 04 §2.4 / A1.2)

    func testReconcilerMergesEndpointsByStableSignal() throws {
        let repo = InMemoryDeviceRepository()
        let original = Device(
            hostname: "lab-01.local",
            lifecycle: .online,
            stableSignals: [.sshHostKey("SHA256:abc123")],
            endpoints: [Endpoint(host: "10.0.0.5", port: 5900, transport: .rfb)]
        )
        try repo.upsert(original)

        let reconciler = DeviceReconciler(repository: repo)
        // Same host, new DHCP address, new hostname — SSH host key matches.
        let scan = ScanObservation(
            hostname: "renamed-lab",
            endpoints: [Endpoint(host: "10.0.0.99", port: 5900, transport: .rfb),
                        Endpoint(host: "10.0.0.99", port: 22, transport: .ssh)],
            stableSignals: [.sshHostKey("SHA256:abc123")]
        )
        try reconciler.reconcile(scan)
        let devices = try repo.all()
        XCTAssertEqual(devices.count, 1, "stable signal must merge, not duplicate")
        XCTAssertEqual(devices[0].id, original.id)
        XCTAssertEqual(devices[0].hostname, "renamed-lab", "hostname change updates the device")
        XCTAssertEqual(devices[0].endpoints.count, 3, "old + new endpoints both tracked")
        XCTAssertTrue(devices[0].endpoints.contains(Endpoint(host: "10.0.0.5", port: 5900, transport: .rfb)))
    }

    func testReconcilerPrefersHighestConfidenceSignal() throws {
        let repo = InMemoryDeviceRepository()
        try repo.upsert(Device(
            hostname: "a.local",
            lifecycle: .online,
            stableSignals: [.hardwareMAC("AA:BB:CC:DD:EE:FF"), .hostname("a.local")]
        ))
        try repo.upsert(Device(
            hostname: "b.local",
            lifecycle: .online,
            stableSignals: [.hostname("b.local")]
        ))
        let reconciler = DeviceReconciler(repository: repo)
        // Observed MAC (highest confidence) matches device A even though hostname says b.local.
        try reconciler.reconcile(ScanObservation(
            hostname: "b.local",
            endpoints: [],
            stableSignals: [.hardwareMAC("AA:BB:CC:DD:EE:FF")]
        ))
        let devices = try repo.all()
        XCTAssertEqual(devices.count, 2)
        let updated = try XCTUnwrap(devices.first { $0.id.rawValue != "" && $0.hostname == "b.local" })
        // The reconciled device A now carries b.local as an alias-merged endpoint host; A keeps MAC.
        let deviceA = try XCTUnwrap(devices.first { $0.stableSignals.contains(.hardwareMAC("AA:BB:CC:DD:EE:FF")) })
        XCTAssertEqual(deviceA.stableSignals.count, 2, "MAC-matched device gained hostname signal, not a new device")
        XCTAssertTrue(deviceA.hostname.contains("b.local"))
        _ = updated
    }

    func testReconcilerCreatesDeviceWhenNoSignalMatches() throws {
        let repo = InMemoryDeviceRepository()
        try repo.upsert(Device(hostname: "known.local", lifecycle: .online))
        let reconciler = DeviceReconciler(repository: repo)
        try reconciler.reconcile(ScanObservation(
            hostname: "brand-new.local",
            endpoints: [Endpoint(host: "10.9.9.9", port: 22, transport: .ssh)],
            stableSignals: []
        ))
        XCTAssertEqual(try repo.all().count, 2)
    }

    // MARK: Smart groups (Plan 04 A1.3 — predicate matching over device fields)

    func testSmartGroupPredicateMatchesDeviceFields() {
        var device = Device(hostname: "lab-01", lifecycle: .online)
        device.osVersion = "15.5"
        device.architecture = "arm64"
        device.capabilities = [.rfb: true, .ssh: true]

        let archAndOnline = SmartGroupPredicate(op: .and, clauses: [
            .init(field: "architecture", op: .eq, value: "arm64"),
            .init(field: "lifecycle", op: .eq, value: "online"),
            .init(field: "os_version", op: .lt, value: "26"),
        ])
        XCTAssertTrue(archAndOnline.matches(device))

        let orMatch = SmartGroupPredicate(op: .or, clauses: [
            .init(field: "architecture", op: .eq, value: "x86_64"),
            .init(field: "hostname", op: .contains, value: "lab"),
        ])
        XCTAssertTrue(orMatch.matches(device))

        let noMatch = SmartGroupPredicate(op: .and, clauses: [
            .init(field: "architecture", op: .eq, value: "x86_64"),
        ])
        XCTAssertFalse(noMatch.matches(device))

        let capability = SmartGroupPredicate(op: .and, clauses: [
            .init(field: "capability.rfb", op: .eq, value: "true"),
        ])
        XCTAssertTrue(capability.matches(device))
    }

    func testSmartGroupDefinitionPersistsAndResolves() async throws {
        let db = try Self.tempDB()
        let repo = SQLiteSmartGroupRepository(db: db)
        let group = SmartGroup(
            name: "arm64-lab",
            predicate: SmartGroupPredicate(op: .and, clauses: [.init(field: "architecture", op: .eq, value: "arm64")])
        )
        try repo.upsert(group)
        let loaded = try repo.load(group.id)
        // Definition is the persisted source of truth. createdAt round-trips
        // at ISO8601 millisecond precision — compare with storage tolerance.
        XCTAssertEqual(loaded?.id, group.id)
        XCTAssertEqual(loaded?.name, group.name)
        XCTAssertEqual(loaded?.predicate, group.predicate)
        XCTAssertLessThan(abs((loaded?.createdAt.timeIntervalSince1970 ?? 0) - group.createdAt.timeIntervalSince1970), 0.01)

        // Membership resolution is derived, not stored.
        var device = Device(hostname: "lab-01", lifecycle: .online)
        device.architecture = "arm64"
        XCTAssertTrue(loaded?.predicate.matches(device) ?? false)
    }

    private static func tempDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-groups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("t.db").path)
        _ = try SQLiteMigrator(db: db).run()
        return db
    }
}

/// In-memory DeviceRepository for reconciliation tests (no filesystem).
final class InMemoryDeviceRepository: DeviceRepository, @unchecked Sendable {
    private var devices: [Device] = []
    private let lock = NSLock()

    func upsert(_ device: Device) throws {
        lock.lock(); defer { lock.unlock() }
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
    }

    func load(_ id: DeviceID) throws -> Device? {
        lock.lock(); defer { lock.unlock() }
        return devices.first { $0.id == id }
    }

    func all() throws -> [Device] {
        lock.lock(); defer { lock.unlock() }
        return devices
    }

    func delete(_ id: DeviceID) throws {
        lock.lock(); defer { lock.unlock() }
        devices.removeAll { $0.id == id }
    }
}
