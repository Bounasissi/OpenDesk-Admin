# Roadmap

## Phase 1 — Core Engine ✅
- [x] RFB protocol client core (handshake, security negotiation, VNC DES auth)
- [x] SSH transport + host registry
- [x] Task engine (UNIX commands, power tasks) with per-host result capture
- [x] Inventory collector (hardware + software reports)
- [x] Distribution engine (file push, package install)
- [x] `opendesk` CLI with subcommands
- [x] Unit + integration tests

## Phase 2 — Fleet Ops Hardening ✅
- [x] Wake-on-LAN power tasks (`opendesk wake`, RFC 102-byte magic packet, UDP broadcast)
- [x] Saved task definitions with versioning (TaskStore: update bumps version, duplicate names rejected)
- [x] Result/inventory export (CSV + JSON, RFC 4180 quoting)
- [x] Discovery: Bonjour `_rfb._tcp` browser (FleetDiscovery)
- [x] Concurrent task execution across fleet (bounded parallelism, order-preserving)
- [x] Raw framebuffer update decoding + input event messages (KeyEvent/PointerEvent/CutText)
- [x] CI workflow (GitHub Actions, macos-14, swift build + test)

## Phase 3 — GUI Dashboard (SwiftUI) — core complete ✅
- [x] Roster view with groups + add-host bar
- [x] Bonjour discovery section in sidebar
- [x] Task runner UI with live results
- [x] Inventory report viewer
- [x] Screen connect + handshake status view
- [x] Single-screen live observation (ScreenStreamer → Screen Viewer window)
- [x] Control mode input routing (NSEvent → KeysymMap → RFB KeyEvent/PointerEvent)
- [x] Tiled multi-screen observation (TiledObservationView, 1–4 column grid)

## Phase 4 — Advanced
- [x] Scheduled tasks (in-process TaskScheduler; interval + daily triggers; `opendesk schedule daemon` for foreground runs; launchd plist wrapper documented as the boot-persistent path)
- [x] Preference/plist payload distribution (`defaults import` over SSH)
- [ ] Multi-admin shared registry (SQLite or Supabase backend behind a flag)
- [ ] App Store-independent signed/notarized distribution

## Explicitly not planned
- Replicating ARD's proprietary admin↔client protocol
- Any use of Apple's ARD client agent
