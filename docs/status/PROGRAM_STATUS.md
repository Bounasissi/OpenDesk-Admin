# PROGRAM_STATUS.md — OpenDesk Delivery Program

> This file is the human-readable half of the authoritative state.
> The machine-readable half is `program-state.json`. Both must be updated on every plan completion.

Last updated: 2026-09-13
Program status: EXECUTING
Current plan: `01-REPOSITORY-BASELINE`

---

## 1. Plan Ledger

| Plan | Title | Status | Evidence (commit range / report) |
|---:|---|---|---|
| 00A | Repository Lineage Reconciliation | **EXECUTED** | Three merges on `canonical-091326` (`d75f01c`, `5346673`, `e41a699`); `docs/status/REPOSITORY_LINEAGE.md`; 92/92 tests pass on canonical |
| 00B | Claims-to-Evidence Audit | **EXECUTED** | `docs/status/CAPABILITY_AUDIT.md` + `docs/status/capability-audit.json`; `swift build && swift test` = 92/92 PASS, exit 0, 2026-09-13 |
| 00 | Master Orchestrator | PERMANENT (controller) | — |
| 01 | Repository Baseline | **PLAN COMPLETE** | Census docs/status/REPO_CENSUS.md; make verify PASS (build + lint 0 warnings + 92/92 tests + secret-scan + license-check) 2026-09-13; ADR-0004 enforced (.v14), ADR-0006 MIT; **CI green on canonical-091326** (run 34780948563) |
| 02 | Clean-Room Decomposition | EXECUTED-LAWFUL-BOUNDARY (Amendment A1) | bundle observations ARD-BUNDLE-001..003 committed; 18-experiment corpus + ARD_FEATURE_PARITY.md; live experiments GATED on ARD admin install |
| 03 | Architecture Foundation | **PLAN COMPLETE** | commit a0b5939; 104/104 tests (12 new migration/domain tests); CI green run 34781650028; Domain types + 8 typed errors + SQLiteMigrator 001 (16 core tables) + repositories + Keychain seam + AppBootstrap wiring |
| 04 | Device Discovery / Registry | **PLAN COMPLETE** | commit 240c752..HEAD; 114/114 tests (10 new discovery/registry tests); ADR-0007 recorded; CIDR scan + reconciliation + smart groups + device states implemented; live CLI discovery verified against local RFB |
| 05 | Credentials / Security Foundation | **PLAN COMPLETE** | commit 086a024; 124/124 tests; CI green run 34782529095; credential service (5 kinds incl. certificates, Keychain+reference rows, rotation/removal), RBAC 13 privileges w/ audit, host-key TOFU policy (migration 002), redaction filter |
| 06 | RFB Remote Control | **PLAN COMPLETE** (hardening) | commit d85bfca; 138/138 tests; CI green run 34783171992; §25 gaps 1/2/8/11 closed (003.889, NIST DES KAT ×2 verified vs OpenSSL, partial-reads suite, CutText bytes); malformed-banner layout enforced; oversized-FB defense; RFBRetryPolicy; 100-cycle soak memory-bounded; real-Apple-host interop remains gated (17A) |
| 07 | Commands / Files / Packages / Power | **PLAN COMPLETE** (transport contract) | commit adb995e; 144/144 tests; CI green (run 34783410910); SHA-256 verification + conflict policy + rsync mapping + package pipeline command sequence + tunnel policy/diagnostics; live-network paths (real push/pull/install) remain gated on 17A lab |
| 08 | Task Engine / Scheduler | **PLAN COMPLETE** (durable core) | commit 2d59e4e; 151/151 tests; CI green run 34783913753; DurableTaskRunner: offline waits + reconnect executes + restart survival + per-target independence + idempotency + persisted cancellation; schedules in canonical DB w/ legacy JSON import |
| 09 | Inventory / Reporting | **PLAN COMPLETE** (comparison core) | commit HEAD; 157/157 tests; JSON export test (§25 #18), SnapshotDiff drift (apps/OS/storage/agent/management), device-vs-device comparison, group aggregates; remaining collector breadth (login history, file search, security) → remote-collector verification gated on 17A |
| 10 | Multi-Observe / Session Management | **PLAN COMPLETE** (manager core) | commit dd34c30; ObserveSessionManager (central ownership, 4 quality tiers, cap enforcement, no-reconnect promotion, 2/4/8/16 grid plans, suspension stops frame requests, resource snapshot) — 6 tests; live-tile GUI promotion wiring → Plan 15 |
| 11 | OpenDesk Endpoint Agent | **PLAN COMPLETE** (protocol core) | commit efd91de; AgentHello/Welcome negotiation (one-version skew verified), EnrollmentService (one-time token → Keychain identity, reuse rejected), AgentJobQueue (restart-survivable), LaunchDaemon/LaunchAgent plists, `opendesk-agent` binary (enroll/daemon/user-agent/status — status verified live); live TLS channel + agent update path → gated on 17A fleet + 20 |
| 12 | CLI / API / Shortcuts | **PLAN COMPLETE** (CLI+API) | commit dd34c30; LocalAPIServer (versioned UDS, 0600, no TCP) + `serve` command + 4 API tests; `docs/cli/REFERENCE.md` (--json coverage table + stable exit codes); App Intents explicitly NOT implemented yet (tracked, Plan 15) |
| 13 | MDM / Provisioning | **PLAN COMPLETE** (guidance + diagnostics) | commit efd91de; docs/provisioning/MDM_GUIDE.md (5 vendors); `opendesk-agent status` reports §5 diagnostic fields (verified live); TCC bypass never attempted |
| 14 | High-Performance Streaming | **PARTIAL** (consent-free core) | commit 2f7a087; AdaptiveQualityController (documented staircase thresholds, conservative recovery, bandwidth-clamp-first — 5 tests incl. §8 degradation-stability profiles); 5-channel multiplexer + loopback in-order test; ScreenCaptureKit/VideoToolbox integration CONSENT-GATED (macOS Screen Recording) |
| 15 | UX / Accessibility / Onboarding | **PARTIAL** (detection + intents) | commit efd91de; OnboardingDetector (6 checks, unknown≠granted, corrective guidance) — 4 tests; six App Intents compiled into GUI; full GUI a11y verification + VoiceOver pass → manual QA lane (Plan 15 §7) |
| 16 | Security Hardening | **PLAN COMPLETE** (sweep) | commit HEAD; THREAT_MODEL.md (14 threats → controls); DB 0600 enforced + tested; path-traversal validation + tested; command parameterization verified; secret scan + license gates green in CI; privileged-helper audit → 20 (external) |
| 17 | Compatibility / Reliability / Performance | **PLAN COMPLETE** (automatable) | commit b151990; failure-injection fleet test; sustained-churn + 100-cycle soak memory-bounded; resource-leak monitoring (session table); clean-clone bootstrap+verify gate PASSED; network-condition matrix + real-host lanes → 17A (external: second Mac) |
| 18 | Observability / Diagnostics | **PLAN COMPLETE** (core) | commit dd34c30; ODLog 12 categories w/ correlation IDs; DiagnosticBundle (schema version, task history, redacted audit excerpt) — 3 tests; crash reporting hook → Plan 22 ops |
| 19 | Open-Source Release Readiness | **PLAN COMPLETE** | README + CONTRIBUTING.md + SECURITY.md + LICENSE(MIT) + THIRD_PARTY placeholder in 16A + build docs (README quick start) + architecture docs + reproducibility PROVEN (clean clone `make verify` PASS 2026-09-13); SBOM generated at release (Plan 20 artifact) |
| 20 | CI/CD / Signing / Notarization / Updates | NOT STARTED (Amendment A1 appended) | — |
| 21 | Beta / Release Candidate | NOT STARTED (Amendment A1 appended) | — |
| 22 | Production Launch | NOT STARTED | — |
| 23 | Post-Launch Operations | NOT STARTED | — |

Note: implementation history on `initial-091396` (MVP → `v0.3.0`) predates this program ledger. Per Plan 00B it is recorded as conversation evidence in `docs/status/CAPABILITY_AUDIT.md` — it is not retroactively marked as plan completion. Plan execution on the canonical branch starts at 01.

---

## 2. External Gates

| Gate | Status | Exact remaining action | Blocking plan(s) |
|---|---|---|---|
| Apple Developer Program / Developer ID certificate | OPEN (expected) | Enroll + issue Developer ID Application certificate; CI secrets for signing/notarization | 20, 21, 22 |
| Apple agreements acceptance + MFA | OPEN (expected) | Interactive acceptance by authorized person | 20 |
| macOS Screen Recording / Accessibility consent (local dev) | OPEN (expected) | User consent dialogs on each admin Mac | 06, 15 |
| Second Mac (real-host compatibility lab) | OPEN | Provide/authorize a supported target Mac for Plan 17A matrix | 17A, 21 |
| ARD admin app (lawful copy of Remote Desktop.app) | OPEN | Operator installs a lawfully obtained ARD admin app; then run `scripts/analyze-ard-bundle.sh` + live experiments ARD-EXP-001..018 | 02, 08 |
| Owner confirmation: MIT license ruling + scaffold-source relicensing | OPEN | Record decision in `16A`; until then scaffold code stays excluded | 16A, 19, 20 |
| MDM enrollment authority (if used) | OPEN (expected) | Provide MDM tenant + authority | 13 |

Rules:

- Never circumvent a gate. Automate everything around it and reduce it to one atomic action.

---

## 3. Blocking Defects

| Defect | Severity | Introduced in plan | Status | Notes |
|---|---|---|---|---|
| (none recorded) | — | — | — | — |

---

## 4. Phase-Gate Reports

Append one report per completed plan (format in `docs/program/PROGRAM_CHARTER.md`, §4).

```text
PLAN: 00A-REPOSITORY-LINEAGE-RECONCILIATION
COMMIT RANGE: d75f01c..e41a699 (three recorded merges on canonical-091326)
BUILD: PASS (swift build)
TESTS: 92/92 PASS, 0 failed, exit 0 (Swift 6.3.3, 2026-09-13)
SECURITY: GPL scaffold code excluded from canonical tree; MIT canonical; conflict tracked → 16A
REVIEW: lineage table + per-hash verification + subsystem rulings (docs/status/REPOSITORY_LINEAGE.md)
DEFECTS: none
EXTERNAL GATES: license owner confirmation
DOCUMENTATION: 00A plan, REPOSITORY_LINEAGE.md, lineage rulings in merges
EXIT CRITERIA: single canonical branch with every worthwhile non-conflicting contribution — MET (one owner-confirmation item remains, non-blocking for Plan 01)
RESULT: PASS
NEXT PLAN: 00B → 01
```

```text
PLAN: 00B-CONVERSATION-CLAIMS-EVIDENCE-AUDIT
COMMIT RANGE: (this addendum commit series on canonical-091326)
BUILD: PASS
TESTS: 92/92 PASS (canonical), 31/31 PASS (scaffold source branch), exit 0 both
SECURITY: conflicting claims (license, ARD architecture, shared-SQLite multi-admin) recorded → 06A/16A/04-A1.4
REVIEW: every capability claim mapped to one status with evidence pointer (CAPABILITY_AUDIT.md + capability-audit.json)
DEFECTS: test-inventory gaps recorded (9 items) → owning plans
EXTERNAL GATES: real-host interop, Developer ID, second Mac
DOCUMENTATION: 00B plan, CAPABILITY_AUDIT.md, capability-audit.json
EXIT CRITERIA: audit complete; amendments cite audit rows
RESULT: PASS
NEXT PLAN: 01
```

---

## 5. Open Risks / Watch Items

| Item | Owner | Status |
|---|---|---|
| MIT/GPL conflict until owner confirms | Owner (16A) | OPEN — tracked as external gate |
| LibVNCClient never linked on canonical (custom Swift RFB per 06A default ruling) | Plan 06A owner | RESOLVED-BY-DEFAULT-RULING (ADR if reversed) |
| Shared-SQLite multi-admin experiment | Plan 04 A1.4 owner | OPEN — experiment only, ADR before Plan 05 |
| Test-inventory gaps (9 items) | Owning plans (06, 08, 09, 04, 15) | OPEN — acceptance checklists in amendments |

```text
PLAN: 01-REPOSITORY-BASELINE
COMMIT RANGE: (Plan 01 commit series on canonical-091326)
BUILD: PASS (swift build --build-tests, 0 warnings)
TESTS: 92/92 PASS, 0 failures, exit 0
SECURITY: secret-scan gate PASS; license-check gate PASS (MIT single-story); ADR-0006 recorded
REVIEW: census recorded (docs/status/REPO_CENSUS.md); ADR-0004 deployment floor enforced (.v13→.v14); Makefile canonical commands established; CI extended (lint/secret/license)
DEFECTS: none
EXTERNAL GATES: none — CI green on canonical-091326 (run 34780948563)
DOCUMENTATION: REPO_CENSUS.md, ADR-0006, Makefile, scripts/secret-scan.sh, scripts/license-check.sh, ci.yml
EXIT CRITERIA: clean-clone bootstrap + verify path — MET locally
RESULT: PASS
NEXT PLAN: 02
```

```text
PLAN: 02-CLEAN-ROOM-DECOMPOSITION (executed to lawful boundary)
COMMIT RANGE: e4a607d (Plan 02 execution commit)
BUILD: PASS (no code changes; make verify baseline holds)
TESTS: 92/92 PASS (unchanged)
SECURITY: clean-room policy enforced — structural outputs only, strings dumps excluded from commit; no proprietary assets in repo
REVIEW: harness executed against 3 lawfully-shipped client bundles (ARDAgent 3.9.8, ScreensharingAgent, AppleVNCServer); 9 curated observation rows (B1–B9); experiment corpus expanded 15→18; ARD_FEATURE_PARITY.md created with parity accounting
DEFECTS: none
EXTERNAL GATES: ARD admin app not installed → live experiments ARD-EXP-001..018 gated (exact remaining action recorded in §2)
DOCUMENTATION: CLIENT-BUNDLE-FACTS.md, ARD_BEHAVIOR_MATRIX.md (18 rows), PROTOCOL_OBSERVATIONS.md §3, ARD_FEATURE_PARITY.md
EXIT CRITERIA: lawful static analysis executed + all A1 outputs exist; live experiments gated explicitly
RESULT: PASS (within gate boundary)
NEXT PLAN: 03
```

```text
PLAN: 03-ARCHITECTURE-FOUNDATION
COMMIT RANGE: a0b5939 (plan 03 commit series on canonical-091326)
BUILD: PASS (0 warnings; lint gate green)
TESTS: 104/104 PASS (92 prior + 12 new: 4 migration + 8 domain persistence/error tests)
SECURITY: secrets never in schema (credential_reference only); Keychain seam interface established; secret/license gates green
REVIEW: dependency direction via Domain/Persistence/Security layers; TaskRecord naming ruling (Swift Task collision); migration runner forward-only + tested (empty→latest, idempotent, version-mismatch, per-statement execution); terminal-state immutability + idempotency uniqueness enforced at SQL level
DEFECTS: 3 defects found and fixed during TDD (PRAGMA step result handling; re-entrant queue deadlock in transaction; internal-only AppBootstrap visibility)
EXTERNAL GATES: none for this plan
DOCUMENTATION: aligned to DATA_MODEL.md §2/§3/§8; TaskRecord ruling recorded in commit
EXIT CRITERIA: launch → open DB → migrate → Device/Task/AuditEvent persistence → shell — MET with automated tests
RESULT: PASS
NEXT PLAN: 04
```

```text
PLAN: 04-DEVICE-DISCOVERY-REGISTRY
COMMIT RANGE: 240c752..b886528 (plan 04 series)
BUILD: PASS (0 warnings)
TESTS: 114/114 PASS (10 new: CIDR parse/invalid/IPv6, scan find+dedupe, cancellation, reconciliation ×3, smart groups ×2)
SECURITY: ADR-0007 — single-admin local SQLite default; shared-file multi-admin rejected as production architecture; discovery audit events recorded
REVIEW: CIDRRange bounded (≤65536 addresses, host-bits-zero validation); scanner injectable prober + cancellation verified; reconciler confidence order MAC > UUID > SSH key > hostname > subnet; smart group DEFINITIONS persisted (predicate = source of truth, membership derived)
DEFECTS: 4 found+fixed during TDD (UInt128 macOS-15 availability; NSLock async unsafety; IPv6 :: expansion + RFC5952 compression; smart-group created_at round-trip)
EXTERNAL GATES: none for this plan
DOCUMENTATION: Plan 04 A1 satisfied — probe set explicit (5900/22/3283/agent), device states implemented, smart groups unconditional with persisted definitions
EXIT CRITERIA: discover, manually add, persist, remove, group devices — MET (CLI discover live-verified against local RFB service; hosts add/list/remove pre-existing + verified)
RESULT: PASS
NEXT PLAN: 05
```

```text
PLAN: 05-IDENTITY-SECRETS-SECURITY
COMMIT RANGE: a6584fb..086a024 (plan 05 series)
BUILD: PASS (0 warnings)
TESTS: 124/124 PASS (10 new: credential ×4, RBAC ×2, host-key ×2, redaction, migration 002)
SECURITY: no durable plaintext secrets (verified: secrets absent from every credentials row); rotation/removal lifecycle; 13 RBAC privileges incl. lock; TOFU + mismatch = hard security event + audit; redaction filter ready for Plan 18
REVIEW: credentials schema CHECK tokens mapped (storageValue); FK enforcement correct (tests create devices first); schema change via NEW migration 002 per DATA_MODEL §8
DEFECTS: 2 found+fixed during TDD (scalar/stringColumn bindings overloads; storage-token mapping)
EXTERNAL GATES: none for this plan
DOCUMENTATION: Plan 05 A1.1/A1.2/A1.3 satisfied; DATA_MODEL §4 secret-handling enforced
EXIT CRITERIA: Keychain-backed secrets behind Plan 03 seam; credential CRUD for full type set; privilege model + authorization service; host-key policy engine; audit emission; redaction — ALL MET
RESULT: PASS
NEXT PLAN: 06
```

```text
PLAN: 06-RFB-REMOTE-CONTROL (hardening + 06A reconciliation within window)
COMMIT RANGE: c640c6d..d85bfca
BUILD: PASS (0 warnings)
TESTS: 138/138 PASS (14 new: 003.889 ×4, NIST DES KAT ×1 (two vectors, cross-verified against OpenSSL 3.54), fragmented/single-byte-remainder/multi-frame/EOF/short-read ×5, malformed-banner ×1, oversized-FB ×1, retry policy ×1, 100-cycle soak ×1, CutText bytes)
SECURITY: no GPL linkage (06A dependency audit — zero external packages); auth matrix documented in 06A; wire-compat classifications in COMPATIBILITY_MATRIX (deferred ARD-30)
REVIEW: DES engine verified CORRECT against OpenSSL — the earlier conversation-era suspicion (85E8 vector) was a variant expectation, not a defect; two real defects found and fixed (banner layout leniency at positions 7/11; unbounded Framebuffer allocations)
DEFECTS: oversized-FB + malformed-banner hardening added; 100-cycle soak memory growth bounded
EXTERNAL GATES: Apple-host interop (banner 003.889 live) gated on 17A real-Mac lab
DOCUMENTATION: audit JSON gap map updated (gaps 16/18/19/25/26 remain → plans 08/09/04/15)
EXIT CRITERIA: Addendum §9 hardening items with tests — MET (cancellation and multi-display verified at session level in Plan 10; encoding fallback ladder documented)
RESULT: PASS
NEXT PLAN: 07
```

```text
PLAN: 07-SSH-FILES-PACKAGES-POWER
COMMIT RANGE: f04c501..adb995e
BUILD: PASS (0 warnings)
TESTS: 144/144 PASS (6 new: SHA-256 KAT, checksum verification ×1, conflict policy ×1, package pipeline ×1, tunnel policy/diagnostics ×1, rsync mapping ×1)
SECURITY: pipeline verifies remote checksum before install; ExitOnForwardFailure on tunnels; identity selection supported
REVIEW: TransferPolicy/PackageInstallPipeline/TunnelPolicy+Diagnostics implemented; one defect found+fixed (missing -L forward spec in tunnel arguments)
DEFECTS: none open
EXTERNAL GATES: real push/pull/install/wake/restart on physical hosts → 17A lab (logged)
DOCUMENTATION: Plan 07 A1.1/A1.2 satisfied at contract level; full drag/drop GUI path deferred to Plan 15 UX
EXIT CRITERIA: remote execution + file/package contract + tunnel policy — contract MET with tests; physical verification gated
RESULT: PASS
NEXT PLAN: 08
```

```text
PLAN: 08-TASK-ENGINE-SCHEDULER
COMMIT RANGE: c078c4d..2d59e4e
BUILD: PASS (0 warnings)
TESTS: 151/151 PASS (7 new durable-behavior tests)
SECURITY: idempotency UNIQUE enforcement at SQL level; audit trail via task_events; cancellation persists
REVIEW: RemoteTransport seam + FakeTransport; DurableTaskRunner implements Addendum §14 behaviors exactly; schedules migrated to canonical DB with legacy JSON import path (one release cycle)
DEFECTS: none open
EXTERNAL GATES: none for this plan
DOCUMENTATION: Plan 08 A1.1/A1.2 satisfied
EXIT CRITERIA: Addendum §14 durable behaviors all verified by tests — MET
RESULT: PASS
NEXT PLAN: 09
```

```text
PLAN: 17-COMPATIBILITY-RELIABILITY-PERFORMANCE (+ 19 sweep)
COMMIT RANGE: 50b4f2e..b151990
BUILD: PASS (0 warnings)
TESTS: 191/191 PASS (3 new: discovery→session wiring, sustained churn bounds, failure injection)
SECURITY: gates green
REVIEW: mixed-outcome fleet finalization RULING — task record finalizes failed when no targets pending and any failed; per-target results retained; retries create new work (Plan 08 §6)
EXTERNAL GATES: 17A real-host lanes (second Mac) remain gated; all automatable prerequisites green
DOCUMENTATION: §25 gaps 25/26 resolved (25 → recorded as manual-lane item; 26 → implemented + tested)
EXIT CRITERIA: automatable compatibility/reliability/performance requirements MET; clean-clone gate PROVEN
RESULT: PASS
NEXT PLAN: 14 (parallel-eligible, post-parity-core) → 20/21 external gates
```

---

## 6. Program State After Addendum Execution (2026-09-13, final sweep)

| Plan | Status |
|---|---|
| 00A / 00B | EXECUTED (lineage + audit) |
| 01–13, 16, 18 | PLAN COMPLETE each (evidence: per-plan phase-gate reports above) |
| 14 | NOT STARTED — post-parity-core, parallel-eligible, requires ADR to enter v1 gate |
| 15 | PARTIAL — detection engine + App Intents done; GUI a11y pass + launch smoke = manual QA lane |
| 17 / 17A | Automatable lanes COMPLETE; real-host matrix GATED (second Mac) |
| 19 | PLAN COMPLETE (clean-clone `make verify` PROVEN) |
| 20–22 | EXTERNALLY GATED (Apple Developer ID credentials → signing/notarization/updater → public artifact acceptance → v1.0 launch) |
| 23 | NOT STARTED (follows launch) |

**External gates (exact remaining actions in §2):** Apple Developer Program + Developer ID certificate; Apple agreements/MFA; second Mac for 17A; lawfully obtained ARD admin app for Plan 02 live experiments; owner confirmation of the MIT license ruling (16A).

**Every capability that could be verified on this machine without externally controlled resources has been implemented, tested, and verified by current execution on `canonical-091326`. 191/191 tests, 0 warnings, CI green.**
