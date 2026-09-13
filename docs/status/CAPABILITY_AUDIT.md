# CAPABILITY_AUDIT — Conversation Claims → Current Evidence

> Produced by Plan 00B, executed 2026-09-13. Canonical branch: `canonical-091326`.
> Statuses: `VERIFIED_CURRENT`, `PRESENT_BUT_UNVERIFIED`, `MISSING`, `SUPERSEDED`, `CONFLICTING`, `EXTERNAL_GATE`, `POST_V1`.
> Machine-readable ledger: `docs/status/capability-audit.json`.

## 0. Execution Evidence (authoritative, current)

| Check | Result |
|---|---|
| Branch | `canonical-091326` @ merge `e41a699` |
| Command | `swift build && swift test` |
| Result | build OK; **92/92 XCTest cases passed, 0 failed; exit 0** |
| Toolchain | Swift 6.3.3, Xcode 26.6, arm64-apple-macosx28.0, 2026-09-13 |
| Source-branch re-verification | `initial-091396` 92/92 PASS; `OG-Output-Plan-0913` 31/31 PASS (5 suites, Swift Testing) — both exit 0 |
| CI workflow | present (`.github/workflows/ci.yml`) — remote-run status unverified this session |

## 1. RFB / Remote Control

| Capability | Claim source | Status | Evidence / gap | Required action |
|---|---|---|---|---|
| RFB handshake (None) | both | VERIFIED_CURRENT | `RFBClientTests.testHandshakeWithNoneSecurity`; loopback `testNoAuthHandshakeSucceeds` | — |
| Standard VNC auth (DES challenge-response) | impl | VERIFIED_CURRENT | `VNCAuthTests` (bit reversal, key derivation, 16-byte deterministic challenge/response); loopback `testAuthenticatedHandshakeAndRawPixelDecode` | — |
| Wrong-password rejection | impl | VERIFIED_CURRENT | loopback `testWrongPasswordIsRejected` | — |
| RFB `003.889` pseudo-version handling | impl (Apple Screen Sharing) | **PRESENT_BUT_UNVERIFIED** | Source handles minor>255 (`RFBClient.swift` §83–160, "treated as 3.8-capable") but tests cover only `003.008` + garbage (`testVersionParse`, `testVersionParseRejectsGarbage`) | Add explicit `003.889` parse/negotiate test + malformed-banner test (Plan 06) |
| DES standard known-answer vector | Addendum §1 | **PRESENT_BUT_UNVERIFIED** | Determinism tests exist; no published-vector KAT | Add standard DES known-answer test (Plan 06) |
| FramebufferUpdateRequest wire format | impl | **PRESENT_BUT_UNVERIFIED** | `testFramebufferUpdateRequestMessage` asserts type 0x03, incremental byte, 10-byte length — X/Y position fields not asserted | Strengthen test to assert X/Y (Plan 06) |
| Raw framebuffer decoding | impl | VERIFIED_CURRENT | `FramebufferDecoderTests` (7 cases) | — |
| Hextile decoding | impl | VERIFIED_CURRENT | `HextileTests` (8 decoder + 2 end-to-end + 1 bandwidth case) | — |
| CopyRect | scaffold claim | PRESENT_BUT_UNVERIFIED | decoding path in canonical decoder (grep) — needs explicit test | Test or defer ruling (Plan 06) |
| Pixel-format scaling | impl | VERIFIED_CURRENT | `testScaleChannelRoundTrip` | — |
| KeyEvent wire format | impl | VERIFIED_CURRENT | loopback `testInputEventsReachTheServer` (byte-level assertions) | — |
| PointerEvent wire format | impl | VERIFIED_CURRENT | same test (byte-level) | — |
| CutText/clipboard | impl | PRESENT_BUT_UNVERIFIED | `sendCutText` exercised in loopback; byte-level CutText assertion absent | Assert CutText bytes in loopback test (Plan 06) |
| Frame rendering | impl | VERIFIED_CURRENT | `FramebufferRendererTests` (3) + `ScreenRenderingTests` | — |
| Keysym mapping | impl | VERIFIED_CURRENT | `ScreenRenderingTests` (6 cases) | — |
| Live screen streaming + control mode | impl | PRESENT_BUT_UNVERIFIED | `ScreenSession`/`ScreenStreamer` source + GUI wiring exist; unit-verified rendering only | Integration harness (Plan 06 §6) |
| Tiled observation (1–4 columns) | impl | PRESENT_BUT_UNVERIFIED | `TiledObservationView` source; no headless test | Plan 10 harness |
| Connection soak (100-cycle) | plan requirement | MISSING | no soak test on canonical | Plan 06 A1 hardening list |
| Partial socket reads (fragmented/single-byte/multi-frame/EOF/short) | Addendum §1 | **MISSING (tests)** | No dedicated fragmented-read tests found; transport layer exists | Required regression tests (Plan 06) |
| Network-framework threading assertions | Addendum §1 | MISSING | no concurrency assertion test found | Plan 06 |
| Apple Screen Sharing interop (real host) | impl claim | EXTERNAL_GATE | requires real macOS host → Plan 17A lab | 17A matrix row |

