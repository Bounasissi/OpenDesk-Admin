# ADR-0006 — Project License: MIT

**Status:** ACCEPTED (pending owner confirmation as external gate — see `docs/program/16A-LICENSE-DEPENDENCY-RECONCILIATION.md`)
**Date:** 2026-09-13
**Deciders:** OpenDesk program (agent ruling under `AGENTS.md` §2)
**Plan(s) affected:** 01, 06A, 16A, 19, 20

## Context

The three September 13 development histories carry conflicting license claims: `initial-091396` (canonical code base) is MIT; `OG-Output-Plan-0913` (scaffold, unmerged) is GPL-3.0-or-later. `AGENTS.md` §4 of Plan 01 requires the license to be chosen now. There may be exactly one authoritative licensing story.

## Decision

Repository license: **MIT**, matching the canonical implementation history.

## Ruling Block

```text
RULING:
Decision: MIT as the single repository and distribution license.
Evidence: canonical Package.swift has zero external dependencies (no LibVNCClient linkage — 06A default ruling); canonical LICENSE is MIT; scaffold GPL sources are excluded from the canonical tree (REPOSITORY_LINEAGE.md §2).
Reason: zero GPL obligations if nothing GPL is linked or distributed; same-author provenance means scaffold-derived code may be relicensed by the owner, pending explicit confirmation.
Alternative rejected: GPL-3.0 (would force relicensing of the larger canonical MIT base and restrict downstream users without offsetting benefit); dual licensing (ambiguous, violates single-story rule).
Cost if wrong: relicensing sweep later; bounded because the canonical tree is already MIT.
Reversible: yes (owner confirmation recorded in 16A).
```

## Consequences

- `THIRD_PARTY_NOTICES` records Apple-provided `libsqlite3` usage when artifacts ship (Plan 20).
- GPL scaffold sources remain reference-only until the owner confirms relicensing (16A external gate).
- `scripts/license-check.sh` enforces the single-story rule in `make verify` and CI.

## Reconsideration Triggers

- Owner rules GPL-3.0-or-later instead (requires full-tree sweep + 16A update).
- A GPL dependency becomes technically necessary (ADR-0003 §3 process-boundary evaluation).
