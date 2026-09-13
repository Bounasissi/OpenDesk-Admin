# ADR-0001 — Adopt Zero-Oversight Delivery Program + Instruction Hierarchy

**Status:** ACCEPTED
**Date:** 2026-09-13
**Deciders:** OpenDesk program (authored at first commit)
**Plan(s) affected:** 00–23

## Context

OpenDesk begins at a first commit with a nearly empty repository. Development must proceed from here to a signed, notarized, publicly downloadable v1.0 with no routine human oversight, across many coding-agent sessions with no shared conversational memory.

## Decision

Adopt the binding instruction hierarchy: root `AGENTS.md` (no-question policy, decision precedence, engineering defaults, git/TDD/review rules, completion ledger), `docs/program/00–23` per-plan documents, and `docs/program/PROGRAM_CHARTER.md` (Definition of Done, phase-gate protocol, handoff contract, milestone order, scope discipline, external gates). `docs/status/program-state.json` is authoritative after context loss.

## Ruling Block

```text
RULING:
Decision: Adopt instruction hierarchy + ledger-driven orchestration.
Evidence: Program requirements (zero oversight, e2e completion per plan).
Reason: Prevents per-session drift, re-deciding architecture, and partial implementations.
Alternative rejected: Ad-hoc task-by-task instructions; memory-based continuity.
Cost if wrong: Session drift and lost work.
Reversible: no (program-level constitution; superseding requires full replacement ADR).
```

## Consequences

Every agent session starts from `00-MASTER-ORCHESTRATOR.md` and the ledger. Plans are executed in milestone order; only PASS advances.

## Reconsideration Triggers

- External gates prove structurally incompatible with plan order.
- A material scope change invalidates the critical path.