## 2. Transport / Discovery / Registry

| Capability | Status | Evidence / gap | Required action |
|---|---|---|---|
| SSH command execution | VERIFIED_CURRENT | `SSHTransport` + Phase2 per-host transport tests (live run requires hosts) | — |
| SSH tunnel (WAN) | VERIFIED_CURRENT | `TunnelTests` (3: free port, unreachable-host failure, command shape) | — |
| Wake-on-LAN | VERIFIED_CURRENT | `testMagicPacketLayout`, `testMacFormatVariants`, `testInvalidMACThrows`, `testWakeHostWithoutMACThrows` | — |
| Bonjour discovery (`_rfb._tcp`) | PRESENT_BUT_UNVERIFIED | `FleetDiscovery` source; no headless browse test | Headless mDNS unit test (Plan 04) |
| CIDR scan + dedupe | SUPERSEDED (scaffold code) → MISSING on canonical | scaffold `Discovery.swift` excluded by lineage ruling | Implement in Plan 04 A1.1 |
| Manual hostname/IPv4/IPv6 add | VERIFIED_CURRENT | `hosts add` CLI + `HostRegistryTests` (4 cases) | — |
| Registry persistence (JSON + SQLite backends) | VERIFIED_CURRENT | `HostRegistryTests`, `SQLiteBackendTests` (7 cases) | — |
| Device identity reconciliation | MISSING | no implementation on canonical | Plan 04 §2.4 + A1.2 |
| Device states (unknown/online/degraded/offline/retired) | MISSING | current model: online/lastSeen only | Plan 04 §2.5 |
| Smart Groups (predicate engine, persisted definitions) | SUPERSEDED (scaffold) → MISSING on canonical | scaffold predicate engine excluded; 31-test suite passed on source branch only | Plan 04 A1.3 |
| Shared-SQLite multi-admin | CONFLICTING (conversation claim vs Charter) | backend exists (`RegistryBackend` protocol); production-safety unproven | Plan 04 A1.4 experiment + ADR |

## 3. Tasks / Scheduler

| Capability | Status | Evidence / gap | Required action |
|---|---|---|---|
| Bounded-concurrency fleet execution | VERIFIED_CURRENT | `Phase2Tests` (4 cases: ordering, failure aggregation, empty roster, per-host transport) | — |
| Saved tasks (TaskStore, versioned) | VERIFIED_CURRENT | `testAddListAndNameLookup`, `testUpdateBumpsVersion`, `testRemoveAndPersistence` | — |
| Duplicate task rejection | PRESENT_BUT_UNVERIFIED | add/list/remove/version covered; duplicate-id semantics not asserted | Explicit test (Plan 08 A1.1) |
| Schedule math (interval + daily) | VERIFIED_CURRENT | `SchedulerTests` (6 math cases) | — |
| Schedule persistence | VERIFIED_CURRENT | `testScheduleStoreAddListRemove` (JSON store) | Migrate to canonical DB (Plan 08 A1.2) |
| RRULE recurrence | SUPERSEDED (scaffold) → MISSING on canonical | scaffold RRULE parser tested on source branch only | Plan 08 §5 |
| Run-once-later / on-reconnect / on-predicate | MISSING on canonical | plan requirement; not implemented | Plan 08 §5 |
| Durable task states (WAITING_FOR_TARGET, RETRY_WAIT, restart survival) | MISSING | current engine is in-process | Plan 08 §2 A1.1 |
| Idempotency keys / duplicate prevention | MISSING | not implemented | Plan 08 §7 |

## 4. Files / Packages / Inventory

| Capability | Status | Evidence / gap | Required action |
|---|---|---|---|
| scp/rsync push/pull | PRESENT_BUT_UNVERIFIED | `DistributionEngine` source; CLI verified per README claim; no unit test for command construction beyond plist | Command-shape tests (Plan 07) |
| Package install pipeline (installer -pkg) | PRESENT_BUT_UNVERIFIED | source + CLI; no checksum verification | Plan 07 A1.2 |
| Plist staging + defaults import (byhost) | VERIFIED_CURRENT | `testDefaultsImportCommandShape`, `testByhostDomainPrefixStripsCorrectly` | — |
| Checksum-verified transfers | MISSING on canonical | scaffold design excluded | Plan 07 A1.2 |
| Inventory collectors (hardware/OS/apps/…) | PRESENT_BUT_UNVERIFIED | `InventoryTests` (4: profiler JSON parse, GB/MB, invalid JSON, local report) | Plan 09 collector breadth |
| CSV export (RFC-4180 quoting) | VERIFIED_CURRENT | `testResultsCSVQuotingAndLayout`, `testReportsCSV`, `testAppsCSV` | — |
| JSON export | PRESENT_BUT_UNVERIFIED | exporter source; no dedicated JSON-schema test | Add test (Plan 09) |
| Historical snapshots / diff / device-vs-device / aggregates | MISSING | plan requirement; not implemented | Plan 09 A1.1 |

## 5. GUI / UX

