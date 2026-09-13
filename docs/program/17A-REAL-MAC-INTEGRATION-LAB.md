# Plan 17A — Real-Mac Integration Lab

> Binding instruction document. Executes within Plan 17's window (compatibility/reliability/performance).
> Source requirement: Addendum §24.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 17A
- **Prerequisites:** 06, 07 (protocol + transport capabilities)
- **Blocks:** 17 exit gate (real-host column), 21 RC acceptance

---

## 1. Rule

Loopback RFB tests are excellent and permanent — they do **not** replace an actual supported-Mac integration matrix. The lab gate is explicit and never silently deferred.

## 2. Required Verification Matrix

When a second Mac (or controlled fleet) is available, verify against real hosts:

```text
real macOS Remote Management activation
real Screen Sharing authentication (incl. RFB 003.889 banner host)
real SSH (key + password + host-key TOFU policy)
real file transfer (push/pull, recursive dirs, conflict paths)
real package install (signed + unsigned pkg, cleanup)
real restart / wake where safe
sleep / wake reconnect
DHCP / IP change identity reconciliation (Plan 04 A1.2)
multi-display enumeration and per-display observe
permission flows (Screen Recording, Accessibility, notifications)
agent install / upgrade (Plan 11)
```

## 3. No Second Mac Available

Keep the gate explicit while completing every automatable prerequisite:

- All loopback/virtual harnesses green (canonical suite).
- Fixture-driven real-host test scripts written and dry-run against a mock host.
- Matrix table in this plan marked `GATED` per row with the exact remaining human action.
- Gate recorded in `docs/status/PROGRAM_STATUS.md` §2 External Gates.

## 4. Test Lane Design

```text
CI: loopback + synthetic lanes only (no real Macs in CI)
Lab lane: operator-run script suite (scripts/) against provisioned Macs
Evidence: per-row result + logs + screenshots stored under docs/status/evidence/ (no secrets)
```

## 5. Exit Gate

- [ ] Matrix defined with per-row: precondition, procedure, expected result, evidence slot.
- [ ] Automatable prerequisites all green on canonical branch.
- [ ] Either real-host pass recorded per row, or row explicitly gated with the remaining action.
- [ ] 100-cycle connect/disconnect soak + sleep/wake reconnect executed on real hosts when available.
- [ ] Results cross-referenced from `docs/status/CAPABILITY_AUDIT.md`.
