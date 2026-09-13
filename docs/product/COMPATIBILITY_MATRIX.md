# COMPATIBILITY_MATRIX — OpenDesk

**Owner:** OpenDesk program. Living document: Plans 02 and 17 are its producers; agents must keep it current.

---

## 1. ARD Capability Classification Scheme (from Plan 02)

Every Apple Remote Desktop capability gets exactly one classification:

| Class | Meaning | v1 disposition |
|---:|---|---|
| **A** | Standard protocol directly interoperable | Implement via standard protocol (e.g., RFB/VNC, SSH) |
| **B** | Functionality reproducible with public macOS APIs | Implement with native APIs (e.g., ScreenCaptureKit, system_profiler) |
| **C** | Optional ARD wire compatibility useful | Optional interop mode; never a v1 blocker |
| **D** | Replace with OpenDesk-native implementation | OpenDesk-defined protocol/behavior (e.g., endpoint agent protocol) |
| **E** | Defer from v1 | Post-v1 opportunity; recorded with rationale |

---

## 2. Capability Classification Table (initial; refined by Plan 02)

| ARD capability | Class | OpenDesk implementation | Plan |
|---|:---:|---|---|
| Observe/control remote screen | A | RFB client (RFB 5900; ARD security type 30 via LibVNCClient or equivalent) | 06 |
| Multi-observe thumbnails | B/D | Session manager + quality tiers over RFB | 10 |
| Clipboard sync | B | Public clipboard APIs at both ends | 06 |
| Remote commands | A/B | SSH (port 22) + typed RemoteCommandService; agent channel later | 07, 11 |
| File copy (push/pull) | A/B | SSH/SFTP with policy + checksums | 07 |
| Package install | B | `installer -pkg` staged pipeline (checksum verify) | 07 |
| Wake | B | Wake-on-LAN broadcast where supported | 07 |
| Restart/shutdown/sleep/logout | B | Typed power tasks via remote execution / agent | 07, 11 |
| Inventory/reports | B | Public macOS APIs + typed CLI wrappers (system_profiler, softwareupdate, mdfind, launchctl, diskutil, networksetup) | 09 |
| Scheduled tasks / offline tasks | D | OpenDesk-native task engine + scheduler (durable, idempotent) | 08 |
| Smart groups | D | OpenDesk-native predicate engine | 04 |
| Endpoint agent features | D | OpenDesk Agent protocol (LaunchDaemon + LaunchAgent, XPC, TLS) | 11 |
| High-performance streaming | B/D | ScreenCaptureKit → VideoToolbox → secure transport (post-parity-core) | 14 |
| Private Task Server wire protocol | E | Not duplicated; OpenDesk task model replaces it | 08 |
| Every historical ARD report | E | Core report set only (Plan 09); others post-v1 | 09 |
| MDM-assisted provisioning | B | Public MDM payloads (generic/Jamf/Kandji/Mosyle/Intune where permitted) | 13 |

Rules:

- No v1 requirement may remain classified "figure out how Apple did it" (Plan 02 exit gate).
- Class E items are explicitly deferred with rationale; they never block the v1 gate.
- Any class change requires an ADR.

---

## 3. Supported Platform Matrix (from Plan 17)

### 3.1 Admin Mac

| Configuration | Support level |
|---|---|
| macOS 14 (minimum) | Supported (blocking gate) |
| Current stable macOS | Supported (blocking gate) |
| Apple Silicon | Supported (blocking gate) |
| Intel | Supported where still within deployment-target reach |
| Current macOS beta | Informational lane only (non-blocking) |

### 3.2 Remote endpoints

| Configuration | Support level |
|---|---|
| macOS current stable | Supported |
| Minimum supported remote macOS | Supported |
| Apple Silicon / Intel | Supported where applicable |
| macOS Remote Management (RFB, security type 30) | Primary v1 target |
| Ordinary VNC server | Supported for observe/control basics |
| OpenDesk Agent | Supported (no-SSH path) |
| macOS beta endpoint | Informational lane only |

### 3.3 Network conditions (Plan 17)

```text
LAN
high latency
packet loss
temporary disconnect
IP change
sleep/wake
VPN/Tailscale-like path
offline/reconnect
```

---

## 4. Agent/Admin Version Skew (from Plan 11)

Admin app and endpoint agent must tolerate **at least one version of skew**. The handshake (`protocolVersion`, `capabilities[]`, `agentVersion`) is the compatibility contract; the supported-pair matrix is documented in Plan 11 outputs and kept current here.

---

## 5. Public Facts Cited (from Plan 02)

```text
ARD traffic: TCP/UDP 5900 (RFB), TCP/UDP 3283 (ARD reporting), TCP 22 (SSH)
RFB security type 30 = Apple Remote Desktop authentication; LibVNCClient supports it
SMAppService registers LaunchAgents/LaunchDaemons on macOS 13+
ScreenCaptureKit supports persistent capture for VNC applications, with user-granted screen-capture permission
Developer ID distribution requires signing + Hardened Runtime + secure timestamps + notarization
Sparkle 2: SPM integration, HTTPS distribution, Ed25519-signed updates
```

Each row must cite evidence (experiment ID, Apple documentation URL, RFC) in `docs/clean-room/PROTOCOL_OBSERVATIONS.md`.
