# Compatibility Matrix

| Host type | Remote control | Commands | Files | Packages | Inventory | Notes |
|---|---|---|---|---|---|---|
| macOS + Remote Management (ARDAgent) | RFB (ARD auth type 30) | SSH | SFTP | SFTP + installer | SSH collectors | Primary v1 target |
| macOS + SSH only | — | SSH | SFTP | SFTP + installer | SSH collectors | Headless/limited |
| macOS + OpenDesk agent (V2) | Native capture (V2+) | Agent IPC | Agent | Agent | Agent | Full capability |
| Linux VNC host | Standard RFB | SSH | SFTP | distro pkg mgr (later) | later | VNC interop |
| Windows VNC host | Standard RFB | — | — | — | — | VNC interop |
| macOS via MDM | MDM "Enable Remote Desktop" command pre-enables ARD | — | — | MDM deploy | — | Jamf/Kandji/Mosyle/Intune/generic |

## Port requirements

| Path | Ports |
|---|---|
| Remote control | TCP 5900 |
| Management (v1) | TCP 22 |
| ARD reporting interop (observe only) | TCP/UDP 3283 |
| High-performance (V2+) | UDP 5900–5902 |

## macOS version support

| Role | Minimum |
|---|---|
| Admin (OpenDesk console) | macOS 13 (SwiftPM target); recommend 15+ |
| Client via Remote Management | Per Apple ARD client requirements |
| Client via SSH | Any macOS with Remote Login enabled |
