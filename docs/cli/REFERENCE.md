# CLI Reference — OpenDesk (Plan 12 §2)

> Stable surface contract. Human formatting is never the only interface:
> every appropriate command supports `--json`. This document is the exit-code
> and schema authority.

## Exit Codes (stable)

| Code | Meaning |
|---:|---|
| 0 | Success |
| 1 | Runtime failure (command-specific; includes usage errors inside subcommands) |
| 2 | Invalid arguments (bad CIDR, missing required option) |
| 3 | Infrastructure unavailable (database, registry) |

## Commands

| Command | `--json` | Notes |
|---|:---:|---|
| `hosts add <hostname> <username> [--groups g1,g2]` | — | manual target (Plan 04 §2.1) |
| `hosts list [--json]` | ✓ | roster from legacy JSON registry |
| `hosts remove <hostname>` | — | |
| `discover --cidr <block> [--ports p1,p2] [--limit n] [--json]` | ✓ | Bonjour + bounded CIDR scan; reconciles into the canonical registry |
| `devices [--json]` | ✓ | canonical device registry (DeviceID, lifecycle, endpoints) |
| `serve --socket <path>` | n/a | versioned local JSON API over a Unix-domain socket (Plan 12 §3); blocks |
| `task run --host h --command "cmd"` / `--groups g1,g2` | — | SSH fleet execution |
| `tasks add/list/remove` | — | saved (versioned) tasks |
| `schedule add/list/daemon/run-now/remove` | — | schedules (canonical DB storage) |
| `wake --host h` | — | Wake-on-LAN |
| `inventory --local / --host h [--export-csv path]` | — | RFC-4180 CSV / JSON export |
| `observe --host h [--port p] [--password pw]` | — | RFB screen session |
| `tunnel --host h [--screen-port p]` | — | SSH tunnel (keeps running) |
| `copy --host h --local p --remote p` | — | file transfer |
| `install --host h --pkg p` | — | package install pipeline |

## Local API (Plan 12 §3)

- Default transport: **Unix-domain socket** (`opendesk serve --socket <path>`).
- Socket permissions: `0600` (invoking user only). **No unauthenticated TCP control service.**
- Protocol: newline-delimited JSON. Every request carries `"version": 1`.

### Requests (v1)

```json
{"version": 1, "action": "devices.list"}
{"version": 1, "action": "inventory.collect"}
{"version": 1, "action": "tasks.submit", "type": "exec.command", "idempotencyKey": "...", "parameters": "..."}
{"version": 1, "action": "version"}
```

### Responses

```json
{"version": 1, "ok": true, "devices": [{"id": "...", "hostname": "...", "lifecycle": "online"}]}
{"version": 1, "ok": true, "taskID": "UUID"}
{"version": 1, "ok": false, "error": "unknown action"}
```

Errors: `"unsupported version"`, `"unknown action"`, `"malformed request"`, `"action failed"`.

## App Intents (Plan 12 §4)

The six required intents (Run Task, Wake Macs, Restart Macs, Collect Inventory, Connect to Device, Open Device) are specified for the GUI app target as native `AppIntent`s. **Status on the canonical branch: CLI + local API are implemented and tested; the App Intents surface is NOT yet implemented** — it lands with the Plan 15 GUI work and is tracked in the plan ledger. The CLI + local API cover the automation surface for non-GUI hosts meanwhile.
