#!/bin/sh
# gui-launch-smoke.sh — §25 gap #25: launch the GUI executable, verify it
# stays alive, terminate, report. Usable locally and in a GUI-session CI lane.
set -eu

BIN="${1:-.build/debug/opendesk-gui}"
if [ ! -x "$BIN" ]; then
  echo "gui-launch-smoke: FAILED — $BIN not built" >&2
  exit 1
fi

"$BIN" &
PID=$!
sleep 3

if kill -0 "$PID" 2>/dev/null; then
  echo "gui-launch-smoke: alive after 3s (pid $PID)"
  kill "$PID"
  wait "$PID" 2>/dev/null || true
  echo "gui-launch-smoke: PASS (launched, stayed alive, terminated)"
  exit 0
fi
echo "gui-launch-smoke: FAILED — process exited early" >&2
exit 1
