#!/usr/bin/env bash
# Dynamic observation capture — run on the isolated Admin/Client test lab during
# ARD behavior experiments. Captures network, Unified Log, process tree, launchd.
# NO encryption bypass. Metadata observation only.
#
# Usage: sudo ./capture-experiment.sh <experiment-id> <duration-seconds>
set -euo pipefail

EXP_ID="${1:?usage: capture-experiment.sh <experiment-id> <duration-seconds>}"
DURATION="${2:-60}"
OUT="./fixtures/experiments/${EXP_ID}"
mkdir -p "$OUT"

IFACE="${IFACE:-en0}"

echo "Capturing experiment ${EXP_ID} for ${DURATION}s on ${IFACE} -> ${OUT}"

# Network metadata (ports 22/3283/5900/5901/5902)
sudo tcpdump -i "$IFACE" -w "$OUT/network.pcapng" \
  '(port 22 or port 3283 or port 5900 or port 5901 or port 5902)' &
TCPDUMP_PID=$!

# Unified Log
log stream --style json > "$OUT/unified_log.jsonl" &
LOG_PID=$!

# Process tree snapshots
( for i in $(seq 1 $((DURATION / 5))); do ps aux; echo "---"; sleep 5; done ) > "$OUT/process_tree.txt" &
PS_PID=$!

# launchd state
launchctl print system > "$OUT/launchd_system.txt" 2>/dev/null || true
launchctl print "gui/$(id -u)" > "$OUT/launchd_gui.txt" 2>/dev/null || true

sleep "$DURATION"

kill "$TCPDUMP_PID" "$LOG_PID" "$PS_PID" 2>/dev/null || true
wait 2>/dev/null || true

echo "Capture complete: $OUT"
echo "Artifacts: network.pcapng unified_log.jsonl process_tree.txt launchd_*.txt"
