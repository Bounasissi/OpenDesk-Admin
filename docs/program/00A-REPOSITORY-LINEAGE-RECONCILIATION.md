# Plan 00A — Repository Lineage Reconciliation

> Binding instruction document. Executes **before any existing Plan 01–23**.
> Source requirement: "Three-Conversation Requirements Extraction and Delivery Program Addendum" §0, §00A.
> Central rule: **conversation claims are historical evidence, not current repository truth.**

- **Plan ID:** 00A
- **Type:** One-time reconciliation (execution-ordered before Plans 01–23)
- **Prerequisites:** None
- **Blocks:** 00B, 01–23

---

## 1. Goal

Determine where the work from all three September 13 development conversations actually exists, and consolidate the strongest compatible implementation into **one canonical branch**.

## 2. Known Histories (from the conversations)

| History | Reported identity | Reported commits / tags | Confirmed location (2026-09-13 forensic pass) |
|---|---|---|---|
| Implementation-heavy | OpenDesk-Admin MVP → v0.3.0 | `e808761`, `f383d84`, `2a999f5`, `7f1c5c9`, `df7215d`, `b6d0e69`, `4b63ee2`, `068864e`, `a7fb815`, `b785220`; tag `v0.3.0` | branch `initial-091396` (all 10 commits + tag verified present) |
| Architecture/scaffold | OG output plan scaffold | branch `OG-Output-Plan-0913`, commits `83bc198`, `b36e9c6` | branch `OG-Output-Plan-0913` (2 reported + 7 subsequent commits verified present) |
| Program-documentation | AGENTS.md, PROGRAM_CHARTER.md, status ledger, Plans 00–23 | transcript did not prove landing branch | branch `post-initial-work-091326`, commit `038952d` (all governance docs verified present) |

## 3. Agent Instructions

Inspect (mandatory forensic pass):

```bash
git status
git remote -v
git branch -a
git tag
git log --all --graph --decorate --oneline
git reflog --all
git show --stat <hash>        # for every reported hash
git branch --all --contains <hash>
```

Produce `docs/status/REPOSITORY_LINEAGE.md` containing, for every history:

| History | Branch/commit | Exists | Unique value | Superseded | Merge action |
|---|---|---:|---|---:|---|

**Do not blindly merge whole parallel scaffolds.** Compare by subsystem:

```text
docs
domain models
RFB
SSH
persistence
task engine
inventory
GUI
CLI
tests
CI
release engineering
```

Select the strongest implementation per subsystem. Resolve conflicts intentionally. Every exclusion requires a recorded ruling (format: `AGENTS.md` §8).

## 4. Subsystem Comparison Rulings (executed 2026-09-13)

The forensic pass produced these rulings. Rationale per ruling is recorded in `docs/status/REPOSITORY_LINEAGE.md`.