| Capability | Status | Evidence / gap | Required action |
|---|---|---|---|
| GUI launches (SwiftUI app) | PRESENT_BUT_UNVERIFIED | `OpenDeskGUIApp` source; no automated launch test | XCTest launch smoke (Plan 15) |
| GUI discovery concurrency | MISSING | no test | Plan 10 session manager |
| Tiled multi-observe | PRESENT_BUT_UNVERIFIED | source only; 1–4 columns | Plan 10 A1 (2/4/8/16 + resource bounds) |
| Onboarding permission detection | MISSING | plan requirement | Plan 15 §5 |
| Accessibility verification | MISSING | plan requirement | Plan 15 §6 |

## 6. Release / Security / Governance

| Capability | Status | Evidence | Required action |
|---|---|---|---|
| App bundle + ad-hoc signing (`build-app.sh`) | VERIFIED_CURRENT (dev milestone) | script + CHANGELOG; **not release-grade** | Plan 20 full chain |
| Developer ID / notarization / stapling / Gatekeeper | MISSING | external credential gate | Plan 20 §9 |
| Update feed (Sparkle 2 / Ed25519) | MISSING | plan requirement | Plan 20 §7 |
| CI (build+test) | PRESENT_BUT_UNVERIFIED | workflow file present; last remote run unverified this session | Verify first CI run on canonical |
| Keychain secret store | MISSING | Plan 05 (SQLite→CredentialID→Keychain) | Plan 05 |
| RBAC (13 privileges incl. `lock`) | MISSING | Plan 05 A1.2 | Plan 05 |
| Audit trail | MISSING | Plan 05 §6 | Plan 05 |
| Endpoint agent | MISSING | Plan 11 | Plan 11 |
| MDM provisioning | MISSING | Plan 13 | Plan 13 |
| License (MIT vs GPL conflict) | CONFLICTING | `REPOSITORY_LINEAGE.md` §2; canonical = MIT; scaffold GPL excluded | 16A + owner confirmation (EXTERNAL_GATE) |
| LibVNCClient vs custom Swift RFB | CONFLICTING | resolved: custom Swift (06A default ruling) | 06A exit gate |
| Real-Mac compatibility lab | EXTERNAL_GATE | no second Mac this session | Plan 17A |
| Alpha/Beta/RC milestones | MISSING | Plan 21 | Plan 21 |
| v1.0 public launch | MISSING | Plan 22 | Plan 22 |

## 7. Required Test Inventory (Addendum §25)

Capabilities that must have current tests if they exist — with current evidence:

| # | Capability | Current evidence | Gap |
|---:|---|---|---|
| 1 | RFB 003.889 negotiation | parse code only | test gap |
| 2 | DES known-answer | determinism tests only | test gap |
| 3 | Authenticated loopback RFB | `LoopbackEndToEndTests.testAuthenticatedHandshakeAndRawPixelDecode` | — |
| 4 | Wrong-password rejection | `testWrongPasswordIsRejected` | — |
| 5 | Raw decoding | `FramebufferDecoderTests` | — |
| 6 | Hextile decoding | `HextileTests` | — |
| 7 | Pixel-format scaling | `testScaleChannelRoundTrip` | — |
| 8 | Partial TCP reads | **none** | test gap |
| 9 | KeyEvent | loopback byte-level | — |
| 10 | PointerEvent | loopback byte-level | — |
| 11 | CutText | exercised, not byte-asserted | assertion gap |
| 12 | Frame rendering | `FramebufferRendererTests` | — |
| 13 | Bounded fleet concurrency | `Phase2Tests` | — |
| 14 | Wake-on-LAN packet | `testMagicPacketLayout` | — |
| 15 | TaskStore versioning | `testUpdateBumpsVersion` | — |
| 16 | Duplicate task rejection | **none** | test gap |
| 17 | CSV quoting | 3 dedicated tests | — |
| 18 | JSON report export | **none (dedicated)** | test gap |
| 19 | Bonjour discovery | **none (headless)** | test gap |
| 20 | Schedule math | `SchedulerTests` | — |
| 21 | Schedule persistence | `testScheduleStoreAddListRemove` | — |
| 22 | Plist import command construction | 2 dedicated tests | — |
| 23 | SSH tunnel command/lifecycle | `TunnelTests` | — |
| 24 | SQLite registry CRUD | `SQLiteBackendTests` | — |
| 25 | GUI launch | **none (automatable)** | test gap |
| 26 | GUI discovery concurrency | **none** | test gap |

Historical counts (22/45/54/67/80/88/92) are recorded as **conversation evidence only** — not release evidence. Only the §0 result on the canonical branch counts.

## 8. Bottom Line

- The implementation conversation's core technical claims are real and reproducible today: 92/92 tests pass on the canonical branch.
- The audit converts every remaining claim into tracked work: ~15 capability gaps map directly into plan amendments (00A–06A, 04, 05, 06, 07, 08, 09, 10, 11, 16A, 17A, 20, 21) already committed in `docs/program/`.
- No capability is marked `VERIFIED_CURRENT` without a pointer to current source, current tests, or an explicit external gate.
