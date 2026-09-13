# ADR-0004 — Deployment Target: macOS 14+ with Availability Checks

**Status:** ACCEPTED
**Date:** 2026-09-13
**Deciders:** OpenDesk program
**Plan(s) affected:** 01, 17

## Context

v1 must support a practical fleet window. Raising the floor for all users to chase one API is costly; silently pinning an old floor to avoid it is also wrong.

## Decision

Default v1 admin-app deployment target: **macOS 14+**, unless existing repository architecture justifies another floor. Features requiring newer OS APIs use `@available` checks rather than silently raising the entire application's minimum OS.

## Ruling Block

```text
RULING:
Decision: macOS 14 floor; availability checks for newer APIs.
Evidence: Program requirement to support a useful fleet window; SMAppService/ScreenCaptureKit availability windows.
Reason: 14+ covers current fleets while allowing modern APIs without per-feature floor raises.
Alternative rejected: macOS 13 floor (older baseline maintenance); latest-only floor (shrinks support matrix).
Cost if wrong: Re-cutting the floor later; bounded by migration tests.
Reversible: yes.
```

## Consequences

Plan 17's compatibility matrix tests macOS 14 and current stable as blocking lanes; betas are informational only.

## Reconsideration Triggers

- Fleet evidence shows a materially older installed base is required.
- Apple drops a blocking capability from the floor version.
