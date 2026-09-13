# Plan 15 — UX, Accessibility and Onboarding

> Binding instruction document. Read `/AGENTS.md` and `docs/product/PRODUCT_SPEC.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 15
- **Prerequisites:** 04–13
- **Blocks:** 16–19 (shippable UX), 21 (RC acceptance suite)

---

## 1. Goal

Make the feature set understandable without turning OpenDesk into a pixel clone of ARD.

---

## 2. Navigation

Primary surfaces:

```text
Devices
Groups
Tasks
Sessions
Reports
Packages
Activity
Settings
```

---

## 3. Device Detail

One device exposes:

```text
identity
status
capabilities
remote session
inventory
tasks
files
software
audit activity
agent state
```

---

## 4. Task Composer

Standard pattern:

```text
Choose action → choose target → configure → review impact → run/schedule
```

---

## 5. Onboarding

Detect rather than merely document:

```text
missing Screen Recording
missing Accessibility
missing local-network permission where applicable
agent unavailable
SSH unavailable
Remote Management unavailable
```

Provide corrective instructions. **Never claim permission was granted until the OS reports it.**

---

## 6. Accessibility

Verify:

```text
VoiceOver
keyboard-only operation
focus order
Dynamic Type where applicable
contrast
reduced motion
descriptive controls
```

---

## 7. Agent Sequence

1. Implement navigation shell for the eight surfaces.
2. Implement device detail page (aggregate data from Plans 04/09/10).
3. Implement task composer using the five-step pattern (review impact shows resolved targets).
4. Implement permission/availability detection engine + corrective guidance UI (deep links per Plan 13).
5. Accessibility pass: labels, focus order, keyboard-only paths, contrast, reduced motion.
6. Empty/error states for every surface (no blank screens).

---

## 8. Tests Required

- Onboarding detection tests (each missing-permission state detected and rendered).
- Accessibility automated checks (labels present, focus order deterministic) + scripted manual evidence (screenshots/OSlog).
- Composer unit tests (target resolution preview matches dispatch snapshot).

---

## 9. Exit Gate

A new user can install OpenDesk, add one Mac, connect, execute a task, and understand any missing permission from in-app guidance.

---

## 10. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `16-SECURITY-HARDENING`).
