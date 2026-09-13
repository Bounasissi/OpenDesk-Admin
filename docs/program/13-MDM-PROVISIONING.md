# Plan 13 — MDM and Provisioning

> Binding instruction document. Read `/AGENTS.md` and `docs/architecture/SECURITY_ARCHITECTURE.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 13
- **Prerequisites:** 11, 12
- **Blocks:** 15 (onboarding), 21 (RC provisioning check)

---

## 1. Goal

Reduce endpoint setup to the lowest practical human effort.

---

## 2. Required Outputs

Configuration guidance and artifacts for:

```text
generic Apple MDM
Jamf
Kandji
Mosyle
Intune
```

where public MDM capabilities permit them.

---

## 3. Automate (where technically permitted)

```text
agent installation
background service enrollment
configuration
certificate deployment
network configuration
managed preferences
Remote Management activation
```

---

## 4. System-Consent Boundary

Do not attempt to bypass macOS privacy protections. Where macOS requires user or administrator consent, expose the exact missing permission and deep-link to the proper settings location where supported.

---

## 5. Enrollment Diagnostics

One command must report:

```text
agent installed
daemon active
user agent active
screen recording state
accessibility state
network reachability
certificate state
OpenDesk connectivity
```

---

## 6. Agent Sequence

1. Produce MDM payload/config artifacts (plist profiles per vendor where permitted) with documented keys.
2. Implement provisioning package/script path for agent install + service registration.
3. Implement diagnostics command (§5 list) as CLI + API action.
4. Implement in-app guided provisioning surface hooks for Plan 15 (deep links to Settings).
5. Document the full MDM workflow per vendor in `docs/runbooks/` (link from README).

---

## 7. Tests Required

- Diagnostics command tests (each state detectable/reported).
- Profile/schema validation tests for produced MDM artifacts.
- Provisioning dry-run tests (no destructive execution without explicit target).

---

## 8. Exit Gate

A managed Mac can be provisioned with an MDM-driven workflow requiring only OS-mandated consent.

---

## 9. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `15-UX-ACCESSIBILITY-ONBOARDING`; Plan 14 parallel-eligible).

---

## Amendment A1 — Three-Conversation Addendum (2026-09-13, Addendum §19)

The conversation-derived `scripts/setup-client.sh` (first-party macOS tooling) is retained as **developer/manual bootstrap only** — it is not the final provisioning story. §2's vendor list (generic Apple MDM, Jamf, Kandji, Mosyle, Intune) and §5's diagnostic fields are the production path. Do not bypass TCC/user consent (§4 stands). §3's automation applies only to what the platform legally permits.
