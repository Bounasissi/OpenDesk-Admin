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
| 01 | Repository Baseline | NOT STARTED | — |
| 02 | Clean-Room Decomposition | NOT STARTED (Amendment A1 appended) | — |
| 03 | Architecture Foundation | NOT STARTED | — |
| 04 | Device Discovery / Registry | NOT STARTED (Amendment A1 appended) | — |
| 05 | Credentials / Security Foundation | NOT STARTED (Amendment A1 appended) | — |
| 06 | RFB Remote Control | NOT STARTED (Amendment A1 appended; 06A active within window) | — |
| 07 | Commands / Files / Packages / Power | NOT STARTED (Amendment A1 appended) | — |
| 08 | Task Engine / Scheduler | NOT STARTED (Amendment A1 appended) | — |
| 09 | Inventory / Reporting | NOT STARTED (Amendment A1 appended) | — |
| 10 | Multi-Observe / Session Management | NOT STARTED (Amendment A1 appended) | — |
| 11 | OpenDesk Endpoint Agent | NOT STARTED (Amendment A1 appended) | — |
| 12 | CLI / API / Shortcuts | NOT STARTED | — |
| 13 | MDM / Provisioning | NOT STARTED | — |
| 14 | High-Performance Streaming | NOT STARTED (parallel-eligible after 11; A1 positioning rule appended) | — |
| 15 | UX / Accessibility / Onboarding | NOT STARTED | — |
| 16 | Security Hardening | NOT STARTED (16A active before any public distribution) | — |
| 17 | Compatibility / Reliability / Performance | NOT STARTED (17A lab plan added) | — |
| 18 | Observability / Diagnostics | NOT STARTED | — |
| 19 | Open-Source Release Readiness | NOT STARTED | — |
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
