# Software Requirements Specification & Development Roadmap

## 1. Product Definition

**OpenDesk Admin** — open-source, API-first, agent-ready macOS fleet administration. Clean-room replacement for Apple Remote Desktop (ARD 3.10, $79.99, macOS 15.5+).

**Primary user:** macOS system administrator / IT operator managing a fleet of Macs (labs, SMB, education, agencies).

**Jobs to be done:**
1. Find, register, and group Macs on the network.
2. Observe and control remote screens (single + multi-observe).
3. Push/pull files; install packages; run commands/scripts.
4. Collect hardware/software/network/user inventory; run reports.
5. Schedule, queue, and retry tasks across groups — including offline machines.
6. Govern: permissions, credentials, audit trail.

**Out of scope (explicitly):** pixel-equivalent ARD UI; reconstruction of Apple source; Apple High Performance wire protocol (v1); Windows/Linux admin console (clients remain VNC-interoperable).

## 2. Functional Decomposition (ARD → OpenDesk)

| ARD subsystem | Observable capability | OpenDesk implementation | Module |
|---|---|---|---|
| Computer discovery | Locate Macs | Bonjour/mDNS + CIDR scanner + manual | discovery |
| Device registry | All Computers | SQLite device registry | device-registry |
| Lists | Static groups | SQLite relationships | device-registry |
| Smart Lists | Dynamic groups | Predicate/query engine | device-registry |
| Authentication | Mac/ARD/VNC credentials | Keychain-backed credential manager | security |
| Observe | View remote desktop | RFB/VNC client | rfb |
| Control | Keyboard/mouse control | RFB input events | rfb |
| Multi-observe | Many Macs simultaneously | Session fan-out + thumbnail grid | rfb |
| Clipboard | Shared clipboard | RFB clipboard extensions | rfb |
| File copy | Push/pull files | SFTP/SCP | transfers |
| Drag/drop | Finder-like transfers | UI wrapper on transfer engine | transfers |
| Package deployment | `.pkg`/`.mpkg` | SSH + `installer` | packages |
| Offline installs | Task Server | Durable job queue + worker | tasks |
| UNIX commands | Execute shell | SSH | ssh |
| Scripts | Multi-line shell tasks | SSH task runner | ssh |
| Wake/Sleep/Restart/Shutdown/Logout | Power management | Wake-on-LAN + SSH | ssh |
| Lock screen | Prevent local interaction | Agent / Remote Management | agent (V2) |
| Messaging | Send user message | Agent + notification/dialog | agent (V2) |
| Inventory | Hardware/software data | Collectors + system_profiler | inventory |
| File reports | File/software searches | Spotlight/mdfind/agent | inventory |
| App usage | Application history | Endpoint collector | inventory |
| User history | Login/logout records | Unified Log collector | inventory |
| Network reports | Latency/reachability | ICMP/TCP/UDP probes | inventory |
| Reporting DB | Persistent inventory | SQLite | reporting |
| Task history | Historical jobs | SQLite | tasks |
| Scheduled tasks | Future/recurring | RRULE scheduler | scheduler |
| Task templates | Reusable actions | JSON/YAML task definitions | tasks |
| Task Server | Async execution | Daemon/job broker | tasks |
| Permissions | Per-user privileges | RBAC | security |
| AppleScript | Automation | CLI + App Intents + JSON API | apps/cli |
| VNC interoperability | Win/Linux/Unix hosts | Standard RFB/VNC | rfb |
| High Performance | High-FPS/HDR | Custom streaming engine (V2+) | protocol |
| Remote audio | Stereo audio | Streaming channel (V2+) | protocol |
| Virtual display | Separate login desktop | Agent/session subsystem (V3+) | agent |

## 3. Roadmap — Priority Implementation Sequence

Priority 3 = do now · 2 = next · 1 = later · 0 = never.

