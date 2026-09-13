# OpenDesk-Admin

Open-source reimplementation of the capabilities of Apple Remote Desktop (ARD) for macOS — remote observation/control, task execution, inventory reporting, and software distribution across a fleet of Macs — without the $79.99 license fee.

## Status

MVP in active development. See `docs/` for the full decomposition and architecture.

## What it does (current scope)

| ARD Capability | OpenDesk-Admin Module | Status |
|---|---|---|
| Screen observation/control (VNC) | `OpenDeskCore/Protocol` (RFB client) | Handshake + auth live-verified; Raw framebuffer decoding implemented |
| Send UNIX commands to clients | `OpenDeskCore/Tasks` | Implemented (bounded-concurrency fleet execution) |
| Copy items to clients | `OpenDeskCore/Distribution` | Implemented (scp/rsync-backed) |
| Install packages on clients | `OpenDeskCore/Distribution` | Implemented (installer-backed) |
| Hardware/software inventory reports | `OpenDeskCore/Inventory` | Implemented + CSV/JSON export |
| Client roster / computer groups | `OpenDeskCore/Transport` (HostRegistry) | Implemented (persistent, versioned) |
| Saved tasks | `OpenDeskCore/Tasks` (TaskStore) | Implemented (versioned on update) |
| Recurring/scheduled tasks | `OpenDeskCore/Tasks` (TaskScheduler) | Implemented (interval + daily triggers, foreground daemon) |
| Copy app settings (plist payloads) | `OpenDeskCore/Distribution` | Implemented (`defaults import`, byhost supported) |
| Tiled multi-screen observation | `OpenDeskGUI` (TiledObservationView) | Implemented (grid 1–4 columns) |
| Wake-on-LAN | `OpenDeskCore/Tasks` (WakeOnLAN) | Implemented (RFC 102-byte magic packet) |
| Bonjour client discovery | `OpenDeskCore/Transport` (FleetDiscovery) | Implemented (`_rfb._tcp` browse) |
| GUI dashboard | `OpenDeskGUI` (SwiftUI) | Working: roster, add host, task runner, inventory, screen connect |
| CLI | `OpenDeskCLI` | All commands verified |

## Quick start

```bash
swift build
swift test

# CLI
swift run opendesk --help
swift run opendesk inventory --local          # local hardware/software report
swift run opendesk inventory --local --export-csv report.csv
swift run opendesk hosts add mymac.local admin --groups lab-1
swift run opendesk task run --host mymac.local --command "sw_vers"
swift run opendesk tasks add uptime --command "uptime"   # saved task
swift run opendesk wake --host mymac.local               # needs --mac on the host

# GUI dashboard
swift run opendesk-gui
```

## Packaging

```bash
./scripts/build-app.sh release   # → .build/OpenDesk Admin.app (ad-hoc signed)
```

For boot-persistent scheduled tasks, install the launchd wrapper:
`scripts/com.opendesk.schedule-daemon.plist` (see comments inside).

## Documentation

- `docs/DECOMPOSITION.md` — full feature decomposition of Apple Remote Desktop
- `docs/ARCHITECTURE.md` — system design, modules, data flow
- `docs/LEGAL.md` — clean-room engineering policy and licensing constraints
- `docs/ROADMAP.md` — phased delivery plan

## License

MIT. See `LICENSE`. This project contains no Apple source code, binaries, or decompiled material.
