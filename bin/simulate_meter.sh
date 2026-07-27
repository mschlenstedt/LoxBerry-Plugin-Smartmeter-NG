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
# The device is created under /dev/serial/smartmeter/ (the same location as the
# udev rule), so the plugin auto-detects it in the I/R heads tab. Then create an
# SML meter on it (baudrate 9600, parity 8n1); auto-discovery reads the stream on
# save.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="${SMARTMETER_SIM_DEVICE:-/dev/serial/smartmeter/SIM}"
INTERVAL="${SMARTMETER_SIM_INTERVAL:-2}"

# Must run as root: the virtual device is created under /dev.
if [ "$(id -u)" -ne 0 ]; then
	echo "This script must be run as root (sudo): the virtual device is created under /dev/serial/smartmeter/."
	exit 1
fi

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

cleanup() { pkill -P $$ 2>/dev/null || true; }
trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$DEVICE")"

echo "Simulated meter device : $DEVICE"
echo "SML dump               : $DUMP ($(wc -c < "$DUMP") bytes)"
echo "Telegram interval      : ${INTERVAL}s   (Ctrl-C to stop)"
echo
echo "The plugin auto-detects it in the I/R heads tab. Create an SML meter on it"
echo "(baudrate 9600, parity 8n1); auto-discovery reads the stream on save."
echo

# Serve the SML dump on a virtual serial device. socat waits for a reader
# (wait-slave) and exits when that reader disconnects - e.g. when vzLogger is
# restarted or stopped for OBIS discovery. The outer loop then re-creates the
# device for the next reader; the inner "while cat" ends cleanly on SIGPIPE
# (socat gone) instead of busy-looping.
while true; do
	while cat "$DUMP"; do sleep "$INTERVAL"; done \
		| socat -u - "PTY,link=$DEVICE,raw,echo=0,mode=0660,group=loxberry,wait-slave"
	sleep 1
done
