# Plan 12 — CLI, Local API and Apple Shortcuts

> Binding instruction document. Read `/AGENTS.md` first. Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 12
- **Prerequisites:** 03–11
- **Blocks:** 15 (automation surface), 21 (RC suite includes CLI), 22 (agent-ready launch)

---

## 1. Goal

Make OpenDesk agent-usable rather than GUI-only.

---

## 2. CLI

Provide structured commands:

```bash
opendesk discover
opendesk devices
opendesk groups
opendesk observe <device>
opendesk exec ...
opendesk copy ...
opendesk install ...
opendesk restart ...
opendesk inventory ...
opendesk tasks ...
```

Every appropriate command supports `--json`. Human formatting is never the only interface. Document stable exit codes.

---

## 3. Local API

Expose a versioned local API over a Unix-domain socket by default.

**Do not unnecessarily expose an unauthenticated TCP API.**

Example task request:

```json
{
  "version": 1,
  "action": "inventory.collect",
  "target": {
    "group": "lab"
  }
}
```

---

## 4. App Intents

Expose frequent actions:

```text
Run task
Wake Macs
Restart Macs
Collect inventory
Connect to device
Open device
```

---

## 5. Agent Sequence

1. Implement CLI target sharing the same application services layer as the GUI (no logic duplication).
2. Implement `--json` output contract + documented stable exit codes.
3. Implement Unix-domain-socket local API (versioned, authenticated local socket; schema-versioned requests/responses).
4. Implement App Intents for the six actions.
5. Add docs: CLI reference + API reference under `docs/` and `README` pointer.

---

## 6. Tests Required

- CLI integration tests for every command (success + failure + `--json` shape + exit codes).
- Local API contract tests (request/response schema, auth rejection, version negotiation).
- App Intents unit tests where automatable.

---

## 7. Exit Gate

All core v1 management functions can be invoked without clicking the GUI.

---

## 8. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `13-MDM-PROVISIONING`).
