# PROTOCOL_OBSERVATIONS — OpenDesk

**Owner:** Plan 02 (living document). Holds established public facts and derived observations. Every entry cites evidence.

## 2. Open Questions / Pending Observations

| ID | Question | Blocking plan |
|---|---|---|
| Q1 | Does the ARD admin app expose XPC services or additional task wire behavior not present in the client bundles? (Requires admin app install) | 02 (gate), 08 |
| Q2 | Live interop behavior of Apple Screen Sharing banner `RFB 003.889` against a real host (banner observed in ARDAgent support tools? verify live) | 06, 17A |
| Q3 | Exact preference domains the ARD admin app writes (client bundles show none; admin app pending) | 02 (gate) |

## 1. Established Public Facts

| # | Fact | Evidence |
|---|---|---|
| F1 | ARD traffic uses TCP/UDP 5900 (RFB), TCP/UDP 3283 (ARD reporting), TCP 22 (SSH) | Apple documentation (public ports list) |
| F2 | RFB security type 30 is the Apple Remote Desktop authentication type | IETF VNC community documentation; LibVNCClient sources |
| F3 | LibVNCClient supports Apple ARD security type 30 | Public LibVNCClient implementation/docs |
| F4 | `SMAppService` registers LaunchAgents/LaunchDaemons on macOS 13+ | Apple documentation |
| F5 | ScreenCaptureKit includes persistent capture support for VNC applications while requiring user-granted screen-capture permission | Apple documentation |
| F6 | Developer ID-distributed software requires signing, Hardened Runtime, secure timestamps, and notarization; sandboxing is recommended, not mandatory, outside the App Store | Apple documentation |
| F7 | Sparkle 2 supports SPM integration, HTTPS distribution, Developer ID/notarization, and Ed25519-signed updates | Sparkle project documentation |

Rules: facts are seeded from public documentation only; observations from experiments (ARD-EXP-###) are appended with capture references and must pass the redaction policy.

---

## 2. Open Questions / Pending Observations

| ID | Question | Blocking plan |
|---|---|---|
| (none seeded) | Filled by Plan 02/06 as encountered | — |

---

## 3. Maintenance

- Append-only per fact/observation; superseded facts are marked, not deleted.
- Plan 17/23 compatibility monitoring updates this file when macOS releases change behavior (ScreenCaptureKit, TCC, background items, notarization).
- No proprietary payload content ever appears here (see `IMPLEMENTATION_SEPARATION.md`).

---

## 3. Bundle Observations (Plan 02 static analysis, 2026-09-13)

Evidence: `reverse-engineering/protocol-observations/CLIENT-BUNDLE-FACTS.md` (ARD-BUNDLE-001..003, harness outputs committed alongside). Interface facts only; no strings dumps, no proprietary resources committed.

| # | Observation | Evidence |
|---|---|---|
| B1 | ARD client agent ships as `ARDAgent.app` v3.9.8 (`com.apple.RemoteDesktopAgent`), arm64e universal, LSUIElement | harness output `arda-client-analysis/` |
| B2 | ARDAgent links `ScreenSharingServer` (private) and holds `screensharing.screenControl` private entitlement → screen capture/control is Apple-private; OpenDesk uses RFB (A) / ScreenCaptureKit (B) | entitlements dump |
| B3 | Package installation path uses PackageKit (`system.install.apple-software` private authorization) → OpenDesk uses public `installer -pkg` (class B, no private auth) | entitlements dump |
| B4 | Power operations couple to `login` private framework + `iokit.assertonlidclose` → OpenDesk power tasks use public shutdown/osascript/IOKit surfaces | linked-frameworks + entitlements |
| B5 | `tcc.allow kTCCServiceSystemPolicyAllFiles` on the agent explains inventory file-search reach; OpenDesk needs user-granted Full Disk Access → Plan 15 onboarding detection | entitlements dump |
| B6 | ScreensharingAgent links `ConfigurationProfiles` → MDM-managed Remote Management configuration is a supported deployment surface (Plan 13) | `screensharing-agent-analysis/` |
| B7 | AppleVNCServer links `TCC` → screen permission enforcement is in-server; OS consent flow governs OpenDesk equally | `applevnc-server-analysis/` |
| B8 | Helper inventory: `ardpackage`, `build_hd_index`, `distnotifyutil`, `kickstart`, `sysinfocachegen`, `tccstate` + nested `Shared Screen Viewer.app` | bundle tree |
| B9 | No XPC services observed in client bundles; admin-app XPC surface is an open question (Q1) | bundle tree |

These observations are classified inputs to plans 04 (discovery/probes), 06 (protocol), 07 (power/packages), 09 (inventory), 11 (agent), 13 (MDM), 15 (permissions detection).
