# ADR-0002 — v1 Distribution: Developer ID + Notarization + Direct Distribution

**Status:** ACCEPTED
**Date:** 2026-09-13
**Deciders:** OpenDesk program
**Plan(s) affected:** 20, 21, 22

## Context

OpenDesk v1.0 must reach users as a trustworthy public download. Two routes exist: Mac App Store (requires review, sandboxing) and Developer ID direct distribution (requires signing, Hardened Runtime, secure timestamps, notarization).

## Decision

Use **Developer ID + notarization + direct distribution** as the v1 default. Mac App Store is a separate, later distribution track and is not a v1 blocker. Outside the App Store, sandboxing is recommended rather than mandatory.

## Ruling Block

```text
RULING:
Decision: Developer ID + notarization + direct distribution for v1.
Evidence: Apple requirements for Developer ID software; MAS review timing risk.
Reason: Fastest trustworthy path to public download; avoids MAS review on the critical path.
Alternative rejected: MAS-only launch (review dependency blocks zero-oversight timeline).
Cost if wrong: Re-later MAS work; acceptable, track is additive.
Reversible: yes (additive MAS track later).
```

## Consequences

Plan 20 builds the signing/notarization pipeline with an external credential gate if certificates are absent. Plans 21/22 verify Gatekeeper behavior on the published artifact.

## Reconsideration Triggers

- Apple policy change altering Developer ID requirements.
- MAS presence becomes commercially necessary pre-v1.
