# REPO_CENSUS — OpenDesk-Admin (Plan 01 §3.1)

> Recorded 2026-09-13 on branch `canonical-091326` after addendum execution (00A/00B).

| Field | Value |
|---|---|
| Git remote | `git@github.com:Bounasissi/OpenDesk-Admin.git` (origin) |
| Branches | `main`, `canonical-091326` (canonical), `initial-091396`, `OG-Output-Plan-0913`, `post-initial-work-091326`, `4-mapping-reqs-reflect-091326` |
| Canonical commit at census | addendum commit series (`4cbd4eb`..`f874288` + Plan 01 series) |
| Structure | Single SwiftPM package (`OpenDeskAdmin`); targets: `OpenDeskCore` (library), `OpenDeskCLI` (executable), `OpenDeskGUI` (executable), `OpenDeskCoreTests` (test target) |
| Minimum macOS | **14.0** (ADR-0004; `Package.swift` bumped from `.v13` in Plan 01) |
| Toolchain (measured) | Swift 6.3.3 (`swiftlang-6.3.3.1.3 clang-2100.1.1.101`), Xcode 26.6 (17F113), arm64 |
| Dependencies | **None** (zero SwiftPM packages; system `libsqlite3` via SQLite3 module) |
| Tests | 92 XCTest cases across 12 files (Tests/OpenDeskCoreTests) — all passing, 0 failed |
| Build warnings | **0** after Plan 01 cleanup (was 38 incl. duplicates: Optional `.none` ambiguity ×4, never-mutated `var` ×2, unused bindings ×2, unreachable `return`, MainActor call from Thread, redundant `_ =`, NSImage Sendable ×2 resolved by .v14) |
| CI | `.github/workflows/ci.yml` — build + lint (warnings-as-errors) + test + secret-scan + license-check; **green on `canonical-091326`** (run 34780948563) |
| Licenses | MIT (`LICENSE`, ADR-0006); GPL scaffold sources excluded (REPOSITORY_LINEAGE.md §2) |
| Clean-room artifacts | `docs/clean-room/`, `reverse-engineering/behavior-specs/` (7 YAMLs), `scripts/analyze-ard-bundle.sh`, `scripts/capture-experiment.sh` |
| Programs/governance | `AGENTS.md`, `docs/program/00A..23`, `docs/status/` ledger, ADRs 0001–0006 |
| Debug/release schemes | `swift build` (debug) / `./scripts/build-app.sh release` (release .app bundle) |
| Configuration separation | App state under `~/.opendesk/` (hosts.json default) + `~/Library/Application Support/OpenDeskAdmin/` (scaffold SQLite path); no secrets in repo (secret-scan gate) |
| Bundle identifiers / entitlements | Not yet defined in Package.swift era (created in Plan 20 packaging work); tracked |
