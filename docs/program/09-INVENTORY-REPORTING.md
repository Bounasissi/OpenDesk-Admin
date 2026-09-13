# Plan 09 — Inventory and Reporting

> Binding instruction document. Read `/AGENTS.md` and `docs/architecture/DATA_MODEL.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 09
- **Prerequisites:** 03, 08
- **Blocks:** 10, 15, 17 (drift feeds reliability), 21 (RC suite)

---

## 1. Goal

Provide useful fleet intelligence comparable to the administrative value of ARD reports.

---

## 2. Collectors

Create independent collectors for:

```text
hardware
OS
storage
network
display
applications
processes
users
login history
file search
management status
OpenDesk Agent status
```

Each collector emits normalized typed data.

---

## 3. Snapshots

Inventory is snapshot-based. Never overwrite historical state as the only copy. Support comparisons:

```text
device vs previous snapshot
device vs device
group aggregate
```

---

## 4. Sources

Prefer public macOS APIs. Where command-line utilities are needed:

```text
system_profiler
softwareupdate
mdfind
launchctl
diskutil
networksetup
```

they must run through typed wrappers with parsing tests. Do not depend permanently on localized human-readable output if machine-readable alternatives exist.

---

## 5. Reports

Support:

```text
table
search
filter
sort
CSV
JSON
```

---

## 6. Drift Detection

Detect:

```text
new application
removed application
OS change
storage threshold
network change
agent missing
management capability changed
```

---

## 7. Agent Sequence

1. Implement typed wrapper framework for command-line data sources (parse tests per utility).
2. Implement each collector against the wrapper (collect → normalize → typed payload).
3. Implement snapshot persistence + diff engine (device-vs-previous, device-vs-device, group aggregate).
4. Implement collection tasks wired into Plan 08 engine (manual run + schedule).
5. Implement report engine (query → render/export CSV/JSON).
6. Implement drift rules engine with persisted drift events.

---

## 8. Tests Required

- Parser fixture tests per source (sample outputs committed as fixtures; include localized-output variants).
- Snapshot diff tests.
- Report export tests (CSV/JSON schema stability).
- Drift rule tests (each rule fires on synthetic snapshots).

---

## 9. Exit Gate

Inventory survives application restarts and meaningful fleet reports can be exported without network access.

---

## 10. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `10-MULTI-OBSERVE-SESSIONS`).

---

## Amendment A1 — Three-Conversation Addendum (2026-09-13, Addendum §16)

### A1.1 Inventory architecture beyond collection (extends §3/§6)

Required architecture additions:

```text
historical snapshots (already §3 — make retention policy explicit)
device-vs-previous diff (already §6 drift — keep)
device-vs-device comparison (NEW)
group aggregates (NEW: counts by OS, arch, app presence, agent state)
```

Drift detection keeps the §6 list and adds: storage-threshold alerting configured per group, agent disappearance as a first-class finding, management-status change surfaced in device state.

### A1.2 Collectors acceptance check (§2)

§2's collector list matches the addendum target (hardware, OS, storage, network, display, applications, processes, users, login history, file search, management status, agent status/health). Exports: CSV (RFC-4180 behavior already reported and tested) + JSON. Both are v1 requirements.
