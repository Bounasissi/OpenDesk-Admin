# ADR-0005 — Secrets Architecture: SQLite References + Keychain-Only Secrets

**Status:** ACCEPTED
**Date:** 2026-09-13
**Deciders:** OpenDesk program
**Plan(s) affected:** 03, 05, 11, 16, 18

## Context

OpenDesk stores VNC/ARD credentials, SSH passwords/keys, and agent enrollment secrets. Storing them in SQLite would make every DB backup/export a credential leak surface.

## Decision

Implement credentials as `SQLite → CredentialID (reference)` + `Keychain → secret`. Never store password, private key material, agent enrollment secret, or VNC credential in SQLite. Never log secrets. All log/audit sinks apply the redaction filter before persistence.

## Ruling Block

```text
RULING:
Decision: SQLite references + Keychain-only secrets + universal redaction.
Evidence: macOS security architecture (Keychain); Plan 05 exit gate; Plan 16 controls.
Reason: Strongest practical separation of identity data from secret material on macOS.
Alternative rejected: Encrypted-column storage in SQLite (key-management burden without OS integration).
Cost if wrong: Migration to a different secret store later; bounded.
Reversible: yes (store abstraction behind interface).
```

## Consequences

Plan 05 builds the Keychain store and redaction layer; Plan 11 applies the same rule to agent enrollment secrets; Plan 16 verifies by scan; Plan 18's diagnostic bundle never contains Keychain secrets.

## Reconsideration Triggers

- A platform change makes Keychain unsuitable for a required secret class.
