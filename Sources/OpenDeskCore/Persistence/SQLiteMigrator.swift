import Foundation

/// A single forward-only migration step.
public struct MigrationStep {
    public let version: Int
    public let sql: String
    public init(version: Int, sql: String) {
        self.version = version
        self.sql = sql
    }
}

/// Forward-only SQLite migration runner (Plan 03 §4, DATA_MODEL §8).
/// Version table: schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT).
public struct SQLiteMigrator {
    let db: SQLiteDatabase
    let steps: [MigrationStep]

    public init(db: SQLiteDatabase, steps: [MigrationStep] = MigrationCatalog.all) {
        self.db = db
        self.steps = steps
    }

    /// Apply all pending migrations in order; returns versions applied.
    public func run() throws -> [Int] {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
        );
        """)
        let current = try currentVersion()
        var applied: [Int] = []
        for step in steps where step.version > current {
            do {
                try db.transaction {
                    // sqlite3_prepare_v2 compiles only the first statement of a
                    // batch; run the step's statements individually.
                    for statement in step.sql.split(separator: ";") {
                        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            try db.executeInTransaction(trimmed)
                        }
                    }
                    try db.executeInTransaction("INSERT INTO schema_migrations (version) VALUES (?)", bindings: [String(step.version)])
                }
                applied.append(step.version)
            } catch {
                throw PersistenceError.migrationFailed(step: step.version, reason: String(describing: error))
            }
        }
        let highestKnown = steps.map(\.version).max() ?? 0
        if current > highestKnown {
            throw PersistenceError.schemaVersionMismatch
        }
        return applied
    }

    public func currentVersion() throws -> Int {
        let tables = try db.stringColumn("SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations'")
        guard !tables.isEmpty else { return 0 }
        let version = try db.scalar("SELECT MAX(version) FROM schema_migrations")
        return Int(version ?? "0") ?? 0
    }
}

/// Migration catalog. Schema changes require a NEW numbered migration —
/// never edit an applied one (DATA_MODEL §8).
public enum MigrationCatalog {
    public static let all: [MigrationStep] = [migration001, migration002]

    /// 001 — initial core schema (Plan 03 §4; DATA_MODEL §2; secret-free by rule).
    static let migration001 = MigrationStep(version: 1, sql: """
    CREATE TABLE devices (
        id              TEXT PRIMARY KEY,
        hostname        TEXT NOT NULL,
        lifecycle       TEXT NOT NULL DEFAULT 'unknown',
        stable_signals  TEXT,
        notes           TEXT,
        created_at      TEXT NOT NULL,
        updated_at      TEXT NOT NULL
    );

    CREATE TABLE device_endpoints (
        device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        host        TEXT NOT NULL,
        port        INTEGER NOT NULL,
        transport   TEXT NOT NULL,
        last_seen   TEXT,
        PRIMARY KEY (device_id, host, port, transport)
    );

    CREATE TABLE device_capabilities (
        device_id     TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        capability    TEXT NOT NULL,
        available     INTEGER NOT NULL DEFAULT 0,
        evidence      TEXT,
        observed_at   TEXT,
        PRIMARY KEY (device_id, capability)
    );

    CREATE TABLE credentials (
        id              TEXT PRIMARY KEY,
        device_id       TEXT REFERENCES devices(id) ON DELETE CASCADE,
        kind            TEXT NOT NULL CHECK (kind IN ('password','ssh_key','certificate','agent_token','vnc')),
        username        TEXT,
        credential_reference TEXT NOT NULL,
        created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );

    CREATE TABLE groups (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL UNIQUE,
        parent_id   TEXT REFERENCES groups(id) ON DELETE SET NULL,
        created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );

    CREATE TABLE group_memberships (
        group_id    TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
        device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        PRIMARY KEY (group_id, device_id)
    );

    CREATE TABLE smart_groups (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL UNIQUE,
        predicate   TEXT NOT NULL,
        created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );

    CREATE TABLE tasks (
        id                  TEXT PRIMARY KEY,
        type                TEXT NOT NULL,
        state               TEXT NOT NULL,
        target_selector     TEXT,
        parameters          TEXT,
        idempotency_key     TEXT UNIQUE,
        correlation_id      TEXT,
        deadline            TEXT,
        retry_policy        TEXT,
        created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );

    CREATE TABLE task_targets (
        task_id     TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        device_id   TEXT NOT NULL,
        state       TEXT NOT NULL DEFAULT 'pending',
        result      TEXT,
        finished_at TEXT,
        PRIMARY KEY (task_id, device_id)
    );

    CREATE TABLE task_events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id     TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        from_state  TEXT NOT NULL,
        to_state    TEXT NOT NULL,
        detail      TEXT,
        recorded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );

    CREATE TABLE task_templates (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL UNIQUE,
        type        TEXT NOT NULL,
        parameters  TEXT NOT NULL,
        version     INTEGER NOT NULL DEFAULT 1,
        created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );

    CREATE TABLE schedules (
        id          TEXT PRIMARY KEY,
        task_id     TEXT REFERENCES tasks(id) ON DELETE CASCADE,
        task_template_id TEXT REFERENCES task_templates(id) ON DELETE SET NULL,
        kind        TEXT NOT NULL CHECK (kind IN ('now','once','rrule','on_reconnect','on_predicate')),
        rrule       TEXT,
        run_at      TEXT,
        predicate   TEXT,
        enabled     INTEGER NOT NULL DEFAULT 1,
        created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );

    CREATE TABLE sessions (
        id          TEXT PRIMARY KEY,
        device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        kind        TEXT NOT NULL,
        started_at  TEXT NOT NULL,
        ended_at    TEXT
    );

    CREATE TABLE inventory_snapshots (
        id           TEXT PRIMARY KEY,
        device_id    TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        collected_at TEXT NOT NULL,
        payload      TEXT NOT NULL,
        collector_errors TEXT
    );

    CREATE TABLE audit_events (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        actor           TEXT NOT NULL,
        action          TEXT NOT NULL,
        targets         TEXT NOT NULL,
        parameters      TEXT NOT NULL,
        result          TEXT NOT NULL,
        correlation_id  TEXT,
        recorded_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );

    CREATE TABLE agent_status (
        device_id       TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
        agent_version   TEXT,
        capabilities    TEXT,
        health          TEXT,
        last_seen       TEXT
    );

    CREATE INDEX idx_devices_hostname ON devices(hostname);
    CREATE INDEX idx_tasks_state ON tasks(state);
    CREATE INDEX idx_task_events_task ON task_events(task_id);
    CREATE INDEX idx_audit_events_action ON audit_events(action);
    """)

    /// 002 — host-key policy records (Plan 05 §4; host-key policy metadata is
    /// permitted in SQLite per DATA_MODEL §4; fingerprints, never private keys).
    static let migration002 = MigrationStep(version: 2, sql: """
    CREATE TABLE IF NOT EXISTS host_key_records (
        host          TEXT PRIMARY KEY,
        fingerprint   TEXT NOT NULL,
        recorded_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );
    """)
}
