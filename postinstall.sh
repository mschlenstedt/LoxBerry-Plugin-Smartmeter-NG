#!/bin/sh

# Bashscript which is executed by bash *AFTER* complete installation is done
# (but *BEFORE* postupdate). Use with caution and remember, that all systems
# may be different! Better to do this in your own Pluginscript if possible.
#
# Exit code must be 0 if executed successfull.
#
# Will be executed as user "loxberry".
#
# We add 5 arguments when executing the script:
# command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER>

ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

/bin/chmod +x $ARGV5/bin/plugins/$ARGV3/vzlogger_pkg.sh
/bin/chmod +x $ARGV5/bin/plugins/$ARGV3/watchdog.pl
/bin/chmod +x $ARGV5/webfrontend/htmlauth/plugins/$ARGV3/ajax.cgi
/bin/chmod +x $ARGV5/webfrontend/htmlauth/plugins/$ARGV3/usb_devices.cgi

echo "<INFO> Rename htaccess to .htaccess"
mv $ARGV5/webfrontend/htmlauth/plugins/$ARGV3/htaccess $ARGV5/webfrontend/htmlauth/plugins/$ARGV3/.htaccess

echo "<INFO> vzLogger package is installed through the plugin package helper."

echo "<INFO> ***********************************************************************"
echo "<INFO> * Please reboot your LoxBerry to initialize the Smartmeter-NG Plugin  *"
echo "<INFO> ***********************************************************************"

# Exit with Status 0
exit 0
