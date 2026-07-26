#!/usr/bin/perl

# AJAX endpoint for the web interface. Returns JSON. Mutating actions require
# POST. Error messages are returned as keys and localized in the browser, so
# this endpoint stays language-independent.

use strict;
use warnings;
use CGI;
use JSON::PP;
use LoxBerry::System;
# LoxBerry::System exports $lbpbindir (…/bin/plugins/<folder>), where the
# plugin's Perl modules live. It is populated at compile time by the import
# above, so the following "use lib" picks it up.
use lib $lbpbindir;
use SmartMeterIRHeads qw(sync_and_load add_manual remove_manual);

my $cgi = CGI->new;
my $q   = $cgi->Vars;
my $action    = $q->{action} || "";
my $configdir = $lbpconfigdir;

print $cgi->header(-type => "application/json", -charset => "utf-8", -expires => "now");

my $response = { ok => JSON::PP::false };

sub is_post { return (($ENV{REQUEST_METHOD} || "") eq "POST"); }

sub head_lists
{
	my $data = sync_and_load($configdir);
	return (auto => $data->{auto}, manual => $data->{manual});
}

# Probes the running vzlogger PID via the watchdog's lightweight, unlogged
# "pid" action and returns a status hash for the service block.
sub vz_status
{
	my ($rc, $out) = LoxBerry::System::execute(command => "$lbpbindir/watchdog.pl --action=pid 2>/dev/null");
	$out = "" if (!defined($out));
	my ($pid) = $out =~ /(\d+)/;
	return {
		ok      => JSON::PP::true,
		running => $pid ? JSON::PP::true : JSON::PP::false,
		pid     => $pid ? int($pid) : 0,
	};
}

# Runs a mutating watchdog service action (start/stop/restart), then returns the
# resulting status so the UI can update the badge in one round trip.
sub vz_service_action
{
	my ($what) = @_;
	LoxBerry::System::execute(command => "$lbpbindir/watchdog.pl --action=$what 2>&1");
	return vz_status();
}

# Returns the current vzlogger.conf (or its default skeleton) as a structure the
# UI can render. The MQTT connection is filled automatically by the helper.
sub vz_conf_get
{
	my ($rc, $out) = LoxBerry::System::execute(command => "$lbpbindir/vzlogger_conf.pl get 2>/dev/null");
	my $config = eval { JSON::PP->new->relaxed->decode(defined($out) ? $out : "") };
	return { ok => JSON::PP::false, error_key => "UI_AJAX_FAILED" } if ($@ || ref($config) ne "HASH");
	return { ok => JSON::PP::true, config => $config };
}

if ($action eq "irheads-list") {
	$response = { ok => JSON::PP::true, head_lists() };
}
elsif ($action eq "irheads-add") {
	if (!is_post()) {
		$response = { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
	}
	else {
		my ($ok, $err) = add_manual($configdir, $q->{device}, $q->{name});
		$response = { ok => $ok ? JSON::PP::true : JSON::PP::false, error_key => $err, head_lists() };
	}
}
elsif ($action eq "irheads-remove") {
	if (!is_post()) {
		$response = { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
	}
	else {
		my ($ok, $err) = remove_manual($configdir, $q->{device});
		$response = { ok => $ok ? JSON::PP::true : JSON::PP::false, error_key => $err, head_lists() };
	}
}
elsif ($action eq "vz-status") {
	$response = vz_status();
}
elsif ($action eq "vz-restart") {
	$response = is_post() ? vz_service_action("restart") : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vz-stop") {
	$response = is_post() ? vz_service_action("stop") : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vzconf-get") {
	$response = vz_conf_get();
}
else {
	$response = { ok => JSON::PP::false, error_key => "UI_UNKNOWN_ACTION" };
}

print JSON::PP->new->utf8->canonical->encode($response);
exit;
