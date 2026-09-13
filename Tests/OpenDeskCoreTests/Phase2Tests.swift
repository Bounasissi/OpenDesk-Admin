import XCTest
@testable import OpenDeskCore

/// Scripted in-memory transport for task engine tests.
final class MockTaskTransport: CommandTransport {
    var scriptedExitCode: Int32
    var scriptedStdout: String
    var scriptedError: Error?
    private(set) var callCount = 0

    init(exitCode: Int32 = 0, stdout: String = "", error: Error? = nil) {
        self.scriptedExitCode = exitCode
        self.scriptedStdout = stdout
        self.scriptedError = error
    }

    func run(command: String, timeoutSeconds: Int?) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        callCount += 1
        if let scriptedError { throw scriptedError }
        return (scriptedStdout, "", scriptedExitCode)
    }

    func ping() -> Bool { true }
}

final class TaskEngineConcurrencyTests: XCTestCase {
    func testAcrossHostsPreservesOrder() {
        let engine = TaskEngine(transportFactory: { host in
            MockTaskTransport(exitCode: 0, stdout: host.hostname)
        })
        let hosts = (0..<20).map { Host(hostname: "host-\($0).local", username: "admin") }
        let results = engine.runAcrossHosts("true", hosts: hosts, maxConcurrency: 4)
        XCTAssertEqual(results.count, 20)
        for (index, result) in results.enumerated() {
            XCTAssertEqual(result.host, hosts[index].hostname, "results must stay in input order")
            XCTAssertTrue(result.succeeded)
        }
    }

    func testAcrossHostsAggregatesFailures() {
        let engine = TaskEngine(transportFactory: { host in
            if host.hostname.contains("bad") {
                return MockTaskTransport(error: SSHTransport.TransportError.hostUnreachable(host.hostname))
            }
            return MockTaskTransport(exitCode: 0)
        })
        let hosts = [
            Host(hostname: "good.local", username: "admin"),
            Host(hostname: "bad.local", username: "admin"),
        ]
        let results = engine.runAcrossHosts("true", hosts: hosts)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].succeeded)
        XCTAssertFalse(results[1].succeeded)
        XCTAssertTrue(results[1].errorDescription?.contains("unreachable") == true)
    }

    func testAcrossHostsWithEmptyRoster() {
        let engine = TaskEngine(transportFactory: { _ in MockTaskTransport() })
        XCTAssertTrue(engine.runAcrossHosts("true", hosts: []).isEmpty)
    }

    func testEachHostGetsOwnTransport() {
        var constructed = 0
        let engine = TaskEngine(transportFactory: { _ in
            constructed += 1
            return MockTaskTransport()
        })
        let hosts = (0..<5).map { Host(hostname: "h\($0).local", username: "u") }
        _ = engine.runAcrossHosts("true", hosts: hosts)
        XCTAssertEqual(constructed, 5)
    }
}

final class TaskStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendesk-taskstore-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAddListAndNameLookup() {
        let store = TaskStore(directory: tempDir)
        XCTAssertNotNil(store.add(name: "uptime", command: "uptime"))
        XCTAssertNil(store.add(name: "uptime", command: "sw_vers"), "duplicate names rejected")
        XCTAssertEqual(store.task(named: "uptime")?.command, "uptime")
        XCTAssertEqual(store.loadAll().count, 1)
    }

    func testUpdateBumpsVersion() {
        let store = TaskStore(directory: tempDir)
        let task = store.add(name: "t1", command: "cmd1", timeoutSeconds: 5)!
        let updated = store.update(id: task.id, command: "cmd2")!
        XCTAssertEqual(updated.version, 2)
        XCTAssertEqual(updated.command, "cmd2")
        XCTAssertEqual(updated.timeoutSeconds, 5, "unspecified fields preserved")
    }

    func testRemoveAndPersistence() {
        let store = TaskStore(directory: tempDir)
        let task = store.add(name: "t2", command: "c")!
        store.remove(id: task.id)
        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertNil(store.task(named: "t2"))
    }
}