| Priority | Milestone | Definition of Done |
|---:|---|---|
| 3 | ARD decomposition harness | Bundle analyzer + behavior matrix + test lab + docs |
| 3 | Device discovery | Bonjour/IP/manual discovery, persistent devices |
| 3 | Remote control | Authenticate/view/control macOS Remote Management |
| 3 | SSH execution | Commands/scripts against one or many machines |
| 3 | File transfer | Reliable push/pull with progress |
| 3 | Package deployment | `.pkg` upload/install/result collection |
| 3 | Unified task engine | Every management operation becomes a task |
| 3 | Inventory | Core hardware/software/network reports |
| 2 | Groups + Smart Groups | Fleet targeting |
| 2 | Multi-observe | Grid of remote screens |
| 2 | Scheduler | once/repeating/on-reconnect tasks |
| 2 | Worker/Task Server | Disconnected execution + retries |
| 2 | Audit/security | Keychain, RBAC, audit events |
| 2 | OpenDesk agent | Richer endpoint capabilities |
| 1 | Share-screen broadcast | One-to-many demonstration |
| 1 | Lock/curtain | Remote local-input restriction |
| 1 | MDM deployment | Zero/low-touch enterprise enrollment (Jamf, Kandji, Mosyle, Intune, generic) |
| 1 | High Performance | Custom 60-fps streaming |
| 1 | Audio/HDR | Higher-performance media extensions |
| 0 | Pixel-equivalent ARD UI | Unnecessary |
| 0 | Reconstruct Apple source | Unnecessary |

## 4. Beyond ARD (differentiators)

Natural-language task creation · AI-assisted failure remediation · Tailscale-native connectivity · WebRTC/QUIC high-performance mode · configuration drift detection · desired-state policies · live telemetry · structured JSON output · REST API · webhooks · GitOps task definitions · health monitoring · rollback-aware installs · fleet compliance scoring · remote log investigation · built-in terminal · remote process/launchd manager · software update orchestration · Homebrew management · Shortcuts integration.

Thesis shift: from "Free Apple Remote Desktop" → **open-source, API-first, agent-ready macOS fleet administration**.

## 5. Non-Functional Requirements

- **Security:** no secrets in SQLite (Keychain only); no borrower-style PII in logs; signed + notarized builds.
- **Reliability:** idempotent tasks, retry with backoff, per-host results, resumable transfers.
- **Performance:** multi-observe throttling (focused 30–60 FPS / thumbnail 2–5 FPS / background 0.2–1 FPS).
- **Compatibility:** macOS 15+ admin; clients via built-in Remote Management or standard VNC.
- **License:** GPL-3.0-or-later throughout (LibVNCClient is GPL-2.0-or-later).
- **Automation:** CLI, App Intents/Shortcuts, JSON task API, local REST/Unix socket — all on the same service layer.

## 6. Acceptance — Clone Definition of Done

A fresh administrator installs OpenDesk and, without Apple Remote Desktop, can:

```
✓ Find Macs                          ✓ Run tasks across groups
✓ Authenticate                       ✓ Track task progress
✓ Save Macs                          ✓ Track per-machine failures
✓ Create lists / smart lists         ✓ Save task templates
✓ Observe / control a screen         ✓ Schedule tasks
✓ Multi-observe                      ✓ Retry offline targets
✓ Clipboard / multiple displays      ✓ Persist results
✓ Push / pull files                  ✓ Export reports
✓ Install PKGs                       ✓ Audit administrator actions
✓ Run commands / scripts             ✓ Support ordinary VNC hosts
✓ Wake / sleep / restart / shutdown  ✓ Work with macOS Remote Management
✓ Log users out                      ✓ Use secure credentials
✓ Inventory hw/sw/net/files          ✓ Deploy through MDM
✓ Compare software                   ✓ CLI / Shortcuts / API automation
✓ Signed, notarized, reproducible open-source builds
✓ No Apple proprietary code/assets included
```
