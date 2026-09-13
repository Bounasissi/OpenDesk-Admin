# Changelog

All notable changes to OpenDesk-Admin.

## 0.3.0 — 2026-09-13

### Added
- **Screen streaming**: live RFB framebuffer rendering in the GUI Screen
  Viewer window; Control mode with keyboard/mouse injection; tiled
  multi-host observation grid (1–4 columns)
- **Hextile encoding** (RFC 6143 §7.7.4) — bandwidth-efficient updates;
  Raw kept as fallback; >10× smaller than Raw for desktop-like content
  (validated by test)
- **SSH tunnel** (`opendesk tunnel`) — screen access over WAN/VPN,
  addressing ARD's known LAN-only limitation
- **Fleet tasks**: bounded-concurrency execution across the roster,
  saved task definitions with versioning, result export (CSV/JSON)
- **Recurring schedules**: interval + daily triggers, persisted,
  `opendesk schedule daemon` plus launchd wrapper for boot persistence
- **Inventory**: hardware/software reports (local + remote), CSV/JSON
  export, installed-app listing
- **Distribution**: file push (scp/rsync), .pkg install, plist payloads
  via `defaults import`
- **Wake-on-LAN**, **Bonjour discovery** (`_rfb._tcp`)
- **Registry backends**: JSON file (default) + shared SQLite for
  multi-admin rosters
- **GUI dashboard** (SwiftUI): roster, discovery, task runner, inventory,
  screen viewer, tiled observation
- **Packaging**: `OpenDesk Admin.app` build script with ad-hoc signing;
  client provisioning script

### Protocol core
- RFB 3.8 client: version negotiation (incl. Apple's `003.889`
  pseudo-version), security negotiation, VNC DES challenge/response
  (FIPS 46-3 DES verified against standard test vector), pixel-format
  negotiation, framebuffer updates, key/pointer/cut-text events

## 0.1.0 — 2026-09-13
- Initial MVP: RFB protocol core, SSH transport, task engine, inventory
  collector, distribution engine, `opendesk` CLI, 22 tests.
