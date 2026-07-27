#!/bin/bash

# Test helper: simulates a serial SML meter without real hardware.
#
# Creates a virtual serial device with socat and feeds a captured SML dump
# (data/sample.dmp) into it in a loop, so vzLogger reads it like a real reading
# head. NOT wired into the web UI - run it by hand while testing.
#
# Usage:
#   sudo ./simulate_meter.sh [DUMPFILE]
#
# Env overrides:
#   SMARTMETER_SIM_DEVICE   device path to expose (default /dev/ttySmartmeterSim)
#   SMARTMETER_SIM_INTERVAL seconds between telegrams (default 2)
#
# Then, in the plugin:
#   1. I/R heads tab -> add a manual head with the printed device path.
#   2. Smartmeter tab -> add an SML meter on it (baudrate 9600, parity 8n1).
#      Auto-discovery reads the simulated stream on save.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="${SMARTMETER_SIM_DEVICE:-/dev/ttySmartmeterSim}"
INTERVAL="${SMARTMETER_SIM_INTERVAL:-2}"

# Locate the SML dump: explicit argument, installed data dir, or repo checkout.
DUMP="${1:-}"
if [ -z "$DUMP" ]; then
	for candidate in \
		"${SCRIPT_DIR/\/bin\/plugins\//\/data\/plugins\/}/sample.dmp" \
		"$SCRIPT_DIR/../data/sample.dmp"
	do
		[ -r "$candidate" ] && DUMP="$candidate" && break
	done
fi

command -v socat >/dev/null 2>&1 || { echo "socat is required: sudo apt-get install socat"; exit 1; }
[ -n "$DUMP" ] && [ -r "$DUMP" ] || { echo "SML dump not found. Pass the dump file as an argument."; exit 1; }

FEED="$(mktemp -u /tmp/smartmeter-sim.XXXXXX)"
SOCAT_PID=""
cleanup() { [ -n "$SOCAT_PID" ] && kill "$SOCAT_PID" 2>/dev/null || true; rm -f "$FEED"; }
trap cleanup EXIT INT TERM

echo "Simulated meter device : $DEVICE"
echo "SML dump               : $DUMP ($(wc -c < "$DUMP") bytes)"
echo "Telegram interval      : ${INTERVAL}s   (Ctrl-C to stop)"
echo
echo "In the plugin: add a manual I/R head with device '$DEVICE', then create an"
echo "SML meter on it (baudrate 9600, parity 8n1)."
echo

# Persistent virtual serial pair: bytes written to $FEED appear on $DEVICE, which
# is made readable for the loxberry user (vzLogger runs as loxberry).
socat PTY,link="$FEED",raw,echo=0 PTY,link="$DEVICE",raw,echo=0,mode=0660,group=loxberry &
SOCAT_PID=$!
sleep 1

while true; do
	cat "$DUMP" > "$FEED"
	sleep "$INTERVAL"
done
