# OpenDesk-Admin

Open-source reimplementation of the capabilities of Apple Remote Desktop (ARD) for macOS — remote observation/control, task execution, inventory reporting, and software distribution across a fleet of Macs — without the $79.99 license fee.

## Status

MVP in active development. See `docs/` for the full decomposition and architecture.

## What it does (MVP scope)

| ARD Capability | OpenDesk-Admin Module | Status |
|---|---|---|
| Screen observation/control (VNC) | `OpenDeskCore/Protocol` (RFB client) | Implemented (protocol core) |
| Send UNIX commands to clients | `OpenDeskCore/Tasks` | Implemented |
| Copy items to clients | `OpenDeskCore/Distribution` | Implemented (scp/rsync-backed) |
| Install packages on clients | `OpenDeskCore/Distribution` | Implemented (installer-backed) |
| Hardware/software inventory reports | `OpenDeskCore/Inventory` | Implemented |
| Client roster / computer groups | `OpenDeskCore/Transport` (HostRegistry) | Implemented |
| GUI dashboard | macOS app (SwiftUI) | Planned |

## Quick start

```bash
swift build
swift test

# Run the CLI
swift run opendesk --help

# Collect inventory from the local machine
swift run opendesk inventory --local

# Run a UNIX task on a registered host
swift run opendesk task run --host mymac.local --command "sw_vers"
```

## Documentation

- `docs/DECOMPOSITION.md` — full feature decomposition of Apple Remote Desktop
- `docs/ARCHITECTURE.md` — system design, modules, data flow
- `docs/LEGAL.md` — clean-room engineering policy and licensing constraints
- `docs/ROADMAP.md` — phased delivery plan

## License

MIT. See `LICENSE`. This project contains no Apple source code, binaries, or decompiled material.
