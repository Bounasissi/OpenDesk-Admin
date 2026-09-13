# Plan 17 — Compatibility, Reliability and Performance

> Binding instruction document. Read `/AGENTS.md` and `docs/product/COMPATIBILITY_MATRIX.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 17
- **Prerequisites:** 04–16
- **Blocks:** 18, 19–22 (RC requires this gate)

---

## 1. Goal

Prove OpenDesk behaves like infrastructure rather than a prototype.

---

## 2. Compatibility Matrix

Admin Mac:

```text
minimum supported macOS
current macOS
current macOS beta only as non-blocking informational lane
Intel where still supported by chosen target
Apple Silicon
```

Remote endpoints:

```text
minimum supported remote configuration
current macOS
Apple Silicon
Intel where applicable
ordinary VNC server
OpenDesk Agent
```

---

## 3. Network Conditions

Test:

```text
LAN
high latency
packet loss
temporary disconnect
IP change
sleep/wake
VPN/Tailscale-like network path
offline/reconnect
```

---

## 4. Soaks (required)

```text
8-hour admin-app idle soak
8-hour connected remote session soak
100 connection cycles
100 task dispatch cycles
repeated agent restart
repeated app restart
```

---

## 5. Resource Leak Monitoring

Monitor:

```text
memory
threads
file descriptors
sockets
processes
temporary files
database growth
```

---

## 6. Failure Injection

Inject:

```text
disk full
permission denied
invalid credentials
server closes socket
task timeout
database busy
corrupt response
partial transfer
package failure
agent upgrade during task
```

---

## 7. Performance Budgets

Establish measured budgets for:

```text
launch time
device-list rendering
discovery throughput
remote-session latency
memory/session
multi-observe CPU
inventory query latency
database growth
```

If an initial budget proves physically unrealistic, agents may revise it only with benchmark evidence and an ADR.

---

## 8. Agent Sequence

1. Build automation harnesses for soaks/injection (scripts under `scripts/`, results committed as evidence).
2. Execute matrix runs across available hardware/OS combos; record results.
3. Execute network condition tests (local throttling/loss simulation).
4. Measure and record performance budgets; ADR for any revision.
5. Fix all P0/P1 defects surfaced; rerun affected suites.

---

## 9. Tests Required

All soaks, injections, and matrix runs listed above with committed evidence (logs, metrics, screenshots).

---

## 10. Exit Gate

No unresolved P0/P1 reliability defect and all required soak tests pass.

---

## 11. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `18-OBSERVABILITY-DIAGNOSTICS`).
