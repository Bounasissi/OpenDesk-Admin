# PRODUCT_SPEC — OpenDesk

**Version:** 1.0 (program baseline)
**Owner:** OpenDesk program
**Authority:** Decision-precedence level 2 in `AGENTS.md` §2.1.

---

## 1. What OpenDesk Is

OpenDesk is an **open-source, API-first, agent-ready macOS fleet administration application**. It covers the practical administrative outcomes of Apple Remote Desktop (discover, observe, control, copy, install, command, power, inventory, schedule, report) using **independent implementation, public protocols, public documentation, and clean-room behavioral analysis** — it does not copy Apple's implementation, binaries, assets, or private protocols.

---

## 2. Primary User

A **macOS fleet administrator / IT operations person** who:

- manages a handful to a few hundred Macs;
- currently uses Apple Remote Desktop, VNC, and ad-hoc SSH;
- needs discover → connect → control → administer → group → schedule → inventory → automate → secure → ship;
- is technical enough to run a CLI and read JSON, but should never need it to do the job.

Secondary users: automation (agents, scripts, Shortcuts) consuming the CLI/local API.

---

## 3. Jobs To Be Done

| # | Job | Product surface |
|---:|---|---|
| 1 | Find and identify the Macs I manage | Discovery + registry (Plan 04) |
| 2 | See and control a remote Mac | RFB/observe/control (Plan 06), multi-observe (Plan 10) |
| 3 | Push/pull files and install packages | SSH operations (Plan 07) |
| 4 | Run commands and manage power | RemoteCommandService (Plan 07) |
| 5 | Schedule/recur/retry operations across groups | Task engine (Plan 08) |
| 6 | Know my fleet's hardware/software state | Inventory + reports + drift (Plan 09) |
| 7 | Manage Macs without SSH/ARD exposure | Endpoint agent (Plan 11) |
| 8 | Automate everything from scripts/Shortcuts | CLI/API/App Intents (Plan 12) |
| 9 | Deploy to new machines with minimal effort | MDM/provisioning (Plan 13) |
| 10 | Trust that all of this is auditable and secure | Security foundation + hardening (Plans 05/16) |

---

## 4. Lifecycle Mapping (v1)

```text
Discover → Connect → Control → Administer → Group → Schedule → Inventory → Automate → Secure → Ship
```

Every feature supports one or more lifecycle stages; features that do not map to a stage are out of scope for v1 (see `V1_SCOPE.md`).

---

## 5. Core Capability Commitments (v1)

Summarized from `docs/program/PROGRAM_CHARTER.md` §3 — the full PASS list there is the binding contract:

- **Fleet basics:** discovery, manual add, persistent registry, static + smart groups, capability status.
- **Remote assistance:** observe, control, keyboard/mouse, clipboard, scaling, reconnect, multi-observe.
- **Administration:** commands, files, packages, wake/restart/shutdown/logout.
- **Tasks:** durable history, per-target results, cancellation, retry, schedule, offline/reconnect, templates.
- **Inventory:** hardware/OS/storage/network/apps/users/management status, exports, historical snapshots.
- **Agent:** secure enrollment, version negotiation, daemon/agent lifecycle, updates, no-SSH management.
- **Automation:** CLI with `--json`, local Unix-socket API, App Intents.
- **Security:** Keychain-only secrets, host identity verification, audit trail, signed updates, SBOM.
- **Distribution:** Developer ID signed + Hardened Runtime + notarized + stapled + public download + signed update feed.

---

## 6. Non-Goals (v1)

See `docs/product/V1_SCOPE.md` §3 (out-of-scope list) and `docs/program/PROGRAM_CHARTER.md` §6 (scope discipline). OpenDesk v1 is not: an ARD pixel clone, a cloud product, a mobile/Windows/Linux/browser console, a marketplace, or an AI remediation engine.

---

## 7. Distribution & Update Policy

- v1 default: **Developer ID + notarization + direct distribution**; Mac App Store review is not a critical-path dependency.
- Updates: **Sparkle 2** (HTTPS, Ed25519 signatures, monotonic versions, rollback path) unless an equivalent mechanism already exists.
- Apple requires Developer ID signing, Hardened Runtime, secure timestamps, and notarization for Developer ID-distributed software.

---

## 8. Success Criteria

OpenDesk v1.0 is successful when:

1. `docs/program/PROGRAM_CHARTER.md` §3 Product-Wide Definition of Done shows all `PASS`;
2. a person who has never seen the repository can download, install, and use it (Plan 22 gate);
3. every administrative action leaves a redacted audit trail (Plan 05/16);
4. release 1.0.0 is publicly tagged, downloadable, and updateable (Plan 20/22).

---

## 9. Change Control

Changes to this spec require an ADR (`docs/adr/`) and, if scope-altering, an update to `V1_SCOPE.md` in the same change. Agents resolve ambiguity via `AGENTS.md` §2.1 precedence; this document wins over architecture docs and conventions (but loses to existing verified behavior/tests).
