import XCTest
@testable import OpenDeskCore

/// Plan 12 tests: versioned local API over a Unix-domain socket.
/// No unauthenticated TCP exposure; JSON request/response; stable errors.
final class LocalAPITests: XCTestCase {

    private func tempSocketPath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-a-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("s.sock").path
    }

    func testAPIVersionedListDevicesOverUnixSocket() throws {
        let db = try tempDB()
        try SQLiteDeviceRepository(db: db).upsert(Device(hostname: "api-test", lifecycle: .online))
        let server = try LocalAPIServer(socketPath: tempSocketPath(), database: db)
        try server.bind()
        Thread.detachNewThread { try? server.runAcceptLoop() }
        defer { server.stop() }

        try Self.waitReady(server.socketPath)
        let response = try Self.request(socketPath: server.socketPath, request: [
            "version": 1, "action": "devices.list",
        ])
        XCTAssertEqual(response["version"] as? Int, 1)
        XCTAssertEqual(response["ok"] as? Bool, true)
        let devices = try XCTUnwrap(response["devices"] as? [[String: Any]])
        XCTAssertEqual(devices.first?["hostname"] as? String, "api-test")
    }

    func testAPIRejectsUnknownVersion() throws {
        let db = try tempDB()
        let server = try LocalAPIServer(socketPath: tempSocketPath(), database: db)
        try server.bind()
        Thread.detachNewThread { try? server.runAcceptLoop() }
        defer { server.stop() }

        try Self.waitReady(server.socketPath)
        let response = try Self.request(socketPath: server.socketPath, request: [
            "version": 99, "action": "devices.list",
        ])
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "unsupported version")
    }

    func testAPIRejectsUnknownAction() throws {
        let db = try tempDB()
        let server = try LocalAPIServer(socketPath: tempSocketPath(), database: db)
        try server.bind()
        Thread.detachNewThread { try? server.runAcceptLoop() }
        defer { server.stop() }

        try Self.waitReady(server.socketPath)
        let response = try Self.request(socketPath: server.socketPath, request: [
            "version": 1, "action": "destroy.everything",
        ])
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "unknown action")
    }

    func testAPIInventoryCollectAction() throws {
        let db = try tempDB()
        let server = try LocalAPIServer(socketPath: tempSocketPath(), database: db)
        try server.bind()
        Thread.detachNewThread { try? server.runAcceptLoop() }
        defer { server.stop() }

        try Self.waitReady(server.socketPath)
        let response = try Self.request(socketPath: server.socketPath, request: [
            "version": 1, "action": "inventory.collect",
        ])
        XCTAssertEqual(response["ok"] as? Bool, true)
        let taskID = try XCTUnwrap(response["taskID"] as? String)
        XCTAssertTrue(taskID.contains("-"), "durable task submitted with an ID")
    }

    // MARK: Helpers

    private func tempDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-api-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("t.db").path)
        _ = try SQLiteMigrator(db: db).run()
        return db
    }

    /// Wait until the server's socket file appears (accept loop readiness).
    static func waitReady(_ path: String, timeout: TimeInterval = 5) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw PersistenceError.connectionFailed("api socket never appeared: \(path)")
    }

    /// Newline-delimited JSON request/response over a POSIX UDS client.
    static func request(socketPath: String, request: [String: Any]) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PersistenceError.connectionFailed("client socket") }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8.prefix(102))
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (index, byte) in pathBytes.enumerated() {
                raw[index] = byte
            }
        }
        let connectResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { throw PersistenceError.connectionFailed("connect \(socketPath)") }

        var payload = try JSONSerialization.data(withJSONObject: request)
        payload.append(0x0A)
        try payload.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = send(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent, 0)
                guard n > 0 else { throw PersistenceError.connectionFailed("send") }
                sent += n
            }
        }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !received.contains(0x0A) {
            let n = recv(fd, &buffer, buffer.count, 0)
            guard n > 0 else { break }
            received.append(contentsOf: buffer[0..<n])
        }
        guard let line = received.split(separator: 0x0A).first,
              let data = Data(line).count > 0 ? Data(line) : nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PersistenceError.queryFailed("no valid JSON response")
        }
        return object
    }
}
