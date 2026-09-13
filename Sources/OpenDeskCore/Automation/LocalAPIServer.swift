import Foundation
import Darwin

/// Versioned local API server (Plan 12 §3): newline-delimited JSON over a
/// Unix-domain socket. **No unauthenticated TCP control service** — the
/// socket path is filesystem-permission scoped.
public final class LocalAPIServer: @unchecked Sendable {
    public private(set) var socketPath: String
    let database: SQLiteDatabase
    private var listenFD: Int32 = -1
    private var running = false
    private let lock = NSLock()
    public let version = 1

    public init(socketPath: String, database: SQLiteDatabase) throws {
        self.socketPath = socketPath
        self.database = database
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: (socketPath as NSString).deletingLastPathComponent),
            withIntermediateDirectories: true
        )
    }

    /// Bind + listen; `run()` blocks accepting one connection at a time.
    public func bind() throws {
        // sun_path holds 104 bytes on macOS; refuse silent truncation.
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < 104 else {
            throw ConfigurationError.invalidValue(key: "socketPath", reason: "exceeds sun_path capacity (104 bytes)")
        }
        unlink(socketPath)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw PersistenceError.connectionFailed("api socket") }
        let socketFD = listenFD
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (index, byte) in pathBytes.enumerated() {
                raw[index] = byte
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw PersistenceError.connectionFailed("bind \(socketPath)") }
        guard Darwin.listen(socketFD, 4) == 0 else { throw PersistenceError.connectionFailed("listen \(socketPath)") }
        // Scope to the invoking user (Plan 12 §3: socket permissions).
        chmod(socketPath, 0o600)
    }

    /// Convenience: bind + accept loop (blocking).
    public func run() throws {
        try bind()
        try runAcceptLoop()
    }

    /// Blocking accept loop over an already-bound socket.
    public func runAcceptLoop() throws {
        lock.lock(); running = true; lock.unlock()
        while true {
            lock.lock()
            let active = running
            let fd = listenFD
            lock.unlock()
            guard active, fd >= 0 else { break }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { break }
            handle(clientFD: client)
            close(client)
        }
    }

    public func stop() {
        lock.lock(); running = false; lock.unlock()
        if listenFD >= 0 {
            shutdown(listenFD, SHUT_RDWR)
            close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    // MARK: Request handling (newline-delimited JSON)

    func handle(clientFD: Int32) {
        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Read the request line.
        readLoop: while !request.contains(0x0A) {
            let n = recv(clientFD, &buffer, buffer.count, 0)
            if n <= 0 { return }
            request.append(contentsOf: buffer[0..<n])
            if request.count > 1_048_576 { return } // bounded input
        }
        guard let lineData = request.split(separator: 0x0A, omittingEmptySubsequences: true).first,
              let object = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any] else {
            respond(clientFD: clientFD, payload: ["version": version, "ok": false, "error": "malformed request"])
            return
        }
        respond(clientFD: clientFD, payload: dispatch(object))
    }

    func dispatch(_ request: [String: Any]) -> [String: Any] {
        let requestVersion = request["version"] as? Int ?? 0
        guard requestVersion == version else {
            return ["version": version, "ok": false, "error": "unsupported version"]
        }
        let action = request["action"] as? String ?? ""
        do {
            switch action {
            case "devices.list":
                let repo = SQLiteDeviceRepository(db: database)
                let devices = try repo.all()
                let payload: [[String: String]] = devices.map {
                    ["id": $0.id.rawValue, "hostname": $0.hostname, "lifecycle": $0.lifecycle.rawValue]
                }
                return ["version": version, "ok": true, "devices": payload]
            case "inventory.collect":
                let runner = DurableTaskRunner(db: database, transport: NoopTransport())
                let task = try runner.submit(type: "inventory.collect", deviceIDs: [])
                return ["version": version, "ok": true, "taskID": task.id.rawValue]
            case "tasks.submit":
                let runner = DurableTaskRunner(db: database, transport: NoopTransport())
                let task = try runner.submit(
                    type: request["type"] as? String ?? "exec.command",
                    deviceIDs: [],
                    idempotencyKey: request["idempotencyKey"] as? String,
                    parameters: request["parameters"] as? String
                )
                return ["version": version, "ok": true, "taskID": task.id.rawValue]
            case "version":
                return ["version": version, "ok": true, "service": "opendesk"]
            default:
                return ["version": version, "ok": false, "error": "unknown action"]
            }
        } catch {
            return ["version": version, "ok": false, "error": "action failed"]
        }
    }

    private func respond(clientFD: Int32, payload: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        data.append(0x0A)
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { raw in
                send(clientFD, raw.baseAddress!.advanced(by: sent), data.count - sent, 0)
            }
            guard n > 0 else { return }
            sent += n
        }
    }
}

/// Transport used when actions are dispatched locally without a remote target.
public struct NoopTransport: RemoteTransport {
    public init() {}
    public func execute(device: Device, command: String) -> ExecOutcome {
        ExecOutcome(exitCode: 0, stdout: "", stderr: "")
    }
}
