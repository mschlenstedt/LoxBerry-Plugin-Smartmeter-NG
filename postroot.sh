#!/bin/sh

# Runs as root after LoxBerry has installed dependencies and executed the
# normal postinstall/postupgrade scripts. Installs vzlogger, sets up the I/R
# head udev rule, and (re)starts vzlogger through the plugin watchdog. The
# generated vzlogger.conf is the single source of truth; the watchdog only
# starts vzlogger when that file has an enabled meter.

ARGV3=$3
ARGV5=$5

PACKAGE_HELPER="$ARGV5/bin/plugins/$ARGV3/vzlogger_pkg.sh"
WATCHDOG="$ARGV5/bin/plugins/$ARGV3/watchdog.pl"
SMARTMETER_LOG_DIR="$ARGV5/log/plugins/$ARGV3"
SMARTMETER_LOG_FILE="$SMARTMETER_LOG_DIR/smartmeter.log"
SMARTMETER_UDEV_RULE="/etc/udev/rules.d/99-smartmeter.rules"
RUNTIME_DIR="/var/run/shm/$ARGV3"
PLUGIN_CONFIG_DIR="$ARGV5/config/plugins/$ARGV3"
VZLOGGER_CONFIG="$PLUGIN_CONFIG_DIR/vzlogger.conf"

if [ "$(id -u)" != "0" ]; then
	echo "<ERROR> postroot.sh must run as root."
	exit 2
fi

# Record whether vzlogger was already present before the plugin installed it.
# This must be decided *before* the package helper runs below. The uninstall
# script reads this marker and only purges vzlogger and removes the Volkszaehler
# apt repository when the plugin was the one that installed it. An existing
# marker (from an earlier plugin install) is deliberately kept, so plugin
# ownership survives upgrades.
MARKER_FILE="$PLUGIN_CONFIG_DIR/vzlogger.installed-by-plugin"
mkdir -p "$PLUGIN_CONFIG_DIR"
if dpkg-query -W -f='${Status}' vzlogger 2>/dev/null | grep -q "install ok installed"; then
	echo "<INFO> vzlogger is already installed. It will be kept on uninstall."
else
	touch "$MARKER_FILE"
	echo "<INFO> Marked vzlogger for plugin-managed installation."
fi
chown -R loxberry:loxberry "$PLUGIN_CONFIG_DIR" 2>/dev/null || true

# vzlogger is installed here rather than through dpkg/apt so the plugin owns
# the apt call: the packaged service is kept from starting and is disabled
# afterwards, because the plugin runs vzlogger from its own watchdog.
if [ -x "$PACKAGE_HELPER" ]; then
	chmod +x "$PACKAGE_HELPER" 2>/dev/null || true
	if ! "$PACKAGE_HELPER" install; then
		echo "<WARNING> Could not install vzlogger. Use the update button on the plugin page to retry."
	fi
else
	echo "<ERROR> vzlogger package helper is missing: $PACKAGE_HELPER"
fi

install_ir_head_udev_rule()
{
	mkdir -p "$SMARTMETER_LOG_DIR"

	echo "<INFO> Installing SmartMeter I/R head udev rule."
	echo "$(date) - Creating UDEV rule for I/R heads: $SMARTMETER_UDEV_RULE" >>"$SMARTMETER_LOG_FILE"
	printf '%s\n' "# LoxBerry SML-eMon Plugin device rule file - DO NOT EDIT BY HAND!" >"$SMARTMETER_UDEV_RULE"
	printf '%s\n' "KERNEL==\"ttyUSB[0-9]*\",GROUP=\"loxberry\",MODE=\"0660\",SYMLINK+=\"serial/smartmeter/\$env{ID_SERIAL_SHORT}\"" >>"$SMARTMETER_UDEV_RULE"

	if command -v udevadm >/dev/null 2>&1; then
		echo "$(date) - Reload udev rules and trigger devices." >>"$SMARTMETER_LOG_FILE"
		if udevadm control --reload-rules >>"$SMARTMETER_LOG_FILE" 2>&1 && udevadm trigger >>"$SMARTMETER_LOG_FILE" 2>&1; then
			echo "<INFO> SmartMeter I/R head udev rule installed and triggered."
		else
			echo "<WARNING> SmartMeter I/R head udev rule was written, but udev reload/trigger failed."
		fi
	else
		echo "<WARNING> udevadm is not available. SmartMeter I/R head rule was written but not triggered."
	fi
}

install_ir_head_udev_rule
mkdir -p "$RUNTIME_DIR"
chown loxberry:loxberry "$RUNTIME_DIR"
chmod 0750 "$RUNTIME_DIR"
find "$RUNTIME_DIR" -maxdepth 1 -type f -exec chown loxberry:loxberry {} \; -exec chmod 0640 {} \;

# vzlogger runs as loxberry from the watchdog, so the generated configuration
# must be owned by loxberry.
if [ -f "$VZLOGGER_CONFIG" ]; then
	chown loxberry:loxberry "$VZLOGGER_CONFIG"
	chmod 0640 "$VZLOGGER_CONFIG"
fi

# Start (or restart) vzlogger through the watchdog. The watchdog only starts it
# when vzlogger.conf has an enabled meter; otherwise it just ensures that no
# vzlogger process is left running.
if [ -x "$WATCHDOG" ]; then
	su loxberry -c "$WATCHDOG --action=restart" >/dev/null 2>&1 || true
	echo "<INFO> vzlogger watchdog invoked (starts only if a meter is enabled)."
fi

exit 0
