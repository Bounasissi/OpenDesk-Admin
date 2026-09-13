# CLIENT-BUNDLE-FACTS — Lawful Static Analysis of Shipped ARD Client Components

> Plan 02 evidence. Produced 2026-09-13 by `scripts/analyze-ard-bundle.sh` against the ARD client components that ship with every macOS installation (lawfully available on this operator machine).
> Clean-room discipline: interface facts only — bundle topology, metadata, linked frameworks, entitlements, helpers. No strings dumps committed, no decompiled logic, no Apple assets in the repo.
> Raw structural outputs: `arda-client-analysis/`, `screensharing-agent-analysis/`, `applevnc-server-analysis/` (strings-*.txt intentionally excluded from the repository — ruling recorded in `docs/status/REPOSITORY_LINEAGE.md` style: interface facts, not proprietary resource text).

---

## ARD-BUNDLE-001 — ARDAgent.app

| Field | Observation |
|---|---|
| Bundle ID | `com.apple.RemoteDesktopAgent` |
| Version | 3.9.8 |
| LSUIElement | 1 (background agent, no Dock presence) |
| Binary format | Mach-O universal, arm64e (arm64e.x1 variant noted by codesign) |
| Nested app | `Contents/Support/Shared Screen Viewer.app` (separate viewer bundle) |
| Helpers (`Contents/Support/`) | `ardpackage`, `build_hd_index`, `distnotifyutil`, `kickstart` (script), `sysinfocachegen`, `tccstate` |
| Public frameworks linked | AppKit, ApplicationServices, Carbon, Cocoa, CoreAudio, CoreFoundation, CoreGraphics, CoreServices, DirectoryService, Foundation, IOKit, Kerberos, OpenDirectory, Security, SystemConfiguration |
| Private frameworks linked | CoreUtils, DiagnosticLogCollection, DiskManagement, PackageKit, **ScreenSharingServer**, SoftwareUpdate, login |
| Entitlements | `com.apple.private.AuthorizationServices` [system.install.apple-software]; `com.apple.private.diskmanagement.set-boot-device`; `com.apple.private.iokit.assertonlidclose`; `com.apple.private.logind.spi`; `com.apple.private.opendirectory.GetAuthenticationData`; `com.apple.private.screensharing.screenControl`; `com.apple.private.screensharing.xpcaccepted`; `com.apple.private.tcc.allow` [kTCCServiceSystemPolicyAllFiles]; `com.apple.screensharing.MessagesAgent`; `com.apple.security.temporary-exception.files.absolute-path.read-write` [/]; `com.apple.security.temporary-exception.files.home-relative-path.read-write` [.] |

Derived conclusions (interface-level):
- Package installation path uses PackageKit (`system.install.apple-software` authorization) — OpenDesk's `installer -pkg` pipeline (Plan 07) targets the same public `installer` surface without the private authorization.
- Power operations go through `login`/`iokit.assertonlidclose` — consistent with classification B (public `shutdown`/`osascript`/IOKit power APIs) in Plan 07.
- Screen capture/control is inside `ScreenSharingServer.framework` + `screensharing.screenControl` private entitlement — confirming OpenDesk must use RFB (class A) or ScreenCaptureKit (class B) instead (Plan 06/14; 06A ruling).
- TCC full-disk access (`kTCCServiceSystemPolicyAllFiles`) explains inventory file-search reachability — OpenDesk needs user-granted Full Disk Access for the same collector depth (Plan 09 + Plan 15 onboarding detection).

## ARD-BUNDLE-002 — ScreensharingAgent.bundle

| Field | Observation |
|---|---|
| Bundle ID | `com.apple.screensharing.agent` |
| Version | 3.9.8 |
| Private frameworks (sample) | AVConference, AccessibilitySharedSupport, AppleAccount, CloudDocs, CommunicationsFilter, ConfigurationProfiles, CoreTime, CoreUtils, CrashReporterSupport, DiagnosticLogCollection, … |
| Architecture | universal (multiple slices listed) |

Derived conclusions:
- Links `ConfigurationProfiles` — consistent with MDM-managed Remote Management configuration (Plan 13 managed-preference path).
- `AVConference`/`IDS` linkage indicates its messaging/notification surface is Apple-service-coupled — not a wire-compatibility target for OpenDesk (06A §4: deferred).

## ARD-BUNDLE-003 — AppleVNCServer.bundle

| Field | Observation |
|---|---|
| Bundle ID | `com.apple.AppleVNCServer` |
| Private frameworks (sample) | AVConference, AccessibilitySharedSupport, CoreUtils, DiagnosticLogCollection, IDS, SkyLight, TCC, TimeSync, UserActivity, login |
| Architecture | universal |

Derived conclusions:
- `TCC.framework` linkage confirms screen-sharing permission enforcement inside the server component — OpenDesk relies on the OS-level Screen Recording consent flow (Plan 15 §5: never claim consent granted until OS reports it).
- `SkyLight` linkage confirms the server reads the window-server display state — OpenDesk's ScreenCaptureKit path (Plan 14) is the public-API equivalent (class B).

## Coverage Ruling (Plan 02 A1)

| Required observation class | Status |
|---|---|
| bundle topology | RECORDED (3 bundles) |
| Mach-O architectures | RECORDED (universal/arm64e) |
| linked frameworks | RECORDED (public + private lists) |
| entitlements | RECORDED (ARDAgent full list) |
| helpers | RECORDED (6 helper binaries + nested viewer) |
| XPC services | none observed in these bundles (admin app may differ — gated) |
| public metadata (bundle IDs, versions) | RECORDED |
| preference domains | PARTIAL — full domains require admin app (gated) |
| observable network endpoints | PARTIAL — port facts established from public docs (F1); live capture gated |
| observable task behavior / failure behavior / state transitions | GATED — requires live ARD admin installation (external gate) |

**External gate:** the ARD admin application (`Remote Desktop.app`) is not installed on this operator machine. Live behavioral experiments (ARD-EXP-001..018) require a lawfully obtained installation. Gate recorded in `docs/status/PROGRAM_STATUS.md` §2. All lawful static observations recorded above.
