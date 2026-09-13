# Plan 00 — Master Orchestrator

> Binding instruction document. Read `/AGENTS.md` and `docs/program/PROGRAM_CHARTER.md` before executing anything.
> This plan never completes. It is the permanent controller for Plans 01–23.

- **Plan ID:** 00
- **Type:** Permanent controller
- **Prerequisites:** None
- **Blocks:** All plans

---

## 1. Goal

Provide one controller capable of driving all remaining plans sequentially without losing state or rediscovering completed work.

---

## 2. Orchestrator Session Protocol

Every controlling agent must:

1. read `/AGENTS.md`;
2. read `docs/program/PROGRAM_CHARTER.md` (milestone order, phase-gate protocol, handoff contract);
3. inspect Git history (`git log`, branches);
4. inspect repository structure;
5. inspect existing tests and CI;
6. inspect open issues/PRs when repository access exists;
7. read `docs/status/program-state.json`;
8. determine the first incomplete plan;
9. execute only that plan;
10. obtain independent review;
11. merge only when its exit gate passes;
12. update `docs/status/PROGRAM_STATUS.md` and `docs/status/program-state.json`;
13. immediately begin the next plan.

**Never restart completed phases.**

---

## 3. Per-Plan Execution Requirements

Each plan execution gets:

```text
isolated worktree
dedicated branch
progress ledger
test evidence
review evidence
commit history
phase report
```

Git mechanics per `AGENTS.md` §4: never implement directly on `main`; branch per plan; small conventional commits; no force-pushes to shared branches.

---

## 4. Autonomous Ruling Format

When ambiguity is resolved without asking the user, emit:

```text
RULING:
Decision:
Evidence:
Reason:
Alternative rejected:
Cost if wrong:
Reversible: yes/no
```

Material rulings become ADRs in `docs/adr/`.

---

## 5. Circuit Breaker

A task may receive five remediation passes. After five unsuccessful passes:

1. reduce the failing system to its smallest reproducible case;
2. use a fresh higher-capability debugging agent;
3. reassess whether the design violates an OS/API constraint;
4. select the smallest architectural correction;
5. document it (ADR if material);
6. continue.

Do not endlessly rerun the same fix.

---

## 6. Parallelism Policy

- Plan 14 may run in parallel after Plan 11 completes.
- No other plan runs in parallel with its successor on the critical path unless the milestone order in `PROGRAM_CHARTER.md` §2 marks it parallel-eligible.
- Parallel work uses its own branch and merges only after its exit gate passes.

---

## 7. State After Context Loss

`docs/status/program-state.json` is authoritative. On any new session:

1. read it;
2. verify the recorded completed plans against Git history and `PROGRAM_STATUS.md` evidence;
3. resume the first incomplete plan.

Do not trust memory or conversation history over the ledger.

---

## 8. Exit Gate (per plan, recurring)

The active plan's exit gate (defined inside that plan's document) must be verified and its phase-gate report appended to `docs/status/PROGRAM_STATUS.md` §4 before the next plan starts. Only `PASS` advances.
