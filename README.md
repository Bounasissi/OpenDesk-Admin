# OpenDesk-Admin

Open-source, API-first, agent-ready macOS fleet administration — the practical administrative outcomes of Apple Remote Desktop via independent implementation of public protocols, with no Apple proprietary code.

**Agent entry point:** [`AGENTS.md`](AGENTS.md) → [`docs/program/00-MASTER-ORCHESTRATOR.md`](docs/program/00-MASTER-ORCHESTRATOR.md)

State after context loss: [`docs/status/program-state.json`](docs/status/program-state.json)
Program-wide policy: [`docs/program/PROGRAM_CHARTER.md`](docs/program/PROGRAM_CHARTER.md)

## Canonical status (2026-09-13)

Canonical branch: **`canonical-091326`** — reconciled from three development histories per
[`docs/program/00A-REPOSITORY-LINEAGE-RECONCILIATION.md`](docs/program/00A-REPOSITORY-LINEAGE-RECONCILIATION.md)
(evidence: [`docs/status/REPOSITORY_LINEAGE.md`](docs/status/REPOSITORY_LINEAGE.md)).
Every conversation claim was audited against current execution:
[`docs/status/CAPABILITY_AUDIT.md`](docs/status/CAPABILITY_AUDIT.md) — `swift build && swift test`: **92/92 passed, exit 0**.

Claims are historical evidence, not repository truth. Nothing counts as complete until the canonical branch proves it.

## What it does (verified on canonical branch)

| Capability | Module | Evidence |
|---|---|---|
| RFB/VNC remote control (handshake, VNC auth DES, Raw + Hextile, keys, pointer, clipboard) | `OpenDeskCore/Protocol` | 92-case suite incl. authenticated loopback RFB over real TCP |
| SSH command execution + WAN tunneling | `OpenDeskCore/Transport` | `TunnelTests`, transport tests |
| File distribution (scp/rsync, installer -pkg, plist defaults import) | `OpenDeskCore/Distribution` | command-shape tests |
| Inventory + RFC-4180 CSV / JSON export | `OpenDeskCore/Inventory` | CSV quoting tests |
| Fleet tasks (bounded concurrency, saved versioned tasks, schedules) | `OpenDeskCore/Tasks` | `Phase2Tests`, `SchedulerTests` |
| Wake-on-LAN | `OpenDeskCore/Tasks/WakeOnLAN` | magic-packet tests |
| Device registry (JSON + SQLite backends) | `OpenDeskCore/Transport` | `HostRegistryTests`, `SQLiteBackendTests` |
| GUI dashboard (roster, observe, tiled multi-screen) | `OpenDeskGUI` | source + manual QA (see audit) |

## Quick start

```bash
swift build
swift test

# CLI
swift run opendesk --help
swift run opendesk inventory --local
swift run opendesk hosts add mymac.local admin --groups lab-1
swift run opendesk task run --host mymac.local --command "sw_vers"

# GUI dashboard
swift run opendesk-gui
```

Packaging (development): `./scripts/build-app.sh release` → ad-hoc signed `.app` (dev milestone only; production signing is Plan 20).

## Program

The delivery program runs Plans 00A/00B (executed) → 01–23 to a signed, notarized, publicly downloadable v1.0:

- Plan documents: [`docs/program/`](docs/program/) (incl. amendments: 02-A1, 04-A1, 05-A1, 06-A1, 06A, 07-A1, 08-A1, 09-A1, 10-A1, 11-A1, 16A, 17A, 20-A1, 21-A1)
- Product: [`docs/product/PRODUCT_SPEC.md`](docs/product/PRODUCT_SPEC.md), [`docs/product/V1_SCOPE.md`](docs/product/V1_SCOPE.md), [`docs/product/POST_V1_ROADMAP.md`](docs/product/POST_V1_ROADMAP.md)
- Clean-room policy + ARD behavior analysis: [`docs/clean-room/`](docs/clean-room/), `reverse-engineering/`
- Post-v1 objectives: [`docs/product/POST_V1_ROADMAP.md`](docs/product/POST_V1_ROADMAP.md)

## License

MIT. See [`LICENSE`](LICENSE). The canonical tree contains no Apple source code, no proprietary binaries, and no GPL-linked components. GPL-derived scaffold sources remain on `OG-Output-Plan-0913` as reference evidence (ruling: `docs/status/REPOSITORY_LINEAGE.md` §2; reconciliation: [`docs/program/16A-LICENSE-DEPENDENCY-RECONCILIATION.md`](docs/program/16A-LICENSE-DEPENDENCY-RECONCILIATION.md)).
