# V1_SCOPE — OpenDesk v1.0 Scope Contract

**Authority:** Decision-precedence level 3 in `AGENTS.md` §2.1.
**Change control:** scope additions/removals require an ADR referencing the affected plan and lifecycle stage.

---

## 1. In Scope — v1.0

The v1 critical path: `Discover → Connect → Control → Administer → Group → Schedule → Inventory → Automate → Secure → Ship`.

### 1.1 Milestone feature baselines

| Milestone | Feature baseline | Tag |
|---|---|---|
| Alpha | device registry, remote control, commands, file transfer, package install, task engine, basic inventory | `0.x-alpha` |
| Beta | + endpoint agent, groups, scheduler, reports, CLI, onboarding, security hardening, diagnostics, auto-update | `0.9.0-beta.*` |
| RC | feature freeze; only defect/security/release fixes | `1.0.0-rc.*` |
| v1.0 | full Product-Wide DoD (`PROGRAM_CHARTER.md` §3) | `1.0.0` |

### 1.2 Plan ownership

Plans 01–23 in `docs/program/` define the work. Every v1 feature traces to at least one plan and one lifecycle stage.

---

## 2. Platform Floor

- **Admin app:** macOS 14+ (default; availability checks for newer APIs — no silent floor raise).
- **Remote endpoints:** supported macOS targets per `COMPATIBILITY_MATRIX.md` (current + minimum supported), Apple Silicon and Intel where applicable; ordinary VNC server and OpenDesk Agent as endpoint types.
- Current macOS beta tested only as a non-blocking informational lane.

---

## 3. Out of Scope — v1.0

The following are **not allowed to hold v1 hostage**:

```text
pixel matching Apple Remote Desktop
duplicating Apple's private Task Server wire protocol
duplicating every ARD report
supporting every historical macOS release
custom cloud infrastructure
accounts/billing
mobile apps
Windows administrator app
Linux administrator app
browser administrator app
plugin marketplace
AI remediation
full GitOps
Docker management
Homebrew fleet orchestration
advanced compliance engine
```

Record these as **post-v1 opportunities**. Mac App Store distribution is a separate track, not a v1 blocker. High-Performance Streaming (Plan 14) is post-parity-core: it must not delay v1 unless promoted into the v1 gate by ADR.

---

## 4. External Gates Acknowledged

Per `AGENTS.md` §2.2 and `PROGRAM_CHARTER.md` §7: Apple Developer membership/certificates/credentials/MFA, macOS consent prompts (Screen Recording, Accessibility, background items), MDM authority, DNS ownership, GitHub org permissions. Agents document and isolate these; they never circumvent them.

---

## 5. Release Blockers (bug policy)

```text
P0 — data/security/destructive issue
P1 — core feature unavailable or repeated crash
```

No open P0/P1 enters v1.0 (enforced at Plan 21 → Plan 22 handoff).
