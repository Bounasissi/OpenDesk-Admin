# REPOSITORY_LINEAGE — OpenDesk-Admin

> Produced by Plan 00A (Repository Lineage Reconciliation), executed 2026-09-13.
> Canonical branch: **`canonical-091326`**.
> Central rule: conversation claims are historical evidence, not current repository truth.

---

## 1. History Verification

| History | Branch / commit | Exists | Verified by | Unique value | Superseded | Merge action |
|---|---|---:|---|---|---:|---|
| Implementation-heavy (MVP → v0.3.0) | `initial-091396` @ `b785220` | YES | `git show --stat` + `git branch --contains` on all 10 reported hashes; `swift build` + `swift test` = 92/92 PASS, exit 0, 2026-09-13 | RFB protocol stack (Raw/Hextile decoders, keysym, renderer, connection), loopback RFB TCP server + auth tests, GUI (dashboard, tiled observe, streamer), CLI, task engine + scheduler + TaskStore + WOL, SSH tunnel, distribution engine, SQLite/JSON registry, CI workflow, app packaging scripts, MIT license | — | **Merged as canonical code base** (merge `d75f01c`) |
| Architecture/scaffold (OG output plan) | `OG-Output-Plan-0913` @ `ed4d091` (reported head commits `83bc198`, `b36e9c6` also present) | YES | same forensic pass; `swift build` + `swift test` = 31/31 PASS (5 suites), exit 0, 2026-09-13 | Clean-room artifacts: 7 behavior-spec YAMLs, task-lifecycle state machine, `analyze-ard-bundle.sh`, `capture-experiment.sh`, compatibility matrix, protocol spec, security model, SRS, DoD, clean-room policy; reference implementations (Discovery w/ CIDR, SQLite 21-table schema, RRULE scheduler, Smart Groups predicates, power ops, checksum transfers, ARD-30 RFB, ArgumentParser CLI, Swift Testing suite, GPL-3.0 license) | Reference implementations superseded by canonical tree (see rulings §2); artifacts preserved on source branch | **Partially merged** (merge `5346673`): docs + reverse-engineering + analysis scripts merged; code paths (`packages/`, `apps/`, `tests/`, `Package.resolved`) excluded by ruling |
| Program-documentation | `post-initial-work-091326` @ `038952d` | YES | `git show` of AGENTS.md, PROGRAM_CHARTER.md, Plans 00–23, status ledger | Binding instruction hierarchy: AGENTS.md, PROGRAM_CHARTER.md, Plans 00–23, ADRs 0001–0005, product spec, V1 scope, architecture docs, clean-room docs, release docs, runbooks, status ledger | — | **Merged in full** (merge `e41a699`) |

### Reported hash verification

| Reported hash | Subject (truncated) | Reachable from | Status |
|---|---|---|---|
| `e808761` | OpenDesk-Admin MVP: RFB/VNC client, SSH task engine, inventory, distribution, CLI | `initial-091396`, `canonical-091326` | VERIFIED |
| `f383d84` | Add .gitignore; remove committed build artifacts | same | VERIFIED |
| `2a999f5` | Phase 2 complete: framebuffer decoding, fleet tasks, WOL, saved tasks, exports, discovery, GUI | same | VERIFIED |
| `7f1c5c9` | Live screen streaming + control mode input routing | same | VERIFIED |
| `df7215d` | Update roadmap: Phase 3 core complete | same | VERIFIED |
| `b6d0e69` | Tiled observation, task scheduler, plist payloads | same | VERIFIED |
| `4b63ee2` | Hextile encoding, SSH tunnel for WAN, app packaging, launchd scheduler | same | VERIFIED |
| `068864e` | README: packaging + launchd sections | same | VERIFIED |
| `a7fb815` | SQLite registry backend, hextile bandwidth validation, client provisioning, changelog (**tag `v0.3.0`**) | same | VERIFIED |
| `b785220` | Loopback RFB server: authenticated end-to-end protocol tests over real TCP | same | VERIFIED |
| `83bc198` | Scaffold OpenDesk Admin: clean-room ARD replacement blueprint | `OG-Output-Plan-0913`, `canonical-091326` | VERIFIED |
| `b36e9c6` | Remove stray sqlite3 WAL artifacts | same | VERIFIED |

Tag `v0.3.0` → `a7fb815` (SQLite registry backend commit). **Ruling:** `v0.3.0` is a development tag on a dev branch, not a release artifact; it must not be treated as v1 readiness evidence (Addendum §27).

## 2. Subsystem-by-Subsystem Rulings

