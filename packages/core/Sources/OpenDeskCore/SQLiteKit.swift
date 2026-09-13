// SQLiteKit — minimal SQLite persistence for OpenDesk Admin.
// Uses the system libsqlite3 (no external dependency). WAL mode, foreign keys on.

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif
import SQLite3
import Foundation

/// SQLITE_TRANSIENT is not exposed by the SQLite3 module on all SDKs.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteError: Error, Sendable, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
}

public final class SQLiteDatabase: @unchecked Sendable {
    private let handle: OpaquePointer?
    private let queue = DispatchQueue(label: "opendesk.sqlite")

    public init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw SQLiteError.openFailed(msg)
        }
        handle = db
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA foreign_keys = ON;")
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    /// Execute a statement with no results (DDL, PRAGMA, INSERT/UPDATE/DELETE).
    public func exec(_ sql: String) throws {
        try queue.sync {
            var errMsg: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &errMsg) == SQLITE_OK else {
                let msg = errMsg.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(errMsg)
                throw SQLiteError.stepFailed(msg)
            }
        }
    }

    /// Run a query with bound parameters, mapping each row via the closure.
    public func query<T>(_ sql: String, bindings: [SQLiteValue] = [], row: (SQLiteRow) throws -> T) throws -> [T] {
        try queue.sync {
            let stmt = try prepare(sql, bindings: bindings)
            defer { sqlite3_finalize(stmt) }
            var results: [T] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW {
                    results.append(try row(SQLiteRow(stmt: stmt)))
                } else if rc == SQLITE_DONE {
                    break
                } else {
                    throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(handle)))
                }
            }
            return results
        }
    }

    /// Run an INSERT/UPDATE/DELETE with bindings.
    public func run(_ sql: String, bindings: [SQLiteValue] = []) throws {
        try queue.sync {
            let stmt = try prepare(sql, bindings: bindings)
            defer { sqlite3_finalize(stmt) }
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
                throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    public func lastInsertRowID() -> Int64 {
        queue.sync { sqlite3_last_insert_rowid(handle) }
    }

    private func prepare(_ sql: String, bindings: [SQLiteValue]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(handle)))
        }
        for (idx, value) in bindings.enumerated() {
            let i = Int32(idx + 1)
            let rc: Int32
            switch value {
            case .null: rc = sqlite3_bind_null(stmt, i)
            case .int(let v): rc = sqlite3_bind_int64(stmt, i, v)
            case .real(let v): rc = sqlite3_bind_double(stmt, i, v)
            case .text(let v): rc = sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                rc = v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, i, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                }
            }
            guard rc == SQLITE_OK else {
                sqlite3_finalize(stmt)
                throw SQLiteError.bindFailed("bind index \(i)")
            }
        }
        return stmt!
    }
}

// MARK: - Values

public enum SQLiteValue: Sendable {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])
}

public struct SQLiteRow {
    private let stmt: OpaquePointer

    fileprivate init(stmt: OpaquePointer) { self.stmt = stmt }

    public func columnCount() -> Int32 { sqlite3_column_count(stmt) }

    public func columnName(_ i: Int32) -> String {
        String(cString: sqlite3_column_name(stmt, i))
    }

    public func isNull(_ i: Int32) -> Bool {
        sqlite3_column_type(stmt, i) == SQLITE_NULL
    }

    public func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }

    public func real(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }

    public func text(_ i: Int32) -> String? {
        guard !isNull(i) else { return nil }
        return String(cString: sqlite3_column_text(stmt, i))
    }

    public func bool(_ i: Int32) -> Bool { int(i) != 0 }
}
