PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- ============================================================
-- OpenDesk Admin — SQLite schema v1
-- Secrets are NEVER stored here. credentials.credential_reference
-- is a UUID resolved via macOS Keychain.
-- ============================================================

CREATE TABLE IF NOT EXISTS devices (
    id              TEXT PRIMARY KEY,            -- uuid
    hostname        TEXT NOT NULL,
    bonjour_name    TEXT,
    ips             TEXT,                        -- JSON array
    mac_address     TEXT,
    os_version      TEXT,
    architecture    TEXT,                        -- arm64 | x86_64
    ard_version     TEXT,
    rfb_available   INTEGER NOT NULL DEFAULT 0,
    ssh_available   INTEGER NOT NULL DEFAULT 0,
    auth_state      TEXT,                        -- none | pending | ok | failed
    latency_ms      REAL,
    online          INTEGER NOT NULL DEFAULT 0,
    last_seen       TEXT,
    notes           TEXT,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS credentials (
    id                  TEXT PRIMARY KEY,        -- uuid
    device_id           TEXT REFERENCES devices(id) ON DELETE CASCADE,
    kind                TEXT NOT NULL CHECK (kind IN ('password','ssh_key','certificate','agent_token','vnc')),
    username            TEXT,
    credential_reference TEXT NOT NULL,          -- Keychain UUID; secret never here
    created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS groups (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    parent_id   TEXT REFERENCES groups(id) ON DELETE SET NULL,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS group_memberships (
    group_id    TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, device_id)
);

CREATE TABLE IF NOT EXISTS smart_groups (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    predicate_json  TEXT NOT NULL,               -- JSON predicate tree
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS sessions (
    id          TEXT PRIMARY KEY,
    device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    mode        TEXT NOT NULL CHECK (mode IN ('observe','control')),
    started_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    ended_at    TEXT
);

CREATE TABLE IF NOT EXISTS task_templates (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    type            TEXT NOT NULL,
    parameters_json TEXT NOT NULL DEFAULT '{}',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS schedules (
    id              TEXT PRIMARY KEY,
    rrule           TEXT,                        -- RFC 5545 recurrence, nullable
    run_at          TEXT,                        -- one-shot, nullable
    on_reconnect    INTEGER NOT NULL DEFAULT 0,
    predicate_json  TEXT,                        -- run-when-predicate-true
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS tasks (
    id              TEXT PRIMARY KEY,            -- uuid
    type            TEXT NOT NULL,               -- execute_command | install_package | ...
    parameters_json TEXT NOT NULL DEFAULT '{}',
    execution_json  TEXT NOT NULL DEFAULT '{}',  -- {"mode":"immediate"} etc.
    schedule_id     TEXT REFERENCES schedules(id) ON DELETE SET NULL,
    template_id     TEXT REFERENCES task_templates(id) ON DELETE SET NULL,
    idempotency_key TEXT UNIQUE,
    deadline        TEXT,
    status          TEXT NOT NULL DEFAULT 'created'
                    CHECK (status IN ('created','queued','available','offline_wait','dispatched','running','success','failed','cancelled')),
    retry_policy_json TEXT NOT NULL DEFAULT '{}',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    started_at      TEXT,
    completed_at    TEXT
);

CREATE TABLE IF NOT EXISTS task_targets (
    task_id     TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','dispatched','running','success','failed','skipped')),
    result_json TEXT,
    error       TEXT,
    PRIMARY KEY (task_id, device_id)
);

CREATE TABLE IF NOT EXISTS task_events (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id      TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    device_id    TEXT REFERENCES devices(id) ON DELETE SET NULL,
    event        TEXT NOT NULL,                  -- queued | dispatched | started | output | success | failed | cancelled | retry
    payload_json TEXT,
    at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS inventory_snapshots (
    id           TEXT PRIMARY KEY,
    device_id    TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    collected_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS hardware_inventory (
    snapshot_id   TEXT PRIMARY KEY REFERENCES inventory_snapshots(id) ON DELETE CASCADE,
    architecture  TEXT,
    model         TEXT,
    memory_bytes  INTEGER,
    cpu           TEXT,
    displays_json TEXT
);

CREATE TABLE IF NOT EXISTS software_inventory (
    snapshot_id TEXT NOT NULL REFERENCES inventory_snapshots(id) ON DELETE CASCADE,
    bundle_id   TEXT,
    name        TEXT,
    version     TEXT,
    path        TEXT,
    PRIMARY KEY (snapshot_id, bundle_id, path)
);

CREATE TABLE IF NOT EXISTS network_inventory (
    snapshot_id TEXT NOT NULL REFERENCES inventory_snapshots(id) ON DELETE CASCADE,
    interface   TEXT,
    addresses   TEXT,                            -- JSON array
    gateway     TEXT,
    PRIMARY KEY (snapshot_id, interface)
);

CREATE TABLE IF NOT EXISTS users (
    id      TEXT PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    role    TEXT NOT NULL DEFAULT 'operator' CHECK (role IN ('admin','operator','observer'))
);

CREATE TABLE IF NOT EXISTS login_events (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    username  TEXT,
    kind      TEXT NOT NULL CHECK (kind IN ('login','logout')),
    at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS application_usage (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    bundle_id TEXT,
    used_at   TEXT NOT NULL,
    duration_s INTEGER
);

CREATE TABLE IF NOT EXISTS file_inventory (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    path        TEXT NOT NULL,
    size_bytes  INTEGER,
    modified_at TEXT,
    found_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS audit_events (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id      TEXT REFERENCES users(id) ON DELETE SET NULL,
    action       TEXT NOT NULL,
    target       TEXT,                           -- device id / group id / task id
    payload_json TEXT,
    at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS agent_status (
    device_id       TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
    version         TEXT,
    last_heartbeat  TEXT,
    capabilities_json TEXT
);

-- ============================================================
-- Indexes
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_devices_online        ON devices(online);
CREATE INDEX IF NOT EXISTS idx_tasks_status          ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_task_targets_device   ON task_targets(device_id);
CREATE INDEX IF NOT EXISTS idx_task_events_task      ON task_events(task_id);
CREATE INDEX IF NOT EXISTS idx_snapshots_device      ON inventory_snapshots(device_id);
CREATE INDEX IF NOT EXISTS idx_software_bundle       ON software_inventory(bundle_id);
CREATE INDEX IF NOT EXISTS idx_audit_at              ON audit_events(at);