final class WakeOnLANTests: XCTestCase {
    func testMagicPacketLayout() throws {
        let packet = try WakeOnLAN.magicPacket(mac: "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(packet.count, 102)
        for byte in packet.prefix(6) { XCTAssertEqual(byte, 0xFF) }
        // 16 repetitions of the MAC
        let mac = packet.subdata(in: 6..<packet.count)
        XCTAssertEqual(mac.count, 96)
        for block in stride(from: 0, to: 96, by: 6) {
            XCTAssertEqual(Array(mac)[block], 0xAA)
            XCTAssertEqual(Array(mac)[block + 5], 0xFF)
        }
    }

    func testMacFormatVariants() throws {
        let colon = try WakeOnLAN.magicPacket(mac: "AA:BB:CC:DD:EE:FF")
        let hyphen = try WakeOnLAN.magicPacket(mac: "AA-BB-CC-DD-EE-FF")
        let compact = try WakeOnLAN.magicPacket(mac: "aabbccddeeff")
        XCTAssertEqual(colon, hyphen)
        XCTAssertEqual(colon, compact)
    }

    func testInvalidMACThrows() {
        XCTAssertThrowsError(try WakeOnLAN.magicPacket(mac: "not-a-mac"))
        XCTAssertThrowsError(try WakeOnLAN.magicPacket(mac: "AA:BB:CC:DD:EE"))
        XCTAssertThrowsError(try WakeOnLAN.magicPacket(mac: "AA:BB:CC:DD:EE:GG"))
    }

    func testWakeHostWithoutMACThrows() {
        let host = Host(hostname: "x.local", username: "u")
        XCTAssertThrowsError(try WakeOnLAN.wake(host: host))
    }
}

final class ReportExporterTests: XCTestCase {
    func testResultsCSVQuotingAndLayout() throws {
        let result = TaskResult(
            taskId: UUID(), host: "mac1.local", exitCode: 1,
            stdout: "line1\nline2", stderr: "", errorDescription: "boom, big",
            durationMs: 12
        )
        let csv = ReportExporter.resultsCSV([result])
        // Quoted field content keeps raw newlines inside quotes (RFC 4180).
        XCTAssertTrue(csv.contains("\"line1\nline2\""), "embedded newline must be quoted")
        XCTAssertTrue(csv.contains("\"boom, big\""), "embedded comma must be quoted")

        // Row-aware CSV parse must recover exactly 8 fields from the data row.
        let rows = parseCSVDocument(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["host", "exit_code", "succeeded", "duration_ms", "started_at", "stdout", "stderr", "error"])
        XCTAssertEqual(rows[1].count, 8)
        XCTAssertEqual(rows[1][0], "mac1.local")
        XCTAssertEqual(rows[1][7], "boom, big")
        XCTAssertTrue(rows[1][5].contains("line2"), "stdout field survives quoting")
    }

    /// RFC 4180 document parser: rows separated by newlines, quoted fields
    /// may contain commas and newlines.
    private func parseCSVDocument(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        func endField() {
            fields.append(current)
            current = ""
        }
        func endRow() {
            endField()
            rows.append(fields)
            fields = []
        }

        var iterator = text.makeIterator()
        var pending = iterator.next()
        while let char = pending {
            if inQuotes {
                if char == "\"" {
                    let next = iterator.next()
                    if next == "\"" { current.append("\"") }
                    else { inQuotes = false; pending = next; continue }
                } else {
                    current.append(char)
                }
            } else {
                switch char {
                case "\"": inQuotes = true
                case ",": endField()
                case "\n": endRow()
                case "\r": break
                default: current.append(char)
                }
            }
            pending = iterator.next()
        }
        if !fields.isEmpty || !current.isEmpty { endRow() }
        return rows
    }

    func testReportsCSV() throws {
        let report = MachineReport(
            hostname: "m1", modelName: "MacBook Pro", chipArchitecture: "arm64",
            osVersion: "15.0", serialNumber: "S1", totalMemoryMB: 8192,
            uptimeSeconds: nil, installedApps: [], collectedAt: Date()
        )
        let csv = ReportExporter.reportsCSV([report])
        XCTAssertTrue(csv.contains("m1,MacBook Pro,arm64,15.0,S1,8192,"))
        let json = try ReportExporter.reportsJSON([report])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // matches the exporter's encoding
        let decoded = try decoder.decode([MachineReport].self, from: json)
        XCTAssertEqual(decoded.first?.hostname, "m1")
    }

    func testAppsCSV() {
        let report = MachineReport(
            hostname: "m1", modelName: "X", chipArchitecture: "arm64", osVersion: "15.0",
            serialNumber: "S", totalMemoryMB: 8, uptimeSeconds: nil,
            installedApps: [MachineReport.AppEntry(name: "Terminal", version: "2.14", path: "/System/Applications/Utilities/Terminal.app")],
            collectedAt: Date()
        )
        let csv = ReportExporter.appsCSV([report])
        XCTAssertTrue(csv.contains("m1,Terminal,2.14"))
        XCTAssertEqual(csv.components(separatedBy: "\n").count, 2)
    }
}

