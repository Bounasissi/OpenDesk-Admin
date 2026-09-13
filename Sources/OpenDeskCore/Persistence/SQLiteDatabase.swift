import Foundation
import SQLite3

/// First-class SQLite connection for the OpenDesk persistence layer (Plan 03).
/// Serialized access through an internal queue; WAL + foreign keys enabled.
public final class SQLiteDatabase: @unchecked Sendable {
    private let handle: OpaquePointer?
    private let queue = DispatchQueue(label: "opendesk.persistence.sqlite")

    public init(path: String) throws {
        let dir = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw PersistenceError.connectionFailed(message)
        }
        self.handle = db
        // Plan 16 §3: the roster/task database is user-private (0600).
        chmod(path, 0o600)
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA busy_timeout = 5000;")
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    // MARK: - Public API

    /// Execute a statement (no result rows consumed).
    public func execute(_ sql: String) throws {
        try queue.sync { try executeNow(sql) }
    }

    /// Execute a statement with bindings. `nil` binds SQL NULL.
    public func execute(_ sql: String, bindings: [String?]) throws {
        try queue.sync { try executeNow(sql, bindings: bindings) }
    }

    /// Run a query returning typed rows.
    public func query(_ sql: String) throws -> [Row] {
        try queue.sync { try queryNow(sql) }
    }

    /// Run a query with bindings. `nil` binds SQL NULL.
    public func query(_ sql: String, bindings: [String?]) throws -> [Row] {
        try queue.sync { try queryNow(sql, bindings: bindings) }
    }

    /// Homogeneous string-binding conveniences.
    public func execute(_ sql: String, bindings: [String]) throws {
        try queue.sync { try executeNow(sql, bindings: bindings.map(Optional.init)) }
    }

    public func query(_ sql: String, bindings: [String]) throws -> [Row] {
        try queue.sync { try queryNow(sql, bindings: bindings.map(Optional.init)) }
    }

    /// Convenience: first column of each row as string.
    public func stringColumn(_ sql: String) throws -> [String] {
        try queue.sync {
            try queryNow(sql).compactMap { row in row.values.values.first ?? nil }
        }
    }

    public func stringColumn(_ sql: String, bindings: [String]) throws -> [String] {
        try queue.sync {
            try queryNow(sql, bindings: bindings.map(Optional.init)).compactMap { row in row.values.values.first ?? nil }
        }
    }

    public func stringColumn(_ sql: String, bindings: [String?]) throws -> [String] {
        try queue.sync {
            try queryNow(sql, bindings: bindings).compactMap { row in row.values.values.first ?? nil }
        }
    }

    /// Convenience: scalar string lookup.
    public func scalar(_ sql: String) throws -> String? {
        try queue.sync {
            let rows = try queryNow(sql)
            guard let row = rows.first else { return nil }
            return row.values.values.first ?? nil
        }
    }

    public func scalar(_ sql: String, bindings: [String]) throws -> String? {
        try queue.sync {
            let rows = try queryNow(sql, bindings: bindings.map(Optional.init))
            guard let row = rows.first else { return nil }
            return row.values.values.first ?? nil
        }
    }

    public func scalar(_ sql: String, bindings: [String?]) throws -> String? {
        try queue.sync {
            let rows = try queryNow(sql, bindings: bindings)
            guard let row = rows.first else { return nil }
            return row.values.values.first ?? nil
        }
    }

    /// Run `body` inside an IMMEDIATE transaction; rolls back on throw.
    /// The body must use the un-dispatched `executeInTransaction`/`queryInTransaction` helpers.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try queue.sync {
            try executeNow("BEGIN IMMEDIATE")
            do {
                let result = try body()
                try executeNow("COMMIT")
                return result
            } catch {
                try? executeNow("ROLLBACK")
                throw error
            }
        }
    }

    // MARK: - On-queue helpers (call only inside transaction bodies)

    public func executeInTransaction(_ sql: String, bindings: [String?] = []) throws {
        try executeNow(sql, bindings: bindings)
    }

    public func queryInTransaction(_ sql: String, bindings: [String?] = []) throws -> [Row] {
        try queryNow(sql, bindings: bindings)
    }

    // MARK: - Internals (call on queue)

    private func executeNow(_ sql: String, bindings: [String?]? = nil) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.queryFailed(lastError())
        }
        defer { sqlite3_finalize(statement) }
        if let bindings {
            for (index, value) in bindings.enumerated() {
                if let value {
                    _ = value.withCString { cString in
                        sqlite3_bind_text(statement, Int32(index + 1), cString, -1, SQLITE_TRANSIENT_OP)
                    }
                } else {
                    sqlite3_bind_null(statement, Int32(index + 1))
                }
            }
        }
        let step = sqlite3_step(statement)
        guard step == SQLITE_DONE || step == SQLITE_ROW else {
            throw PersistenceError.queryFailed(lastError())
        }
    }

    private func queryNow(_ sql: String, bindings: [String?]? = nil) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.queryFailed(lastError())
        }
        defer { sqlite3_finalize(statement) }
        if let bindings {
            for (index, value) in bindings.enumerated() {
                if let value {
                    _ = value.withCString { cString in
                        sqlite3_bind_text(statement, Int32(index + 1), cString, -1, SQLITE_TRANSIENT_OP)
                    }
                } else {
                    sqlite3_bind_null(statement, Int32(index + 1))
                }
            }
        }
        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var values: [String: String?] = [:]
            let count = sqlite3_column_count(statement)
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, i))
                values[name] = sqlite3_column_type(statement, i) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, i))
            }
            rows.append(Row(values: values))
        }
        return rows
    }

    private func lastError() -> String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed"
    }
}

/// Typed access to a query result row.
public struct Row {
    let values: [String: String?]

    public func opt(_ key: String) -> String? { values[key] ?? nil }
    public func str(_ key: String) -> String { opt(key) ?? "" }
    public func int(_ key: String) -> Int? { opt(key).flatMap(Int.init) }
    public func date(_ key: String) -> Date? { opt(key).map(isoDate) }
}

/// SQLITE_TRANSIENT is not exposed by the SQLite3 module on all SDKs.
let SQLITE_TRANSIENT_OP = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
