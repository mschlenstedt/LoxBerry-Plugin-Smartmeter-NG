#!/bin/bash

# Test helper: simulates a serial SML meter without real hardware.
#
# Creates a virtual serial device with socat and feeds a captured SML dump
# (data/sample.dmp) into it in a loop, so vzLogger reads it like a real reading
# head. NOT wired into the web UI - run it by hand while testing.
#
# Usage:
#   sudo ./simulate_meter.sh [DUMP]
#
#   DUMP may be:
#     - omitted            -> the default sample (data/sample.dmp)
#     - a bare filename    -> looked up in data/testdata/ (also tries <name>.bin),
#                             e.g. ISKRA_MT631-D2A51-V22-K0z_without_PIN.bin
#     - an absolute or relative path to any SML dump file
#
# Env overrides:
#   SMARTMETER_SIM_DEVICE   device path to expose (default /dev/serial/smartmeter/SIM)
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

# Resolve the plugin data dir (installed under $lbhomedir/data/plugins, or the
# repo checkout's data/) and the bundled test-data directory.
DATA_DIR=""
for d in \
	"${SCRIPT_DIR/\/bin\/plugins\//\/data\/plugins\/}" \
	"$SCRIPT_DIR/../data"
do
	[ -d "$d" ] && DATA_DIR="$d" && break
done
TESTDATA_DIR="$DATA_DIR/testdata"

# Locate the SML dump to feed (see the Usage note above).
ARG="${1:-}"
if [ -z "$ARG" ]; then
	DUMP="$DATA_DIR/sample.dmp"
elif [ "$ARG" = "$(basename "$ARG")" ] && [ -r "$TESTDATA_DIR/$ARG" ]; then
	DUMP="$TESTDATA_DIR/$ARG"
elif [ "$ARG" = "$(basename "$ARG")" ] && [ -r "$TESTDATA_DIR/$ARG.bin" ]; then
	DUMP="$TESTDATA_DIR/$ARG.bin"
else
	DUMP="$ARG"
fi

command -v socat >/dev/null 2>&1 || { echo "socat is required: sudo apt-get install socat"; exit 1; }
if [ -z "$DUMP" ] || [ ! -r "$DUMP" ]; then
	echo "SML dump not found: '${ARG:-<default sample>}'"
	if [ -d "$TESTDATA_DIR" ]; then
		echo "Available test dumps in $TESTDATA_DIR:"
		ls -1 "$TESTDATA_DIR" | grep -iv '\.md$' | sed 's/^/  /'
	fi
	exit 1
fi

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
