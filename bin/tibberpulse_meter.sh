#!/bin/bash

# Bridges a Tibber Pulse (IR head + WLAN bridge) to a virtual serial device so
# vzLogger can read it like a normal reading head.
#
# The bridge's local webserver returns one transport-framed SML telegram
# (1b1b1b1b… start, CRC16/X.25) per request at
#   http://admin:<password>@<host>/data.json?node_id=<node>
# This script polls that URL with curl and feeds the raw telegrams into a socat
# PTY under /dev/serial/smartmeter/<name>.
#
# Usage:
#   sudo ./tibberpulse_meter.sh <name>          run the bridge (foreground loop)
#   sudo ./tibberpulse_meter.sh stop <name>     stop a running bridge
#
# <name> refers to a manual head of type "tibberpulse" in config/irheads.json;
# host, node, password and device are read from there. Must run as root (the
# device lives under /dev). One instance per configured Tibber Pulse; started by
# the watchdog (boot / restart / check) and on add via the web interface.
#
# Env overrides (run mode):
#   SMARTMETER_TIBBER_INTERVAL  seconds between polls (default 2)
#   SMARTMETER_TIBBER_TIMEOUT   curl timeout in seconds (default 4)

set -u

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PLUGINNAME="$(basename "$SCRIPT_DIR")"
LBHOMEDIR="${SCRIPT_DIR%/bin/plugins/*}"
IRJSON="$LBHOMEDIR/config/plugins/$PLUGINNAME/irheads.json"
RUNDIR="/var/run/shm/$PLUGINNAME"
AUTO_DIR="/dev/serial/smartmeter"

valid_name() { printf '%s' "${1:-}" | grep -qE '^[A-Za-z0-9_-]+$'; }
need_root()  { [ "$(id -u)" -eq 0 ] || { echo "This script must be run as root (sudo)."; exit 1; }; }

# ---------------------------------------------------------------- stop mode
if [ "${1:-}" = "stop" ]; then
	NAME="${2:-}"
	valid_name "$NAME" || { echo "Usage: $0 stop <name>"; exit 1; }
	need_root
	PIDFILE="$RUNDIR/tibberpulse-$NAME.pid"
	if [ -f "$PIDFILE" ]; then
		pid="$(cat "$PIDFILE" 2>/dev/null)"
		if printf '%s' "$pid" | grep -qE '^[0-9]+$'; then
			# SIGTERM triggers the run-mode cleanup trap (removes device/socat).
			kill "$pid" 2>/dev/null || true
			sleep 1
			kill -9 "$pid" 2>/dev/null || true
			pkill -P "$pid" 2>/dev/null || true
		fi
	fi
	rm -f "$PIDFILE" "$RUNDIR/tibberpulse-$NAME.curl" "$RUNDIR/tibberpulse-$NAME.bin" "$AUTO_DIR/$NAME" 2>/dev/null || true
	exit 0
fi

# ---------------------------------------------------------------- run mode
NAME="${1:-}"
INTERVAL="${SMARTMETER_TIBBER_INTERVAL:-2}"
TIMEOUT="${SMARTMETER_TIBBER_TIMEOUT:-4}"

valid_name "$NAME" || { echo "Usage: $0 <name>   (name of a tibberpulse head in irheads.json)"; exit 1; }
need_root
command -v curl  >/dev/null 2>&1 || { echo "curl is required";  exit 1; }
command -v socat >/dev/null 2>&1 || { echo "socat is required"; exit 1; }
command -v xxd   >/dev/null 2>&1 || { echo "xxd is required";   exit 1; }

mkdir -p "$RUNDIR"
CURLCFG="$RUNDIR/tibberpulse-$NAME.curl"
PIDFILE="$RUNDIR/tibberpulse-$NAME.pid"
TMPBIN="$RUNDIR/tibberpulse-$NAME.bin"

# Read host/node/password/device for this head from irheads.json and write the
# curl config (url + credentials) so the password never appears in the process
# list. Perl escapes the password for the curl config file format. Prints the
# device path on stdout.
DEVICE="$(perl -MJSON::PP -e '
	local $/; open(my $fh, "<", $ARGV[0]) or exit 2;
	my $d = eval { decode_json(<$fh>) }; exit 2 if (!$d || ref($d->{manual}) ne "ARRAY");
	my ($m) = grep { ref($_) eq "HASH" && ($_->{type} // "") eq "tibberpulse" && ($_->{name} // "") eq $ARGV[1] } @{$d->{manual}};
	exit 3 if (!$m);
	my $host = $m->{host} // ""; my $node = $m->{node} // "1";
	my $pw = $m->{password} // ""; my $dev = $m->{device} // "";
	exit 4 if ($host eq "" || $dev eq "");
	$pw =~ s/([\\"])/\\$1/g;
	open(my $c, ">", $ARGV[2]) or exit 5; chmod(0600, $ARGV[2]);
	print $c "url = \"http://$host/data.json?node_id=$node\"\n";
	print $c "user = \"admin:$pw\"\n";
	close($c);
	print $dev;
' "$IRJSON" "$NAME" "$CURLCFG")" || { echo "Could not read config for '$NAME' from $IRJSON"; exit 1; }

[ -n "$DEVICE" ] || { echo "No device configured for '$NAME'"; exit 1; }

cleanup() {
	rm -f "$PIDFILE" "$CURLCFG" "$TMPBIN" "$DEVICE" 2>/dev/null || true
	pkill -P $$ 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo $$ > "$PIDFILE"
mkdir -p "$(dirname "$DEVICE")"

# One poll: fetch a telegram; only forward it if it is a framed SML stream
# (starts with 1b1b1b1b), so an error page (e.g. wrong credentials -> 401) is
# never fed into the PTY. Returns non-zero only when the write pipe broke (socat
# gone), so the inner loop ends and the outer loop re-creates the device.
fetch_one() {
	curl -sS --max-time "$TIMEOUT" -K "$CURLCFG" -o "$TMPBIN" 2>/dev/null || return 0
	[ -s "$TMPBIN" ] || return 0
	[ "$(xxd -p -l4 "$TMPBIN" 2>/dev/null)" = "1b1b1b1b" ] || return 0
	cat "$TMPBIN" || return 1
	return 0
}

# socat waits for a reader (wait-slave) and exits when vzLogger disconnects; the
# outer loop then re-creates the device for the next reader.
while true; do
	while fetch_one; do sleep "$INTERVAL"; done \
		| socat -u - "PTY,link=$DEVICE,raw,echo=0,mode=0660,group=loxberry,wait-slave"
	sleep 1
done
