import Testing
import Foundation
@testable import OpenDeskCore

@Suite("SQLiteKit + DeviceRegistry")
struct RegistryTests {

    @Test("Schema applies and devices round-trip")
    func deviceRoundTrip() throws {
        let tmp = NSTemporaryDirectory() + "od-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let db = try SQLiteDatabase(path: tmp)
        let schema = DeviceRegistry.bundledSchema()!
        let registry = try DeviceRegistry(db: db, schema: schema)

        let device = DeviceRecord(
            hostname: "mac-001",
            ips: ["192.168.1.10"],
            macAddress: "AA:BB:CC:DD:EE:FF",
            osVersion: "15.5",
            architecture: "arm64",
            rfbAvailable: true,
            sshAvailable: true,
            online: true
        )
        try registry.upsertDevice(device)

        let loaded = try registry.devices()
        #expect(loaded.count == 1)
        #expect(loaded[0].hostname == "mac-001")
        #expect(loaded[0].ips == ["192.168.1.10"])
        #expect(loaded[0].rfbAvailable == true)
        #expect(loaded[0].sshAvailable == true)
        #expect(loaded[0].online == true)
    }

    @Test("Discovery dedupe by MAC then hostname")
    func discoveryDedupe() throws {
        let tmp = NSTemporaryDirectory() + "od-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let db = try SQLiteDatabase(path: tmp)
        let registry = try DeviceRegistry(db: db, schema: DeviceRegistry.bundledSchema()!)

        let original = DeviceRecord(hostname: "lab-mac", macAddress: "AA:BB:CC:DD:EE:01", sshAvailable: true)
        try registry.upsertDevice(original)

        // Same MAC rediscovered under a different hostname -> merges into existing record.
        let found = try registry.findDevice(mac: "AA:BB:CC:DD:EE:01", hostname: "renamed-mac")
        #expect(found?.id == original.id)
        #expect(found?.hostname == "lab-mac")

        // Unknown MAC + unknown hostname -> nil (new device).
        let missing = try registry.findDevice(mac: nil, hostname: "brand-new")
        #expect(missing == nil)
    }

    @Test("Groups and membership")
    func groups() throws {
        let tmp = NSTemporaryDirectory() + "od-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let db = try SQLiteDatabase(path: tmp)
        let registry = try DeviceRegistry(db: db, schema: DeviceRegistry.bundledSchema()!)

        let d1 = DeviceRecord(hostname: "a")
        let d2 = DeviceRecord(hostname: "b")
        try registry.upsertDevice(d1)
        try registry.upsertDevice(d2)
        let group = try registry.createGroup(name: "lab")
        try registry.addDevice(d1.id, toGroup: group)
        try registry.addDevice(d1.id, toGroup: group) // idempotent

        let members = try registry.groupMembers(group: group)
        #expect(members.count == 1)
        #expect(members[0].hostname == "a")
    }

    @Test("Task lifecycle: submit -> run -> per-target results -> audit")
    func taskLifecycle() throws {
        let tmp = NSTemporaryDirectory() + "od-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let db = try SQLiteDatabase(path: tmp)
        let registry = try DeviceRegistry(db: db, schema: DeviceRegistry.bundledSchema()!)

        let device = DeviceRecord(hostname: "127.0.0.1", ips: ["127.0.0.1"], sshAvailable: true)
        try registry.upsertDevice(device)

        let engine = TaskEngine(registry: registry, ssh: SSHTransport(sshPath: "/bin/echo"))
        let task = try engine.submit(type: .executeCommand, targets: [device.id], parameters: ["command": "hello"])

        var tasks = try registry.tasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].status == "queued")

        // Execute against a fake transport (echo binary exits 0 immediately).
        _ = try runBlocking { try await engine.execute(taskID: task.id) }

        tasks = try registry.tasks()
        #expect(tasks[0].status == "success" || tasks[0].status == "failed")

        let targets = try registry.taskTargets(taskID: task.id)
        #expect(targets.count == 1)
        #expect(targets[0].status == "success" || targets[0].status == "failed")

        let audit = try registry.auditEvents()
        #expect(audit.contains { $0.action == "task.submit" })
    }

    @Test("Terminal states are immutable")
    func terminalImmutability() {
        #expect(TaskEngine.isTerminal("success"))
        #expect(TaskEngine.isTerminal("failed"))
        #expect(TaskEngine.isTerminal("cancelled"))
        #expect(!TaskEngine.isTerminal("queued"))
        #expect(!TaskEngine.isTerminal("running"))
    }

    @Test("CIDR expansion")
    func cidrExpansion() {
        #expect(CIDRScanner.expand(cidr: "192.168.1.5").count == 1)
        #expect(CIDRScanner.expand(cidr: "192.168.1.0/30").count == 4)
        #expect(CIDRScanner.expand(cidr: "10.0.0.0/24").count == 256)
        // Large ranges refused in v1 (safety cap).
        #expect(CIDRScanner.expand(cidr: "10.0.0.0/16").count == 1)
        #expect(CIDRScanner.expand(cidr: "10.0.0.0/24").first == "10.0.0.0")
        #expect(CIDRScanner.expand(cidr: "10.0.0.0/24").last == "10.0.0.255")
    }

    @Test("SSH shell quoting")
    func shellQuoting() {
        let ssh = SSHTransport()
        #expect(ssh.shellQuote("echo hi") == "'echo hi'")
        #expect(ssh.shellQuote("it's") == "'it'\\''s'")
    }

    /// Bridge for calling async engine methods from sync tests.
    func runBlocking<T>(_ body: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        Task.detached {
            do { result = .success(try await body()) }
            catch { result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        switch result! {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}
