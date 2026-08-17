#!/bin/sh

# Bash script which is executed in case of an update (if this plugin is already
# installed on the system). This script is executed as very first step (*BEFORE*
# preinstall.sh) and can be used e.g. to save existing configfiles to /tmp 
# during installation. Use with caution and remember, that all systems may be
# different!
#
# Exit code must be 0 if executed successfully.
#
# Will be executed as user "loxberry".
#
# We add 5 arguments when executing the script:
# command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER>
#
# For logging, print to STDOUT. You can use the following tags for showing
# different colorized information during plugin installation:
#
# <OK> This was ok!"
# <INFO> This is just for your information."
# <WARNING> This is a warning!"
# <ERROR> This is an error!"
# <FAIL> This is a fail!"

# To use important variables from command line use the following code:
ARGV0=$0 # Zero argument is shell command
#echo "<INFO> Command is: $ARGV0"

ARGV1=$1 # First argument is temp folder during install
#echo "<INFO> Temporary folder is: $ARGV1"

ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
#echo "<INFO> (Short) Name is: $ARGV2"

ARGV3=$3 # Third argument is Plugin installation folder
#echo "<INFO> Installation folder is: $ARGV3"

ARGV4=$4 # Forth argument is Plugin version
#echo "<INFO> Installation folder is: $ARGV4"

ARGV5=$5 # Fifth argument is Base folder of LoxBerry
#echo "<INFO> Installation folder is: $ARGV5"

WATCHDOG="$ARGV5/bin/plugins/$ARGV3/watchdog.pl"

# Stop vzlogger before purge_installation() deletes the plugin directories and
# the new files are copied in, so nothing is replaced under a running process.
# postroot.sh starts it again at the end of the installation.
#
# Ended through the watchdog's own PID probe rather than --action=stop: that
# action writes the manual stop marker, which would make the upgrade look like a
# deliberate stop and leave vzlogger down for good afterwards (issue #4).
if [ -x "$WATCHDOG" ]; then
	echo "<INFO> Stopping vzlogger for the upgrade"
	PID=$("$WATCHDOG" --action=pid 2>/dev/null | tr -dc '0-9')
	if [ -n "$PID" ]; then
		kill -TERM "$PID" 2>/dev/null
		i=0
		while [ "$i" -lt 20 ] && [ -d "/proc/$PID" ]; do
			sleep 0.25
			i=$((i + 1))
		done
		if [ -d "/proc/$PID" ]; then
			kill -KILL "$PID" 2>/dev/null
		fi
	fi
fi

echo "<INFO> Creating temporary folders for upgrading"
mkdir -p /tmp/$ARGV1\_upgrade
mkdir -p /tmp/$ARGV1\_upgrade/config
mkdir -p /tmp/$ARGV1\_upgrade/log

echo "<INFO> Backing up existing config files"
cp -v -r $ARGV5/config/plugins/$ARGV3/ /tmp/$ARGV1\_upgrade/config

echo "<INFO> Backing up existing log files"
cp -v -r $ARGV5/log/plugins/$ARGV3/ /tmp/$ARGV1\_upgrade/log

# Exit with Status 0
exit 0
