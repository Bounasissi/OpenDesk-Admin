# ADR-0003 — Dependency Policy: Native-First, Sparkle 2 Default, LibVNCClient Licensing Gate

**Status:** ACCEPTED
**Date:** 2026-09-13
**Deciders:** OpenDesk program
**Plan(s) affected:** 01, 06, 14, 19, 20, 23

## Context

The program needs remote-control transport and auto-update capability. Native Apple frameworks cover most needs; third parties are candidates for RFB and updates.

## Decision

1. **Native-first:** prefer Apple frameworks; do not add a dependency if less than roughly one day's implementation avoids it and the native implementation is maintainable.
2. **Updates:** default to Sparkle 2 (SPM integration, HTTPS, Ed25519 signatures, notarization support) unless the repository already has an equivalent mechanism.
3. **RFB:** use LibVNCClient only if its licensing is compatible with the project's chosen license. On conflict: (a) evaluate a license-compatible implementation; (b) otherwise place the GPL component behind a separately distributed process boundary; record the licensing architecture; flag legal review as a release gate if uncertainty remains.

## Ruling Block

```text
RULING:
Decision: Native-first + Sparkle 2 default + gated LibVNCClient use.
Evidence: AGENTS.md engineering defaults; Sparkle 2 docs; LibVNCClient licensing.
Reason: Minimizes supply-chain and licensing risk; uses proven components where a native replacement is large.
Alternative rejected: Vendoring GPL code into the app binary; writing a custom updater from scratch.
Cost if wrong: Rework of transport or updater; bounded by plan gates.
Reversible: yes (per-plan substitution with ADR).
```

## Consequences

Plan 01 selects the project license with Plan 06 in mind. Plan 06 performs the licensing analysis before shipping any binary linkage. Plan 19 generates license/notice inventory.

## Reconsideration Triggers

- License conflict resolution options change.
- Sparkle 2 ceases to meet notarization/security requirements.
