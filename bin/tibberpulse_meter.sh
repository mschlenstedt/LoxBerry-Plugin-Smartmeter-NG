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
# Adaptive poll interval: starts at 3 s. On a timeout or HTTP error the interval
# is raised by 2 s up to a maximum of 30 s (each raise is logged as an ERROR into
# the bridge's own LoxBerry logfile). Once it was raised, the interval is frozen
# at its current value on the next successful pull (it does not drop back).
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
#   SMARTMETER_TIBBER_INTERVAL  initial seconds between polls (default 3)
#   SMARTMETER_TIBBER_TIMEOUT   curl timeout in seconds (default 4)

set -u

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PLUGINNAME="$(basename "$SCRIPT_DIR")"
LBHOMEDIR="${SCRIPT_DIR%/bin/plugins/*}"
IRJSON="$LBHOMEDIR/config/plugins/$PLUGINNAME/irheads.json"
RUNDIR="/var/run/shm/$PLUGINNAME"
AUTO_DIR="/dev/serial/smartmeter"

MAX_INTERVAL=30
STEP=2

valid_name() { printf '%s' "${1:-}" | grep -qE '^[A-Za-z0-9_-]+$'; }
need_root()  { [ "$(id -u)" -eq 0 ] || { echo "This script must be run as root (sudo)."; exit 1; }; }

# ---------------------------------------------------------------- stop mode
if [ "${1:-}" = "stop" ]; then
	sname="${2:-}"
	valid_name "$sname" || { echo "Usage: $0 stop <name>"; exit 1; }
	need_root
	pidfile="$RUNDIR/tibberpulse-$sname.pid"
	if [ -f "$pidfile" ]; then
		pid="$(cat "$pidfile" 2>/dev/null)"
		if printf '%s' "$pid" | grep -qE '^[0-9]+$'; then
			kill "$pid" 2>/dev/null || true
			sleep 1
			kill -9 "$pid" 2>/dev/null || true
			pkill -P "$pid" 2>/dev/null || true
		fi
	fi
	rm -f "$pidfile" "$RUNDIR/tibberpulse-$sname.curl" "$RUNDIR/tibberpulse-$sname.bin" \
	      "$RUNDIR/tibberpulse-$sname.interval" "$AUTO_DIR/$sname" 2>/dev/null || true
	exit 0
fi

# ---------------------------------------------------------------- run mode
HEAD="${1:-}"
INTERVAL_INIT="${SMARTMETER_TIBBER_INTERVAL:-3}"
TIMEOUT="${SMARTMETER_TIBBER_TIMEOUT:-4}"

valid_name "$HEAD" || { echo "Usage: $0 <name>   (name of a tibberpulse head in irheads.json)"; exit 1; }
need_root
command -v curl  >/dev/null 2>&1 || { echo "curl is required";  exit 1; }
command -v socat >/dev/null 2>&1 || { echo "socat is required"; exit 1; }
command -v xxd   >/dev/null 2>&1 || { echo "xxd is required";   exit 1; }

mkdir -p "$RUNDIR"
CURLCFG="$RUNDIR/tibberpulse-$HEAD.curl"
PIDFILE="$RUNDIR/tibberpulse-$HEAD.pid"
TMPBIN="$RUNDIR/tibberpulse-$HEAD.bin"
STATEFILE="$RUNDIR/tibberpulse-$HEAD.interval"

# Read host/node/password/device from irheads.json and write the curl config
# (url + credentials) so the password never appears in the process list.
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
' "$IRJSON" "$HEAD" "$CURLCFG")" || { echo "Could not read config for '$HEAD' from $IRJSON"; exit 1; }

[ -n "$DEVICE" ] || { echo "No device configured for '$HEAD'"; exit 1; }

# Own, registered LoxBerry logfile (shows up in the Logfiles tab). The bash log
# library is not "set -u" safe, so disable nounset from here on.
set +u
LOG=""
if [ -r "$LBHOMEDIR/libs/bashlib/loxberry_log.sh" ]; then
	# shellcheck disable=SC1090
	. "$LBHOMEDIR/libs/bashlib/loxberry_log.sh"
	PACKAGE="$PLUGINNAME"
	NAME="tibberpulse_$HEAD"
	LOGDIR="$LBHOMEDIR/log/plugins/$PLUGINNAME"
	LOGLEVEL=7
	mkdir -p "$LOGDIR"
	LOGSTART "Tibber Pulse '$HEAD' bridge started (interval ${INTERVAL_INIT}s)."
	LOG="$FILENAME"
	chown loxberry:loxberry "$LOG" 2>/dev/null || true
fi

# Appends an ERROR/INFO line to the logfile (if any) with a timestamp.
logline() {
	[ -n "$LOG" ] || return 0
	printf '<%s> %s %s\n' "$1" "$(date '+%d.%m.%Y %H:%M:%S')" "$2" >> "$LOG"
}

cleanup() {
	rm -f "$PIDFILE" "$CURLCFG" "$TMPBIN" "$STATEFILE" "$DEVICE" 2>/dev/null || true
	pkill -P $$ 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo $$ > "$PIDFILE"
mkdir -p "$(dirname "$DEVICE")"
# state: "interval frozen raised"
echo "$INTERVAL_INIT 0 0" > "$STATEFILE"

# One poll. On a good SML telegram it is written to the pipe (socat -> PTY) and,
# if the interval had been raised, frozen. On a timeout / HTTP / non-SML answer
# the interval is raised by STEP up to MAX_INTERVAL (each raise logged as ERROR)
# unless already frozen. Returns non-zero only when the write pipe broke (socat
# gone), so the inner loop ends and the outer loop re-creates the device.
fetch_one() {
	read -r interval frozen raised < "$STATEFILE"
	if curl -sS --max-time "$TIMEOUT" -K "$CURLCFG" -o "$TMPBIN" 2>/dev/null \
		&& [ -s "$TMPBIN" ] \
		&& [ "$(xxd -p -l4 "$TMPBIN" 2>/dev/null)" = "1b1b1b1b" ]; then
		if [ "$raised" = "1" ] && [ "$frozen" = "0" ]; then
			echo "$interval 1 1" > "$STATEFILE"
			logline INFO "Tibber Pulse '$HEAD' wieder erreichbar; Abfrageintervall bei ${interval}s eingefroren."
		fi
		cat "$TMPBIN" || return 1
	else
		if [ "$frozen" = "0" ] && [ "$interval" -lt "$MAX_INTERVAL" ]; then
			interval=$(( interval + STEP ))
			[ "$interval" -gt "$MAX_INTERVAL" ] && interval="$MAX_INTERVAL"
			echo "$interval $frozen 1" > "$STATEFILE"
			logline ERROR "Tibber Pulse '$HEAD' Abfrage fehlgeschlagen (Timeout/HTTP); Abfrageintervall erhöht auf ${interval}s."
		fi
	fi
	return 0
}

# socat waits for a reader (wait-slave) and exits when vzLogger disconnects; the
# outer loop then re-creates the device for the next reader. The interval state
# lives in $STATEFILE, so it survives these restarts.
while true; do
	while fetch_one; do
		sleep "$(cut -d' ' -f1 "$STATEFILE" 2>/dev/null || echo "$INTERVAL_INIT")"
	done | socat -u - "PTY,link=$DEVICE,raw,echo=0,mode=0660,group=loxberry,wait-slave"
	sleep 1
done
