# Getting Started

A complete walkthrough: one admin Mac, one or more client Macs.

## Prerequisites

| Machine | Requirement |
|---|---|
| Admin Mac | macOS 13+, Xcode or Swift toolchain to build |
| Client Macs | macOS 13+ (admin account credentials known), on a reachable network |

## 1. Build the admin tools (admin Mac)

```bash
git clone <repo-url>
cd OpenDeskAdmin
swift build -c release
```

Optionally install the CLI on your PATH:

```bash
sudo cp .build/release/opendesk /usr/local/bin/
```

Or build the GUI app bundle: `./scripts/build-app.sh release` → `.build/OpenDesk Admin.app`.

## 2. Prepare each client Mac (one time, per client)

On the **client** Mac, run:

```bash
./scripts/setup-client.sh
```

This enables Remote Login (SSH) and Screen Sharing using Apple's own
first-party tooling. If you want legacy VNC password auth (needed for
`opendesk observe` / GUI screen viewing with a password), use:

```bash
./scripts/setup-client.sh --vnc-password "your-strong-password"
```

## 3. Register clients (admin Mac)

```bash
opendesk hosts add lab-mac-01.local adminuser --groups lab-1
opendesk hosts add lab-mac-02.local adminuser --groups lab-1
opendesk hosts list
```

SSH key auth is used by default (`BatchMode=yes`). Make sure your admin
Mac's SSH key is authorized on the clients (`ssh-copy-id adminuser@lab-mac-01.local`).

## 4. Run tasks

```bash
# One-off command
opendesk task run --host lab-mac-01.local --command "sw_vers"

# Whole group
opendesk task run --groups lab-1 --command "uptime"

# Power tasks
opendesk task sleep --host lab-mac-01.local

# Wake a sleeping client (needs its MAC address registered on the host entry)
opendesk wake --host lab-mac-01.local
```

## 5. Saved + scheduled tasks

```bash
opendesk tasks add collect-os --command "sw_vers" --timeout 30
opendesk schedule add morning-report --task collect-os --groups lab-1 --daily 09:00
opendesk schedule list
opendesk schedule run-now morning-report

# Keep schedules running in the foreground (or install the launchd wrapper
# scripts/com.opendesk.schedule-daemon.plist for boot persistence)
opendesk schedule daemon
```

## 6. Inventory & reports

```bash
opendesk inventory --local
opendesk inventory --host lab-mac-01.local
opendesk inventory --local --export-csv fleet.csv
```

## 7. Software distribution

```bash
# Copy a file
opendesk copy --host lab-mac-01.local --local ./installer.dmg --remote /tmp/installer.dmg

# Install a package
opendesk install --host lab-mac-01.local --pkg ./MyAgent.pkg

# Push a preference payload
# (DistributionEngine.pushPlist — GUI/API path; defaults import over SSH)
```

## 8. Screen observation & control

Requirements: the client has Screen Sharing on (step 2) and, if a VNC
password is set, you know it.

```bash
# Protocol check
opendesk observe --host lab-mac-01.local --password "your-strong-password"

# WAN / VPN: tunnel the screen session over SSH
opendesk tunnel --host lab-mac-01.local
# → connect the viewer to 127.0.0.1:<printed port>
```

In the GUI: open `OpenDesk Admin.app` → Screen tab → **Open Screen Viewer**
(live stream; toggle **Control** to inject keyboard/mouse). For several
Macs at once, open the **Tiled Observation** window and add hosts to the grid.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `host unreachable` | SSH off on client, DNS, or firewall — run setup-client.sh |
| `authentication failed` | SSH key not authorized on client, or wrong VNC password |
| `authenticationFailed` from observe | Client requires a VNC password; pass `--password` |
| Screen shows but no updates | Client screen asleep; wake it first |
| Task runs, exit code 255 | BatchMode SSH: check `ssh -v user@host` |
