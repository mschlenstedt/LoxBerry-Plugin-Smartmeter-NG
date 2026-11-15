#!/bin/bash

# Bridges a Tibber Pulse (IR head + WLAN bridge) to a virtual serial device so
# vzLogger can read it like a normal reading head.
#
# The bridge's local webserver returns one transport-framed SML telegram
# (1b1b1b1b… start, CRC16/X.25) per request at
#   http://admin:<password>@<host>/node_data.json?node_id=<node>  (newer firmware)
#   http://admin:<password>@<host>/data.json?node_id=<node>       (older firmware)
# This script polls that URL with curl and feeds the raw telegrams into a socat
# PTY under /dev/serial/smartmeter/<name>.
#
# Both paths are accepted: the first good answer fixes the path for this run.
# If that path stops answering with SML while the bridge itself still answers
# (a firmware update changed it), the other path is tried and taken over.
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

# Prints <pid> and all its descendants, one per line, children first.
proc_tree() {
	local c
	for c in $(pgrep -P "$1"); do proc_tree "$c"; done
	echo "$1"
}

# Kills a bridge with everything it started: the poll loop subshell, socat and
# a curl/sleep in flight. Killing only the script left them behind as orphans
# (re-parented to init, out of reach of "pkill -P"), polling on and holding the
# device. The tree is frozen first, so nothing can be spawned between listing
# and killing; the listing is repeated until it no longer changes.
stop_tree() {
	local pids prev=""
	while :; do
		pids="$(proc_tree "$1")"
		[ "$pids" = "$prev" ] && break
		# shellcheck disable=SC2086
		kill -STOP $pids 2>/dev/null || true
		prev="$pids"
	done
	# shellcheck disable=SC2086
	kill -KILL $pids 2>/dev/null || true
}

# ---------------------------------------------------------------- stop mode
if [ "${1:-}" = "stop" ]; then
	sname="${2:-}"
	valid_name "$sname" || { echo "Usage: $0 stop <name>"; exit 1; }
	need_root
	pidfile="$RUNDIR/tibberpulse-$sname.pid"
	if [ -f "$pidfile" ]; then
		pid="$(cat "$pidfile" 2>/dev/null)"
		# Only a live bridge process: a stale PID may have been reused.
		if printf '%s' "$pid" | grep -qE '^[0-9]+$' \
			&& tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'tibberpulse_meter\.sh'; then
			stop_tree "$pid"
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

# Data paths of the bridge, newest firmware first (see header).
BRIDGE_PATHS="node_data.json data.json"

# Read host/node/password/device from irheads.json and write the curl config
# (credentials only) so the password never appears in the process list.
CONF="$(perl -MJSON::PP -e '
	local $/; open(my $fh, "<", $ARGV[0]) or exit 2;
	my $d = eval { decode_json(<$fh>) }; exit 2 if (!$d || ref($d->{manual}) ne "ARRAY");
	my ($m) = grep { ref($_) eq "HASH" && ($_->{type} // "") eq "tibberpulse" && ($_->{name} // "") eq $ARGV[1] } @{$d->{manual}};
	exit 3 if (!$m);
	my $host = $m->{host} // ""; my $node = $m->{node} // "1";
	my $pw = $m->{password} // ""; my $dev = $m->{device} // "";
	exit 4 if ($host eq "" || $dev eq "" || $host =~ /[\s\/]/ || $node !~ /\A\d+\z/);
	$pw =~ s/([\\"])/\\$1/g;
	open(my $c, ">", $ARGV[2]) or exit 5; chmod(0600, $ARGV[2]);
	print $c "user = \"admin:$pw\"\n";
	close($c);
	print "$dev\t$host\t$node";
' "$IRJSON" "$HEAD" "$CURLCFG")" || { echo "Could not read config for '$HEAD' from $IRJSON"; exit 1; }
IFS=$'\t' read -r DEVICE HOST NODE <<< "$CONF"

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
# INT/TERM must end the script: a handler that only cleaned up let the loop run
# on without its PID file, so the watchdog started a second bridge beside it.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo $$ > "$PIDFILE"
mkdir -p "$(dirname "$DEVICE")"
# state: "interval frozen raised path" (path "-" = not yet known)
echo "$INTERVAL_INIT 0 0 -" > "$STATEFILE"

# Fetches <path> once into $TMPBIN. Sets POLL_CODE to the HTTP status ("000" on
# timeout / connection error). Succeeds only on HTTP 200 with an SML telegram.
poll() {
	POLL_CODE="$(curl -sS --max-time "$TIMEOUT" -K "$CURLCFG" -o "$TMPBIN" -w '%{http_code}' \
		"http://$HOST/$1?node_id=$NODE" 2>/dev/null)"
	[ "$POLL_CODE" = "200" ] && [ -s "$TMPBIN" ] \
		&& [ "$(xxd -p -l4 "$TMPBIN" 2>/dev/null)" = "1b1b1b1b" ]
}

# One poll. The known data path is asked first; if the bridge answers but not
# with SML there, the other path is tried (unreachable bridge or 401: no point,
# the path is not the problem). On a good SML telegram it is written to the
# pipe (socat -> PTY) and, if the interval had been raised, frozen. Otherwise
# the interval is raised by STEP up to MAX_INTERVAL (each raise logged as ERROR)
# unless already frozen. Returns non-zero only when the write pipe broke (socat
# gone), so the inner loop ends and the outer loop re-creates the device.
fetch_one() {
	read -r interval frozen raised path < "$STATEFILE"
	local candidates p ok=""
	if [ "${path:--}" = "-" ]; then
		candidates="$BRIDGE_PATHS"
	else
		candidates="$path $(printf '%s\n' $BRIDGE_PATHS | grep -vxF "$path" | tr '\n' ' ')"
	fi
	for p in $candidates; do
		if poll "$p"; then ok="$p"; break; fi
		case "$POLL_CODE" in 000|401) break ;; esac
	done
	if [ -n "$ok" ]; then
		if [ "$ok" != "${path:--}" ]; then
			if [ "${path:--}" = "-" ]; then
				logline INFO "Tibber Pulse '$HEAD' liefert Daten unter /$ok."
			else
				logline INFO "Tibber Pulse '$HEAD' liefert unter /$path keine Daten mehr, aber unter /$ok; Abfragepfad umgestellt."
			fi
			path="$ok"
		fi
		if [ "$raised" = "1" ] && [ "$frozen" = "0" ]; then
			frozen=1
			logline INFO "Tibber Pulse '$HEAD' wieder erreichbar; Abfrageintervall bei ${interval}s eingefroren."
		fi
		echo "$interval $frozen $raised $path" > "$STATEFILE"
		cat "$TMPBIN" || return 1
	else
		if [ "$frozen" = "0" ] && [ "$interval" -lt "$MAX_INTERVAL" ]; then
			interval=$(( interval + STEP ))
			[ "$interval" -gt "$MAX_INTERVAL" ] && interval="$MAX_INTERVAL"
			echo "$interval $frozen 1 ${path:--}" > "$STATEFILE"
			logline ERROR "Tibber Pulse '$HEAD' Abfrage fehlgeschlagen (HTTP $POLL_CODE); Abfrageintervall erhöht auf ${interval}s."
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
