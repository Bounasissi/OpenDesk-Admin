import Foundation
import SQLite3

/// Durable roster backend protocol so the registry storage can be swapped
/// (single-admin JSON file, shared SQLite file, future Supabase).
public protocol RegistryBackend {
    func loadAll() -> [Host]
    func save(_ hosts: [Host])
}

/// JSON-file backend (default, single admin).
public final class JSONFileBackend: RegistryBackend, @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "opendesk.registry.json")

    public init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
    }

    public func loadAll() -> [Host] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try? decoder.decode([Host].self, from: data)) ?? []
        }
    }

    public func save(_ hosts: [Host]) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(hosts) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}

/// SQLite backend: a shared hosts.db file on a network volume or synced
/// folder gives multiple admin Macs one roster (file-lock semantics apply
/// per SQLite; keep the file on a volume all admins can reach).
public final class SQLiteBackend: RegistryBackend, @unchecked Sendable {
    private var database: OpaquePointer?
    private let path: String
    private let queue = DispatchQueue(label: "opendesk.registry.sqlite")

    public enum SQLiteError: Error, Equatable {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
    }

    public init(path: String) throws {
        self.path = path
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: (path as NSString).deletingLastPathComponent),
            withIntermediateDirectories: true
        )
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteError.openFailed(message)
        }
        try createSchema()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS hosts (
            id TEXT PRIMARY KEY,
            hostname TEXT NOT NULL,
            port INTEGER NOT NULL DEFAULT 22,
            username TEXT NOT NULL,
            auth_method TEXT NOT NULL DEFAULT 'key',
            groups TEXT NOT NULL DEFAULT '',
            screen_port INTEGER NOT NULL DEFAULT 5900,
            mac_address TEXT,
            last_seen TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_hosts_hostname ON hosts(hostname);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.stepFailed(lastError())
        }
    }

    private func lastError() -> String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "closed"
    }

    public func loadAll() -> [Host] {
        queue.sync { selectAll() }
    }

    public func save(_ hosts: [Host]) {
        queue.sync {
            deleteAll()
            for host in hosts { insert(host) }
        }
    }

    // MARK: - Row mapping

    private func bindHost(_ host: Host, into statement: OpaquePointer?) {
        let id = host.id.uuidString as NSString
        let hostname = host.hostname as NSString
        let username = host.username as NSString
        let auth = host.authMethod.rawValue as NSString
        let groups = host.groups.joined(separator: ",") as NSString
        let mac = (host.macAddress ?? "") as NSString
        let lastSeenString = host.lastSeen.map { ISO8601DateFormatter().string(from: $0) } ?? ""

        sqlite3_bind_text(statement, 1, id.utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, hostname.utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 3, Int32(host.port))
        sqlite3_bind_text(statement, 4, username.utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, auth.utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, groups.utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 7, Int32(host.screenPort))
        sqlite3_bind_text(statement, 8, mac.utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 9, lastSeenString, -1, SQLITE_TRANSIENT)
    }

    private func insert(_ host: Host) {
        let sql = "INSERT OR REPLACE INTO hosts (id, hostname, port, username, auth_method, groups, screen_port, mac_address, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindHost(host, into: statement)
        _ = sqlite3_step(statement)
    }

    private func deleteAll() {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM hosts;", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        _ = sqlite3_step(statement)
    }

    private func selectAll() -> [Host] {
        var hosts: [Host] = []
        let sql = "SELECT id, hostname, port, username, auth_method, groups, screen_port, mac_address, last_seen FROM hosts ORDER BY hostname;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let idString = String(cString: sqlite3_column_text(statement, 0))
            let hostname = String(cString: sqlite3_column_text(statement, 1))
            let port = Int(sqlite3_column_int(statement, 2))
            let username = String(cString: sqlite3_column_text(statement, 3))
            let authRaw = String(cString: sqlite3_column_text(statement, 4))
            let groups = String(cString: sqlite3_column_text(statement, 5))
            let screenPort = Int(sqlite3_column_int(statement, 6))
            let macColumn = sqlite3_column_text(statement, 7)
            let mac = macColumn.map { String(cString: $0) }
            let lastSeenColumn = sqlite3_column_text(statement, 8)
            let lastSeenString = lastSeenColumn.map { String(cString: $0) } ?? ""

            var lastSeen: Date?
            if !lastSeenString.isEmpty {
                lastSeen = ISO8601DateFormatter().date(from: lastSeenString)
            }
            let host = Host(
                id: UUID(uuidString: idString) ?? UUID(),
                hostname: hostname,
                port: port,
                username: username,
                authMethod: Host.AuthMethod(rawValue: authRaw) ?? .key,
                groups: groups.split(separator: ",").map(String.init).filter { !$0.isEmpty },
                screenPort: screenPort,
                macAddress: (mac?.isEmpty == false) ? mac : nil,
                lastSeen: lastSeen
            )
            hosts.append(host)
        }
        return hosts
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
