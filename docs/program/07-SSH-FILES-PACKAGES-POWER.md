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
