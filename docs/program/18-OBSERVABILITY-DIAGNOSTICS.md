# Plan 18 — Observability and Diagnostics

> Binding instruction document. Read `/AGENTS.md` first. Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 18
- **Prerequisites:** 04–17
- **Blocks:** 19 (docs), 21 (diagnostic export in RC suite), 23 (post-launch ops)

---

## 1. Goal

Failures should generate enough evidence to debug them without reproducing them manually.

---

## 2. Logging

Use structured `OSLog`. Categories:

```text
app
discovery
rfb
ssh
agent
tasks
scheduler
inventory
database
security
update
release
```

Every cross-component operation carries a correlation ID.

---

## 3. Redaction

Prohibit logs containing:

```text
passwords
private keys
tokens
clipboard contents by default
remote file contents
package contents
```

---

## 4. Diagnostic Bundle

Implement one-click export containing:

```text
app version
OS version
architecture
sanitized logs
task history excerpt
agent version
capability state
permission state
network diagnostic summary
database schema version
```

**Never include Keychain secrets.**

---

## 5. Crash Reporting

Open-source/privacy-friendly default:

```text
local diagnostics always
remote crash/telemetry opt-in unless explicitly designed otherwise
```

---

## 6. Agent Sequence

1. Implement structured logging policy (categories, correlation IDs) and enforce via lint/code review conventions.
2. Implement redaction layer for all log sinks (shared redactor from Plan 05).
3. Implement diagnostic bundle builder + one-click export in-app and via CLI.
4. Implement local crash/diagnostic capture; document opt-in stance for any remote telemetry.
5. Verify: a failed session or task can be investigated from bundle + correlation ID (integration test or scripted evidence).

---

## 7. Tests Required

- Redaction tests per category.
- Diagnostic bundle completeness tests (each §4 item present; no secret present).
- Correlation-ID propagation tests across components.

---

## 8. Exit Gate

A failed session or task can be investigated from its diagnostic bundle and correlation ID.

---

## 9. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `19-OPEN-SOURCE-RELEASE-READINESS`).
