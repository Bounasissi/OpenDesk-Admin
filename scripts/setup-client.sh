#!/bin/bash
# OpenDesk-Admin client provisioning — run ONCE on each client Mac.
#
# Prepares a Mac to be administered by OpenDesk-Admin:
#   1. Enables Remote Login (SSH)
#   2. Enables Screen Sharing (VNC/RFB)
#   3. Confirms the admin account can SSH in
#
# macOS handles the client services natively (no client agent needed).
# Run with sudo. Tested on macOS 13+ incl. Apple Silicon.
#
# Optional VNC password (legacy VNC clients / OpenDesk observe):
#   ./scripts/setup-client.sh --vnc-password "yourpassword"
#
#   NOTE: sets VNC legacy auth on this machine. Use a strong password;
#   VNC auth is not a secure channel on its own — prefer SSH tunnels
#   (opendesk tunnel) for WAN use.
set -euo pipefail

VNC_PASSWORD=""
if [[ "${1:-}" == "--vnc-password" ]]; then
  VNC_PASSWORD="${2:?--vnc-password requires a value}"
fi

echo "==> Enabling Remote Login (SSH)…"
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate -configure -allowAccessFor -specifiedUsers 2>/dev/null || true

sudo systemsetup -setremotelogin on >/dev/null 2>&1 || {
  echo "   (systemsetup needs Full Disk Access for the shell — trying launchctl)"
  sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist >/dev/null 2>&1 || true
}

echo "==> Enabling Screen Sharing…"
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true

if [[ -n "$VNC_PASSWORD" ]]; then
  echo "==> Setting VNC legacy password…"
  # Uses kickstart (first-party tooling) to set VNC legacy auth.
  sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
    -configure -clientopts -setvnclegacy -vnclegacy yes \
    -setvncpw -vncpw "$VNC_PASSWORD"
fi

echo "==> Verifying services…"
SSH_ON=$(sudo systemsetup -getremotelogin 2>/dev/null | grep -c "On" || true)
SCREEN_ON=$(sudo launchctl list com.apple.screensharing >/dev/null 2>&1 && echo 1 || echo 0)
echo "   SSH: ${SSH_ON}   Screen Sharing: ${SCREEN_ON}"

if [[ "$SSH_ON" -ge 1 && "$SCREEN_ON" -ge 1 ]]; then
  echo "✅ Client ready. On the admin Mac run:"
  echo "   opendesk hosts add $(hostname) <admin-username>"
else
  echo "⚠️  Some services did not enable — check manually in System Settings > General > Sharing."
  exit 1
fi
