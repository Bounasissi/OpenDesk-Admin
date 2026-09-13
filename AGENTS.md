# AGENTS.md — OpenDesk Binding Agent Rules

**Status:** BINDING on every coding agent that touches this repository.
**Program:** OpenDesk first-commit → signed, notarized, publicly downloadable v1.0.
**Authoritative state:** `docs/status/program-state.json` (after any context loss).

---

## 1. Mission

Complete the currently assigned OpenDesk plan in full.

Do not stop at implementation. A task is complete only after:

```text
implementation
→ tests
→ integration
→ documentation
→ review
→ remediation
→ evidence
→ commit
→ phase-gate verification
```

---

## 2. No-Question Operating Policy

Do not ask the user to choose:

- library A versus B;
- file names;
- module boundaries;
- naming;
- implementation patterns;
- test strategies;
- refactoring details;
- error-handling strategy;
- UI details that follow established product patterns;
- CI details;
- release-note wording;
- retry values;
- ordinary security defaults;
- whether to fix defects encountered inside current scope.

Make a ruling and continue.

### 2.1 Decision precedence

When something is ambiguous, resolve in this order:

```text
1. Existing verified behavior/tests
2. docs/product/PRODUCT_SPEC.md
3. docs/product/V1_SCOPE.md
4. docs/architecture/*.md
5. Existing repository conventions
6. Current official platform documentation
7. Established technical standards
8. Simplest secure implementation
9. Agent engineering judgment
```

Record material rulings as an ADR in `docs/adr/` using `docs/adr/ADR_TEMPLATE.md`.

### 2.2 Questions permitted only if execution is literally impossible due to an external condition

Examples:

```text
Apple Developer agreement requires interactive acceptance
Developer ID certificate does not exist
required signing secret is unavailable
external service requires MFA interaction
physical hardware required by a release gate is unavailable
legal ownership/licensing conflict cannot be resolved technically
```

Even then:

1. do not ask immediately;
2. finish every task that does not require the missing external resource;
3. automate all prerequisites;
4. document the gate;
5. produce the exact remaining command/action;
6. mark it in `docs/status/PROGRAM_STATUS.md` under `externalGates`.

An external gate does **not** justify abandoning the phase.

---

## 3. Engineering Defaults

Use:

```text
Swift
SwiftUI
AppKit only where required
Swift concurrency / structured concurrency
SQLite
macOS Keychain
Network.framework
OSLog
XCTest or Swift Testing per repo convention
```

Prefer native Apple frameworks before adding dependencies.

Do not add a dependency if less than roughly one day's implementation avoids it and the native implementation is maintainable.

---

## 4. Git Rules

- Never implement directly on `main`.
- Per plan: isolated worktree/branch → implementation → tests → task review → full-plan review → CI → merge.
- Never force-push shared branches.
- Prefer small conventional commits:

```text
feat: fix: test: docs: refactor: build: ci: chore:
```

---

## 5. TDD Rule

For deterministic business logic:

```text
failing test → verify failure → minimal implementation → verify pass → refactor → rerun
```

UI, networking, and OS-integration work must still have the strongest practical automated coverage plus integration harnesses.

---

## 6. Review Rule

Every meaningful task receives:

1. specification-compliance review;
2. code-quality/security review.

Every plan receives a final branch-level review. Review findings are fixed automatically — never ask whether findings should be fixed.

---

## 7. Completion Ledger

Every plan updates on completion:

```text
docs/status/PROGRAM_STATUS.md
docs/status/program-state.json
```

`program-state.json` shape:

```json
{
  "currentPlan": "06-RFB-REMOTE-CONTROL",
  "status": "executing",
  "completedPlans": ["01", "02", "03", "04", "05"],
  "externalGates": [],
  "blockingDefects": []
}
```

This state is authoritative after context loss.

---

## 8. Autonomous Ruling Format

```text
RULING:
Decision:
Evidence:
Reason:
Alternative rejected:
Cost if wrong:
Reversible: yes/no
```

---

## 9. Circuit Breaker

A task may receive five remediation passes. After five unsuccessful passes:

- reduce the failing system to its smallest reproducible case;
- use a fresh higher-capability debugging agent;
- reassess whether the design violates an OS/API constraint;
- select the smallest architectural correction;
- document it (ADR if material);
- continue.

Do not endlessly rerun the same fix.

---

## 10. Where the Plans Live

All phase instruction documents: `docs/program/00-MASTER-ORCHESTRATOR.md` through `docs/program/23-POST-LAUNCH-OPERATIONS.md`.

Program-wide policy (Definition of Done, phase-gate protocol, handoff contract, milestone order, scope discipline, external gates): `docs/program/PROGRAM_CHARTER.md`.

Execution entry point for any new session: `docs/program/00-MASTER-ORCHESTRATOR.md`.