| Subsystem | Winner | Ruling / evidence |
|---|---|---|
| RFB protocol depth | implementation-heavy | Raw + Hextile decoders, keysym map, renderer, connection, loopback TCP server with VNC auth + wrong-password rejection; 92/92 tests pass 2026-09-13. Scaffold RFBClient (688 lines, advertises ARD security type 30) **superseded as code; recorded as reference input for Plan 06A** |
| Discovery | implementation-heavy | FleetDiscovery (`_rfb._tcp` Bonjour) canonical. Scaffold CIDR-scan + dedupe **not merged (GPL provenance, API collision); recorded as REQUIRED TASKS in Plan 04 amendment** |
| Persistence | implementation-heavy (runtime), scaffold (schema design) | Canonical HostRegistry + JSON/SQLite backends. Scaffold 21-table schema (devices, credentials→Keychain indirection, groups, smart groups, tasks, task_events, audit_events) **adopted as reference schema specification for Plan 03**; scaffold Swift not merged |
| Task engine | implementation-heavy (runtime), scaffold (concepts) | TaskEngine + TaskStore + bounded fleet concurrency canonical. Idempotency keys / durable state machine / event log = **Plan 08 amendment requirements**, reference: scaffold `TaskEngine.swift` |
| Scheduler | implementation-heavy (runtime), scaffold (model) | Interval + daily triggers canonical. RRULE / run-once-later / on-reconnect / on-predicate = **Plan 08 amendment requirements**, reference: scaffold `Scheduler.swift` |
| Smart groups | scaffold (unique) | Not merged. **Required feature — Plan 04 amendment**; predicate-engine design recorded as reference |
| Power management | scaffold (unique) | Not merged. **Required behavior — Plan 07 amendment** |
| Inventory | implementation-heavy | InventoryCollector + ReportExporter (CSV RFC-4180 + JSON) canonical |
| GUI | implementation-heavy | SwiftUI dashboard, tiled observation, screen streamer; unique in all histories → canonical |
| CLI | implementation-heavy | `main.swift` custom CLI verified. Scaffold ArgumentParser surface recorded as Plan 12 amendment input |
| SSH | implementation-heavy | SSHTransport + TunnelManager (WAN tunneling) canonical |
| WOL | implementation-heavy | RFC magic packet implementation + test canonical |
| Tests | implementation-heavy | 92 XCTest cases pass 2026-09-13; scaffold 31 Swift-Testing cases pass on source branch only (excluded from canonical tree — incompatible API, GPL provenance) |
| CI | implementation-heavy | `.github/workflows/ci.yml` canonical |
| Release engineering | implementation-heavy | build-app.sh, setup-client.sh, launchd plist, CHANGELOG |
| Clean-room artifacts | scaffold | **Merged** (documentation-only, no licensing conflict) |
| Governance | program-documentation | **Merged in full** |
| License | CONFLICT | MIT (implementation-heavy) vs GPL-3.0 (scaffold). **Default ruling: MIT** — canonical tree contains zero GPL-linked code; scaffold Swift sources excluded pending owner relicensing confirmation (external gate, tracked in 16A + PROGRAM_STATUS §2) |

## 3. Canonical Branch State

- `canonical-091326` = `main` (initial commit) + three recorded merges (see §1).
- 125 tracked files at reconciliation; working tree clean.
- App re-verification on canonical branch recorded in `docs/status/CAPABILITY_AUDIT.md`.

## 4. Residual Rulings

```text
RULING: scaffold Swift sources not merged
Decision: exclude packages/, apps/, tests/, Package.resolved from canonical tree
Evidence: GPL-3.0 LICENSE in OG-Output-Plan-0913; API collisions with canonical OpenDeskCore
Reason: one authoritative licensing story + one implementation per subsystem
Alternative rejected: dual-tracking both trees in one package
Cost if wrong: lost scaffold-only features (CIDR scan, RRULE scheduler, smart groups) — mitigated: recorded as required plan tasks
Reversible: yes
```

```text
RULING: canonical branch = canonical-091326 (not main)
Decision: consolidate on canonical-091326; main advance is owner's trivial act after CI green
Evidence: AGENTS.md §4 forbids implementing directly on main
Reason: merge verification precedes promotion
Alternative rejected: merging directly onto main
Cost if wrong: none (fast-forward available at any time)
Reversible: yes
```

## 5. Exit Gate (00A §6)

- [x] All reported hashes/branches/tags located and verified.
- [x] Lineage table produced (this document).
- [x] Subsystem comparison completed with strongest implementation per subsystem.
- [x] Exactly one canonical branch containing every worthwhile non-conflicting contribution.
- [x] No unique implementation abandoned without a recorded ruling.
- [ ] Owner confirmation for the license ruling (external gate → 16A + PROGRAM_STATUS §2).
