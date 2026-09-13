# Apple Remote Desktop — Feature Decomposition

Clean-room decomposition based on publicly documented behavior (App Store listing, Apple support docs, public user reports). No Apple binaries were disassembled or decompiled for this document.

## 1. Product Summary

Apple Remote Desktop (ARD) is a Mac fleet-management tool for sysadmins and educators. It is a single admin app that talks to managed client Macs over the network. Core value: **observe, control, execute, report, distribute** at fleet scale.

## 2. Capability Map

### 2.1 Screen Control & Observation
| Feature | Behavior | OpenDesk-Admin equivalent |
|---|---|---|
| Observe (view-only) | Watch one or many client screens | RFB client in read-only mode |
| Control (interactive) | Keyboard + mouse takeover | RFB client with input injection |
| Multi-screen tile view | Grid of many client screens | Planned (Phase 3, SwiftUI) |
| Screen sharing parity | ARD's viewer ≈ built-in macOS Screen Sharing (both VNC/RFB) | We implement the same open RFB protocol (RFC 6143) |

### 2.2 Task Execution
| Feature | Behavior | OpenDesk-Admin equivalent |
|---|---|---|
| Send UNIX command | Run shell command on 1..N clients, capture output | `TaskEngine` over SSH transport |
| Sleep / Wake / Restart / Shut down | Power management across fleet | `PowerTasks` (ssh + `pmset`, Wake-on-LAN magic packet) |
| Lock screen / Logout | Session control | Phase 3 |
| Rename computers, set startup disk | Client config | Phase 4 |

### 2.3 Software Distribution
| Feature | Behavior | OpenDesk-Admin equivalent |
|---|---|---|
| Copy items | Push files/folders to client paths | `DistributionEngine` (rsync/scp) |
| Install packages | Copy + run `installer` on .pkg | `DistributionEngine.installPackage` |
| Copy app settings/preferences | Push plist payloads | Phase 4 |

### 2.4 Reporting & Inventory
| Feature | Behavior | OpenDesk-Admin equivalent |
|---|---|---|
| Hardware overview | Model, CPU, RAM, serial, storage | `InventoryCollector` (system_profiler / IOReport) |
| Software inventory | Installed apps + versions | `InventoryCollector` (Spotlight / app dirs) |
| File search on clients | Remote find | Phase 4 |
| Usage reports | Login/uptime history | Phase 4 |

### 2.5 Fleet Management
| Feature | Behavior | OpenDesk-Admin equivalent |
|---|---|---|
| Computer lists / groups | Organize clients into rosters | `HostRegistry` + group tags |
| Saved tasks | Reusable task definitions | `TaskDefinition` (JSON, versioned) |
| Task scheduling | Run tasks on a schedule | Phase 4 (launchd or in-process scheduler) |
| Client authentication | Per-client admin credentials | SSH key or password per host |

## 3. Known ARD Weaknesses (public reports) — our advantages

1. **LAN-optimized only, poor over WAN** → we build on SSH, which tunnels cleanly over WAN/VPN.
2. **Broken/restricted tasks on modern macOS (Monterey+, Apple Silicon)** → we use supported modern APIs (`installer`, `system_profiler`, SSH) rather than legacy ARD client hooks.
3. **$79.99 per admin seat** → MIT-licensed, free.
4. **Viewer is no better than free Screen Sharing** → our differentiator is the *fleet* layer: tasks, inventory, distribution — not the pixel pipeline.

## 4. Protocol Reality

- ARD's screen control is VNC-derived (RFB protocol, RFC 6143) with Apple extensions (e.g., RectangularEncoding for tight updates).
- ARD's task/report channel is a proprietary protocol on the ARD client agent — **we do not replicate it**. We replace it with SSH + standard macOS tooling, which is more robust and auditable.
- Conclusion: OpenDesk-Admin = **RFB (open standard) for pixels + SSH (open standard) for everything else**. No proprietary protocol reimplementation required for MVP.

## 5. Out of Scope (explicitly)

- Decompiling or redistributing any Apple binary or code (see `docs/LEGAL.md`).
- Replicating ARD's proprietary admin↔client wire protocol.
- MDM-style profile management (different product category; can integrate later via `profiles` CLI).