| Subsystem | Stronger history | Ruling |
|---|---|---|
| RFB protocol depth (Raw/Hextile decoders, keysym, renderer, loopback TCP server tests) | implementation-heavy (`initial-091396`) | **Canonical** — verified by 92 passing tests incl. authenticated loopback RFB over real TCP |
| RFB breadth (Apple ARD security type 30 advertised) | scaffold (`OG-Output-Plan-0913`) | Reference only; not merged (GPL provenance). Becomes Plan 06A input |
| Discovery (Bonjour + CIDR + dedupe) | scaffold | Reference only; scaffold `Discovery.swift` excluded. CIDR + dedupe become **required tasks** in Plan 04 amendment |
| Persistence (21-table SQLite schema, WAL, FK, `credentials` w/ Keychain indirection, `task_events`, `audit_events`) | scaffold schema design | Schema **adopted as reference specification** for Plan 03; scaffold Swift code not merged (GPL provenance + API collision with canonical tree) |
| Task engine (idempotency keys, per-target results, event log) | scaffold concepts | Reference only; canonical TaskEngine + TaskStore retained. Durable-state requirements become Plan 08 amendment |
| Scheduler (RRULE subset, run-once-later, on-reconnect, on-predicate) | scaffold | Reference only; becomes **required behavior** in Plan 08 amendment |
| Smart Groups predicate engine | scaffold (unique) | Reference only; becomes **required feature** in Plan 04 amendment |
| Power management (restart/shutdown/sleep/logout/restart-target states) | scaffold (unique) | Reference only; becomes required behavior in Plan 07 amendment |
| Transfers (SHA-256 checksum verification pipeline) | scaffold | Reference only; checksum verification becomes required in Plan 07 amendment |
| GUI (SwiftUI dashboard, tiled observation, screen streamer) | implementation-heavy (unique) | **Canonical** |
| CLI | both | implementation-heavy `main.swift` canonical (verified CLI); ArgumentParser surface becomes Plan 12 amendment input |
| SSH tunneling | implementation-heavy (unique `TunnelManager`) | **Canonical** |
| Wake-on-LAN | implementation-heavy (unique) | **Canonical** |
| Distribution (scp/rsync, installer -pkg, plist byhost) | implementation-heavy | **Canonical** |
| Inventory + CSV/JSON export | both | implementation-heavy `InventoryCollector`/`ReportExporter` canonical |
| Tests (loopback RFB server, VNCAuth, hextile, framebuffer, scheduler, registry, SQLite backend, tunnel, inventory) | implementation-heavy | **Canonical** — 92/92 pass as of 2026-09-13 |
| Swift Testing suite (31 tests, 5 suites) | scaffold | Excluded from canonical tree (incompatible with canonical API, GPL provenance). Preserved on `OG-Output-Plan-0913` as evidence |
| Clean-room artifacts (behavior-spec YAML ×7, task-lifecycle state machine, `analyze-ard-bundle.sh`, `capture-experiment.sh`, compatibility matrix, protocol spec, security model, SRS, DoD, clean-room policy) | scaffold | **Merged** — no path collisions, no licensing conflict (documentation, not code) |
| CI workflow | implementation-heavy (unique) | **Merged** |
| Release engineering (`build-app.sh`, `setup-client.sh`, launchd plist, changelog) | implementation-heavy (unique) | **Merged** |
| Governance (AGENTS.md, PROGRAM_CHARTER, Plans 00–23, ADRs, product/architecture docs, status ledger) | program-documentation | **Merged** — canonical instruction hierarchy |
| License | **CONFLICT**: MIT (implementation-heavy) vs GPL-3.0 (scaffold) | Canonical = **MIT** per `docs/program/16A-LICENSE-DEPENDENCY-RECONCILIATION.md` default ruling. GPL scaffold code excluded from canonical tree pending owner relicense decision (external gate) |

## 5. Canonical Consolidation (executed)

Canonical branch: **`canonical-091326`** — built from `main`, integrating:

1. `merge: adopt implementation-heavy history (initial-091396) as canonical code base`
2. `merge: scaffold history (OG-Output-Plan-0913) — clean-room artifacts merged, duplicate GPL code excluded by subsystem ruling`
3. `merge: program-documentation history (post-initial-work-091326) — governance, plans 00-23, ADRs, status ledger`

Conflict resolutions: `LICENSE` = MIT; `Package.swift` = canonical implementation manifest; `.gitignore` = union; `README.md` = implementation version (canonical consolidated README authored by this addendum).

## 6. Exit Gate

- [x] Every reported hash/branch/tag from the three conversations located and verified (`git show --stat`, `git branch --contains`).
- [x] `docs/status/REPOSITORY_LINEAGE.md` produced with per-history table.
- [x] Subsystem-by-subsystem comparison completed; strongest implementation selected per subsystem.
- [x] Exactly one canonical development branch (`canonical-091326`) contains every worthwhile non-conflicting contribution from the three histories.
- [x] No unique implementation abandoned without an explicit recorded ruling (see §4 table + lineage doc).
- [ ] Owner confirmation recorded for the MIT/GPL license ruling (external gate → tracked in `16A` and `docs/status/PROGRAM_STATUS.md` §2).
