# DATA_MODEL — OpenDesk

**Authority:** `docs/architecture/SYSTEM_ARCHITECTURE.md`. Schema source of truth for Plans 03–11.

---

## 1. Storage Strategy

- **SQLite** is the only database. Versioned migrations from `001`; the migration runner is part of OpenDeskPersistence (Plan 03).
- **macOS Keychain** holds all secret material. SQLite stores only credential references.
- Inventory is **snapshot-based**: history is never destructively overwritten.

---

## 2. Core Tables (from Plan 03)

```text
devices                 — identity, lifecycle state, stable identity signals
device_endpoints        — per-endpoint addresses/ports/transport hints
device_capabilities     — observed capabilities (RFB/SSH/ARD/agent) + probe evidence
credentials             — CredentialID references; NO secret material
groups                  — static groups
group_memberships       — device↔group mapping
smart_groups            — predicate definitions for dynamic membership
tasks                   — task records (state machine per TASK_MODEL.md)
task_targets            — resolved/snapshot targets per task
task_events             — state transitions + per-target results
task_templates          — reusable task definitions
schedules               — run-now/once/RRULE/online/predicate schedules
sessions                — remote session records
inventory_snapshots     — snapshot payloads + metadata
audit_events            — actor/action/targets/timestamp/redacted-parameters/result/correlationID
agent_status            — agent version, capabilities, health, last seen
```

---

## 3. Identifiers (stable, from Plan 03)

```text
DeviceID
GroupID
TaskID
SessionID
CredentialID
InventorySnapshotID
```

Rules:

- `DeviceID` is stable across IP/interface/hostname changes; reconciliation merges endpoints into one device (Plan 04).
- All identifiers are opaque and persisted verbatim.

---

## 4. Secret Handling (binding)

Stored in SQLite (allowed): `CredentialID`, `credential type`, `owner references`, `host-key policy metadata`.

Stored only in Keychain (never in SQLite, never logged):

```text
password
private key material
agent enrollment secret
VNC credential
```

Host-key trust state (TOFU record, fingerprint) is metadata, stored in SQLite with an audit event for first-enrollment.

---

## 5. Task Records

Fields per task row (see `TASK_MODEL.md`): `TaskID, type, target selector, resolved targets, parameters, execution policy, schedule, created at, deadline, state, results, retry policy, idempotency key, correlation ID`. Terminal states are immutable; transitions append `task_events`.

---

## 6. Inventory Snapshots

Each snapshot: `InventorySnapshotID`, `DeviceID`, `collected at`, `source (RFB host/SSH/agent)`, `typed payload per collector`, `schema version`. Comparisons (device-vs-previous, device-vs-device, group aggregate) are derived queries; drift events reference snapshot pairs.

---

## 7. Audit Events

Every administrative action records:

```text
actor
action
targets
timestamp
parameters with secrets removed
result
correlation ID
```

Audit writes are non-optional in the services layer; the redaction filter (Plan 05) is applied before persistence.

---

## 8. Migration Rules

- Forward-only migrations; each step tested (empty→latest; every intermediate version).
- Schema changes require a new numbered migration — never edit a released migration.
- Migration failures surface as `PersistenceError` with a recovery path (backup-then-retry policy documented in Plan 17 failure injection).
