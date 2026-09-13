# Plan 07 — SSH, Commands, Files, Packages and Power

> Binding instruction document. Read `/AGENTS.md` and `docs/architecture/TRANSPORT_ARCHITECTURE.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 07
- **Prerequisites:** 03, 05
- **Blocks:** 08 (task engine wraps these operations), 09

---

## 1. Goal

Deliver the primary non-screen administrative operations.

---

## 2. Remote Execution Abstraction

Create `RemoteCommandService` with:

```text
command
arguments
environment
working directory
timeout
stdout
stderr
exit code
cancellation
```

Avoid unstructured shell concatenation.

---

## 3. SSH

Prefer an implementation with:

```text
known-host verification
key auth
password auth where needed
timeouts
cancellation
connection reuse
SFTP
```

Never disable host-key validation globally. Host-key policy comes from Plan 05.

---

## 4. File Operations

Implement:

```text
push file
pull file
push directory
pull directory
overwrite policy
rename policy
progress
checksum
resume where transport supports it
preserve timestamps
safe cleanup
```

---

## 5. Package Installation

Typed workflow:

```text
validate package
→ calculate checksum
→ copy to staging
→ verify remote checksum
→ installer -pkg ... -target /
→ collect status
→ remove staging artifact
→ optional reboot task
```

Do not execute user-controlled paths through naïve shell interpolation.

---

## 6. Power Operations

Typed tasks:

```text
wake
sleep
restart
shutdown
logout
```

Wake uses WoL (Wake-on-LAN) where supported.

---

## 7. Agent Sequence

1. Implement SSH transport (host-key policy wiring, auth, timeouts, cancellation, connection reuse) behind a port interface.
2. Implement `RemoteCommandService` on top with structured result type.
3. Implement file operations (SFTP push/pull, policy checks, progress, checksums).
4. Implement package install workflow as a typed pipeline with per-step status.
5. Implement power task adapters (`shutdown`, `restart`, `sleep`, `logout` via typed remote commands; WoL sender for wake).
6. Expose all as task types for Plan 08 (do not wire task engine yet).

---

## 8. Tests Required

- Command service unit tests (argument construction — no shell string building).
- File operation tests with local SFTP fixture (loopback SSH server where feasible).
- Checksum verification tests; corrupted-artifact rejection tests.
- Package workflow state tests.
- Power adapter tests (fake command executor).
- Injection tests: hostile filenames/paths must fail validation, never execute.

---

## 9. Exit Gate

One operation can target one Mac or a group while returning independent, structured per-device results.

---

## 10. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `08-TASK-ENGINE-SCHEDULER`).

---

## Amendment A1 — Three-Conversation Addendum (2026-09-13, Addendum §12, §13)

### A1.1 SSH tunneling is a general remote-connectivity policy (extends §3)

The conversation-derived `ssh -N -T -L localPort:localhost:5900` tunnel is retained. Generalize it with:

```text
tunnel lifecycle management (start/stop/status)
reconnect with backoff
process cleanup on app exit and crash
port collision handling
host-key validation (Plan 05 policy)
identity selection per device
timeouts (connect, idle, negotiation)
diagnostics (state, last error, endpoint)
```

Post-v1 connectivity objective: Tailscale-native workflows. **Do not build custom cloud relay infrastructure before it is justified** (Charter §6 scope discipline).

### A1.2 File distribution full contract (extends §4/§5)

Conversation implementation covers rsync/scp push/pull, installer -pkg, plist staging, defaults import, byhost domains — retain all. The full v1 contract additionally requires:

```text
push and pull
recursive directories
overwrite policy (explicit choice, not accidental)
rename-on-conflict option
timestamps preserved where supported
permissions preserved where supported
checksum verification (SHA-256; reference scaffold Transfers.swift)
progress reporting
cancellation
partial-failure reporting per item
resume where supported
safe staging cleanup (no orphan temp files)
parallel transfer limits (per-host and fleet)
drag/drop GUI path
```

Package installation must verify: local package integrity, remote checksum, installer result, staging cleanup, optional restart, per-device outcome recorded in the task result.
