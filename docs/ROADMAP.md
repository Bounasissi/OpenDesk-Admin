# Roadmap

## Phase 1 — Core Engine (this repo, current)
- [x] RFB protocol client core (handshake, security negotiation, framebuffer request/decode skeleton)
- [x] SSH transport + host registry
- [x] Task engine (UNIX commands, power tasks) with per-host result capture
- [x] Inventory collector (hardware + software reports)
- [x] Distribution engine (file push, package install)
- [x] `opendesk` CLI with subcommands
- [x] Unit + integration tests

## Phase 2 — Fleet Ops Hardening
- [ ] Wake-on-LAN power tasks
- [ ] Saved task definitions with versioning + JSON schema
- [ ] Result aggregation reports (export CSV/JSON)
- [ ] Discovery: Bonjour `_rfb._tcp` / `_ssh._tcp` browser to auto-populate roster
- [ ] Concurrent task execution across fleet (bounded parallelism)

## Phase 3 — GUI Dashboard (macOS, SwiftUI)
- [ ] Roster view with groups
- [ ] Single + tiled screen observation windows (bind RFB client to NSImageView/Canvas)
- [ ] Control mode (key/mouse injection via CGEvent)
- [ ] Task runner UI with live results
- [ ] Inventory report viewer

## Phase 4 — Advanced
- [ ] Scheduled tasks (launchd integration)
- [ ] Preference/plist payload distribution
- [ ] Multi-admin shared registry (SQLite or Supabase backend behind a flag)
- [ ] App Store-independent signed/notarized distribution

## Explicitly not planned
- Replicating ARD's proprietary admin↔client protocol
- Any use of Apple's ARD client agent
