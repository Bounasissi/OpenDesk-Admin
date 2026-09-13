# OpenDesk Admin

Open-source, API-first, agent-ready macOS fleet administration — a clean-room replacement for Apple Remote Desktop (ARD).

## Thesis

ARD ≈ VNC/RFB viewer + SSH remote execution + file transfer + package installer + inventory collector + SQLite + task queue + scheduler + device groups + report viewer + RBAC + macOS-native UI.

The hard part is not remote desktop. The hard part is **orchestration and reliability across many machines**. OpenDesk Admin reproduces ARD's observable administrative outcomes without any Apple proprietary code, then exceeds it with CLI/API/automation-first design.

## Lifecycle

```
Build → Test → Deploy → Monitor → Improve
```

Every management operation in OpenDesk is a **Task**:

```
Target Set + Action + Parameters + Execution Strategy + Schedule + Result
```

## Repository Layout

```
opendesk/
├── apps/                  # admin-macos (SwiftUI), agent-macos, cli
├── packages/              # core, device-registry, discovery, rfb, ssh,
│                          # transfers, packages, inventory, tasks,
│                          # scheduler, reporting, security, protocol
├── reverse-engineering/   # clean-room behavior specs, protocol observations,
│                          # state machines, compatibility matrix
├── fixtures/              # test data
├── docs/                  # architecture, protocols, security, compatibility
├── scripts/               # analysis harness + dev tooling
└── tests/                 # integration tests
```

## Quick Start (development)

```bash
swift build                      # builds all packages + CLI
swift test                       # runs unit tests
swift run opendesk --help        # CLI entry point
```

## Implemented (v0.1)

| Capability | Status | Module |
|---|---|---|
| SQLite persistence (21-table schema, WAL, FK) | **implemented** | core/SQLiteKit + DeviceRegistry |
| Device discovery (Bonjour + CIDR scan, dedupe) | **implemented** | core/Discovery |
| SSH command/script execution | **implemented** | core/SSHTransport |
| Universal task engine (queue, state machine, per-target results, audit) | **implemented** | core/TaskEngine |
| File push/pull (SFTP, SHA-256 verified) | **implemented** | core/Transfers |
| Package install pipeline (checksum → stage → installer → cleanup) | **implemented** | core/Transfers |
| Inventory collectors (hw/os/net/storage/apps/users) | **implemented** | core/Inventory |
| RFB/VNC client (RFC 6143: handshake, VNC auth DES, raw/copyrect/hextile, input events) | **implemented** | core/RFBClient |
| Scheduler (RRULE subset, one-shot, on-reconnect) | **implemented** | core/Scheduler |
| Smart Groups predicate engine (AND/OR, version compare) | **implemented** | core/Scheduler |
| Power management (Wake-on-LAN, sleep/restart/shutdown/logout) | **implemented** | core/Scheduler |
| CLI: discover/devices/exec/copy/install/inventory/groups/power/schedule/tasks/audit | **implemented** | apps/cli |
| RFB live session UI + multi-observe grid | next | apps/admin-macos |
| Task Server worker (offline execution) | next | core |
| SwiftUI admin console | next | apps/admin-macos |
| OpenDesk agent (V2) | later | apps/agent-macos |

## CLI Usage

```bash
opendesk discover-command --cidr 192.168.1.0/24 [--no-bonjour]
opendesk devices-command [--format json]
opendesk exec-command "softwareupdate -l" --devices <id-or-hostname,...>
opendesk copy-command ./file.pkg /tmp/ --devices <id-or-hostname,...>
opendesk install-command ./file.pkg --devices <id-or-hostname,...> [--restart-policy restart]
opendesk inventory-command --devices <id-or-hostname,...> [--json]
opendesk tasks-command
opendesk audit-command
```

Default database: `~/Library/Application Support/OpenDeskAdmin/opendesk.db` (override with `--db`).

## Key Documents

| Document | Purpose |
|---|---|
| [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md) | System architecture and module boundaries |
| [docs/protocols/PROTOCOL-SPEC.md](docs/protocols/PROTOCOL-SPEC.md) | Network/protocol decomposition (RFB, SSH, 3283, 5900) |
| [docs/SRS-ROADMAP.md](docs/SRS-ROADMAP.md) | Software Requirements Specification + development roadmap |
| [docs/CLEAN-ROOM-POLICY.md](docs/CLEAN-ROOM-POLICY.md) | Legal/clean-room engineering policy |
| [docs/architecture/DATA-MODEL.md](docs/architecture/DATA-MODEL.md) | SQLite schema and task object model |
| [docs/DEFINITION-OF-DONE.md](docs/DEFINITION-OF-DONE.md) | Project-level Definition of Done |

## Technical Baseline

| Concern | Choice |
|---|---|
| Language/UI | Swift + SwiftUI + selective AppKit |
| Remote display | RFB/VNC (LibVNCClient initially, GPL-2.0-or-later) |
| Administration | SSH (commands, files, packages) |
| Storage | SQLite |
| Secrets | macOS Keychain (SQLite stores references only) |
| Background execution | launchd |
| Discovery | Bonjour + Network.framework + CIDR scan |
| Package deployment | SFTP + `installer` |
| Automation | CLI + App Intents + JSON task API |
| License | GPL-3.0-or-later |

## Client Strategy

- **V1** — Use Apple's built-in Remote Management (ARDAgent) + SSH. No custom agent required.
- **V2** — Lightweight OpenDesk agent.
- **V3** — Agent independent of ARDAgent.
- **V4** — Fully open-source remote-management stack.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
