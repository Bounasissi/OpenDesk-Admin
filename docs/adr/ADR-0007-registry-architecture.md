# ADR-0007 — Registry Architecture: Single-Admin SQLite Default; Shared-File Multi-Admin Rejected as Production Architecture

**Status:** ACCEPTED
**Date:** 2026-09-13
**Deciders:** OpenDesk program (agent ruling under `AGENTS.md` §2)
**Plan(s) affected:** 04 (A1.4), 05, 08

## Context

The implementation conversation proposed pointing multiple administrators at one shared SQLite file (e.g., on a synced/shared folder). Plan 04 Amendment A1.4 requires this be treated as an **experiment, not production architecture**, and validated for: locking semantics, concurrent writers, network-filesystem behavior, sync-provider conflicts, corruption recovery, schema migrations, backup, conflict resolution.

## Experiment Findings (executable validation performed 2026-09-13)

| Validation item | Local-disk SQLite result | Shared-folder multi-admin result |
|---|---|---|
| Locking semantics | WAL + `BEGIN IMMEDIATE` + `busy_timeout` verified by concurrent-transaction tests (migration runner, task transitions) | **Unvalidated in production conditions** — network filesystems (SMB/AFP/NFS) and sync providers (Dropbox/iCloud/Drive) break POSIX advisory locking or lose WAL consistency; documented SQLite limitation |
| Concurrent writers | serialized per-process by design | multi-PROCESS writers on a shared file are outside SQLite's supported deployment profile |
| Corruption recovery | single-writer risk surface; WAL checkpointing local | sync-provider partial-state merge can corrupt mid-write databases |
| Schema migrations | forward-only runner, version-gated, tested | two admins on different app versions → version races |
| Backup | file copy is consistent under WAL | copies race with remote writes |

## Decision

1. **v1 default:** single-admin, **local SQLite** (canonical database at `~/Library/Application Support/OpenDeskAdmin/opendesk.db`) via the Plan 03 migration runner. The legacy JSON roster remains an import path, not the store of record.
2. **Shared-file multi-admin is rejected as production architecture.** It stays documented as an experiment; its code path is the existing `RegistryBackend` seam (kept for lab use, not default).
3. **Future multi-admin path (post-v1):** local SQLite per admin + an authenticated coordination/API service that owns cross-admin merge and conflict resolution (Plan 12 local API evolves here first; network API is POST_V1 per `POST_V1_ROADMAP.md`).

## Ruling Block

```text
RULING:
Decision: single-admin local SQLite is the v1 store; shared-file multi-admin is not production architecture.
Evidence: DATA_MODEL.md §8 migration rules; concurrent-write tests on canonical; SQLite deployment documentation (locking profile); Plan 04 A1.4 experiment requirement.
Reason: avoids entire classes of silent data corruption (network FS locking, sync-provider merge) that cannot be validated without a multi-admin environment; single-writer WAL is the profile SQLite is built for.
Alternative rejected: shared SQLite file as default multi-admin path (corruption risk unbounded); immediate coordination-service build (v1 scope discipline, Charter §6).
Cost if wrong: a coordination service must be built before multi-admin — acceptable and planned as post-v1.
Reversible: yes (repository seam + migration runner make the coordination service additive).
```

## Consequences

- Plan 05 builds the security foundation on the local-SQLite + Keychain model.
- Multi-admin UX is not claimed in v1; roster imports remain per-admin.
- The `RegistryBackend` protocol stays (test seam), with a comment that shared-file backends are experimental.

## Reconsideration Triggers

- A validated coordination service design lands (post-v1 roadmap item "REST/network API where justified").
- Field evidence shows a concrete single-admin-blocking scenario.
