#!/usr/bin/perl

# Popup that shows the connected USB devices (lsusb). Opened in a separate
# window from the I/R reading heads tab. Uses "nopanels" as the second
# lbheader() argument so the page renders without the LoxBerry menu, like the
# MultiIO i2c scan popup.

use strict;
use warnings;
use LoxBerry::System;
use LoxBerry::Web;

my $version = LoxBerry::System::pluginversion();

my $maintemplate = HTML::Template->new(
	filename          => "$lbptemplatedir/usb_devices.html",
	global_vars       => 1,
	loop_context_vars => 1,
	die_on_bad_params => 0,
);
my %L = LoxBerry::System::readlanguage($maintemplate, "language.ini");

LoxBerry::Web::lbheader($L{'COMMON.PLUGIN_TITLE'} . " V$version", "nopanels", "");

my (undef, $lsusb) = execute(command => "lsusb");
my (undef, $lsusb_tree) = execute(command => "lsusb -t");

$maintemplate->param(LSUSB => $lsusb);
$maintemplate->param(LSUSB_TREE => $lsusb_tree);

print $maintemplate->output();
exit;
