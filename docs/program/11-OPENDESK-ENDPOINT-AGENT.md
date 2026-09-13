# Plan 11 — OpenDesk Endpoint Agent

> Binding instruction document. Read `/AGENTS.md`, `docs/architecture/SECURITY_ARCHITECTURE.md`, and `docs/architecture/TRANSPORT_ARCHITECTURE.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 11
- **Prerequisites:** 03–10
- **Blocks:** 12–13, 14 (agent provides capture surface), 15 (agent-state UI), 21 (RC suite)

---

## 1. Goal

Remove SSH/ARD limitations and enable richer management.

---

## 2. Process Model

Use:

```text
LaunchDaemon
+ per-user LaunchAgent where user-session access is required
```

Use `SMAppService` where supported (macOS 13+).

---

## 3. Responsibilities Split (least privilege)

**Daemon** — only privileged/system operations, e.g.:

```text
inventory
package operations
power tasks
durable jobs
system status
secure file operations
```

**User agent** — user-session operations, e.g.:

```text
screen capture
user notification
clipboard
user-session interaction
```

---

## 4. IPC

Use authenticated XPC or another native authenticated local IPC mechanism.

**The daemon must not expose arbitrary privileged shell execution to untrusted local clients.**

---

## 5. Enrollment

Provide:

```text
interactive local enrollment
one-time enrollment token
MDM enrollment path
```

Generate per-device identity after enrollment. Enrollment secrets live in Keychain only.

---

## 6. Remote Protocol

Version it from day one:

```text
protocolVersion
capabilities[]
agentVersion
```

---

## 7. Transport Security

Use standard TLS primitives. Do not invent cryptography. Implement mutual identity when practical.

---

## 8. Update Strategy

Agent and admin compatibility must tolerate at least one version of skew.

---

## 9. Agent Sequence

1. Implement daemon skeleton (LaunchDaemon, lifecycle, health endpoint, version/capabilities).
2. Implement user-agent skeleton (LaunchAgent, session-bound operations).
3. Implement authenticated local IPC with strict operation allowlist + parameter validation.
4. Implement enrollment flows (local interactive, token, MDM path).
5. Implement secure remote channel (TLS, mutual identity, protocolVersion/capabilities handshake).
6. Implement remote operation handlers for v1 management operations (inventory, package, power, status, secure file ops).
7. Implement agent-side durable job queue.
8. Define compatibility-skew policy (min admin↔agent version pairs) and encode in handshake.

---

## 10. Tests Required

- IPC authorization tests (untrusted client rejected; allowlist enforced).
- Handshake/version-skew tests (all supported admin/agent version pairs).
- Enrollment flow tests (local, token).
- Daemon/agent lifecycle tests (launch, restart, permission denial).
- Remote-operation tests with fake admin client.

---

## 11. Exit Gate

A managed endpoint can perform the v1 management operations without requiring Remote Login/SSH.

---

## 12. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `12-CLI-API-SHORTCUTS`).
