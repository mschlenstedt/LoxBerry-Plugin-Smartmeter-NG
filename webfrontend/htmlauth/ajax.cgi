#!/usr/bin/perl

# AJAX endpoint for the web interface. Returns JSON. Mutating actions require
# POST. Error messages are returned as keys and localized in the browser, so
# this endpoint stays language-independent.

use strict;
use warnings;
use CGI;
use JSON::PP;
use File::Temp qw(tempfile);
use LoxBerry::System;
# LoxBerry::System exports $lbpbindir (…/bin/plugins/<folder>), where the
# plugin's Perl modules live. It is populated at compile time by the import
# above, so the following "use lib" picks it up.
use lib $lbpbindir;
use SmartMeterIRHeads qw(sync_and_load load_data add_manual add_tibberpulse remove_manual);

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
	# Never expose the Tibber Pulse password to the browser.
	my @manual = map { my %e = %$_; delete $e{password}; \%e } @{$data->{manual}};
	return (auto => $data->{auto}, manual => \@manual);
}

# Launches / stops a Tibber Pulse bridge as root (whitelisted in sudoers). The
# start is detached (setsid) because the bridge runs a foreground poll loop.
sub tibberpulse_start
{
	my ($name) = @_;
	return if (($name // "") !~ /\A[A-Za-z0-9_-]+\z/);
	system("setsid sudo -n $lbpbindir/tibberpulse_meter.sh $name </dev/null >/dev/null 2>&1 &");
}

sub tibberpulse_stop
{
	my ($name) = @_;
	return if (($name // "") !~ /\A[A-Za-z0-9_-]+\z/);
	system("sudo", "-n", "$lbpbindir/tibberpulse_meter.sh", "stop", $name);
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

# Reads the current per-channel values from vzLogger's local httpd and returns
# them as { uuid => value }. Best effort: if the local interface is off or the
# httpd is unreachable, an empty map is returned so the UI shows no values.
sub vz_live
{
	my $port = vz_local_port();
	return { ok => JSON::PP::true, values => {} } if (!$port);
	require HTTP::Tiny;
	my $resp = HTTP::Tiny->new(timeout => 2)->get("http://127.0.0.1:$port/");
	return { ok => JSON::PP::true, values => {} } if (!$resp || !$resp->{success});
	my $doc = eval { JSON::PP->new->relaxed->decode($resp->{content}) };
	return { ok => JSON::PP::true, values => {} } if ($@ || ref($doc) ne "HASH");
	my %values;
	foreach my $ch (@{ref($doc->{data}) eq "ARRAY" ? $doc->{data} : []}) {
		next if (ref($ch) ne "HASH" || !defined($ch->{uuid}));
		my $tuples = $ch->{tuples};
		next if (ref($tuples) ne "ARRAY" || !@$tuples);
		my $last = $tuples->[-1];
		next if (ref($last) ne "ARRAY" || @$last < 2);
		$values{$ch->{uuid}} = $last->[1] + 0;
	}
	return { ok => JSON::PP::true, values => \%values };
}

# Installed and available vzlogger version plus whether an update exists. The
# package helper reports the versions (dpkg / apt-cache); dpkg --compare-versions
# decides if the available one is newer.
sub vz_upgrade_versions
{
	my $pkg = "$lbpbindir/vzlogger_pkg.sh";
	my (undef, $cur)   = LoxBerry::System::execute(command => "$pkg current 2>/dev/null");
	my (undef, $avail) = LoxBerry::System::execute(command => "$pkg available 2>/dev/null");
	$cur   = defined($cur)   ? $cur   : ""; $cur   =~ s/\A\s+|\s+\z//g;
	$avail = defined($avail) ? $avail : ""; $avail =~ s/\A\s+|\s+\z//g;
	my $update = 0;
	if ($cur ne "" && $avail ne "") {
		$update = 1 if (system("dpkg", "--compare-versions", $avail, "gt", $cur) == 0);
	}
	return {
		ok               => JSON::PP::true,
		current          => $cur,
		available        => $avail,
		update_available => $update ? JSON::PP::true : JSON::PP::false,
	};
}

# Runs the vzlogger package upgrade as root (whitelisted in sudoers). The helper
# refreshes the Cloudsmith repository key and writes its own LoxBerry logfile.
sub vz_upgrade_run
{
	my $pkg = "$lbpbindir/vzlogger_pkg.sh";
	my ($rc) = LoxBerry::System::execute(command => "sudo $pkg upgrade </dev/null 2>&1");
	return { ok => (defined($rc) && $rc == 0) ? JSON::PP::true : JSON::PP::false };
}

# The vzLogger local httpd port, or undef when the local interface is disabled.
sub vz_local_port
{
	my ($rc, $out) = LoxBerry::System::execute(command => "$lbpbindir/vzlogger_conf.pl get 2>/dev/null");
	my $config = eval { JSON::PP->new->relaxed->decode(defined($out) ? $out : "") };
	return undef if ($@ || ref($config) ne "HASH" || ref($config->{local}) ne "HASH");
	return undef if (!$config->{local}{enabled});
	my $port = $config->{local}{port};
	return ($port && $port =~ /\A\d+\z/) ? $port : undef;
}

# Hands a JSON payload to a mutating helper subcommand via a temporary file and
# interprets the result: the stored config on success, or a localizable
# error_key the helper reported (e.g. a duplicate meter name).
sub vz_conf_write
{
	my ($subaction, $json) = @_;
	my $payload = eval { JSON::PP->new->decode(defined($json) ? $json : "") };
	return { ok => JSON::PP::false, error_key => "UI_AJAX_FAILED" } if ($@ || ref($payload) ne "HASH");
	my ($fh, $tmp) = eval { tempfile("vzconf-XXXXXX", DIR => $lbpconfigdir, SUFFIX => ".json", UNLINK => 0) };
	return { ok => JSON::PP::false, error_key => "UI_AJAX_FAILED" } if (!$tmp);
	print $fh JSON::PP->new->utf8->encode($payload);
	close($fh);
	my ($rc, $out) = LoxBerry::System::execute(command => "$lbpbindir/vzlogger_conf.pl $subaction '$tmp' 2>/dev/null");
	unlink($tmp);
	my $res = eval { JSON::PP->new->relaxed->decode(defined($out) ? $out : "") };
	return { ok => JSON::PP::false, error_key => "UI_AJAX_FAILED" } if ($rc != 0 || $@ || ref($res) ne "HASH");
	return { ok => JSON::PP::false, error_key => $res->{error_key} } if ($res->{error_key});
	return { ok => JSON::PP::true, config => $res };
}

# Runs the (blocking) OBIS discovery for one meter and returns its candidate
# channels. The meter name is constrained, so it is safe to pass on the command
# line.
sub vz_discover
{
	my ($meter) = @_;
	$meter = "" if (!defined($meter));
	return { ok => JSON::PP::false, error_key => "UI_DISCOVER_METER_NOT_FOUND" } if ($meter !~ /\A[A-Za-z0-9_-]{1,64}\z/);
	my ($rc, $out) = LoxBerry::System::execute(command => "$lbpbindir/vzlogger_discover.pl --meter='$meter' 2>/dev/null");
	my $res = eval { JSON::PP->new->relaxed->decode(defined($out) ? $out : "") };
	return { ok => JSON::PP::false, error_key => "UI_AJAX_FAILED" } if ($@ || ref($res) ne "HASH");
	return $res;
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
elsif ($action eq "irheads-add-tibberpulse") {
	if (!is_post()) {
		$response = { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
	}
	else {
		# add_tibberpulse probes the bridge (reachable + credentials + SML) first.
		my ($ok, $err) = add_tibberpulse($configdir, $q->{name}, $q->{host}, $q->{node}, $q->{password});
		tibberpulse_start($q->{name}) if ($ok);
		$response = { ok => $ok ? JSON::PP::true : JSON::PP::false, error_key => $err, head_lists() };
	}
}
elsif ($action eq "irheads-remove") {
	if (!is_post()) {
		$response = { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
	}
	else {
		# If the removed head is a Tibber Pulse, take its bridge down too.
		my ($data) = load_data($configdir);
		my ($entry) = grep { ref($_) eq "HASH" && ($_->{device} // "") eq ($q->{device} // "") } @{$data->{manual}};
		my ($ok, $err) = remove_manual($configdir, $q->{device});
		tibberpulse_stop($entry->{name}) if ($ok && $entry && ($entry->{type} // "") eq "tibberpulse");
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
elsif ($action eq "vzconf-set-settings") {
	$response = is_post() ? vz_conf_write("set-settings", $q->{settings}) : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vzconf-add-meter") {
	$response = is_post() ? vz_conf_write("add-meter", $q->{meter}) : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vzconf-update-meter") {
	$response = is_post() ? vz_conf_write("update-meter", $q->{meter}) : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vzconf-remove-meter") {
	$response = is_post() ? vz_conf_write("remove-meter", $q->{meter}) : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vzconf-add-channel") {
	$response = is_post() ? vz_conf_write("add-channel", $q->{channel}) : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vzconf-update-channel") {
	$response = is_post() ? vz_conf_write("update-channel", $q->{channel}) : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vzconf-remove-channel") {
	$response = is_post() ? vz_conf_write("remove-channel", $q->{channel}) : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vz-live") {
	$response = vz_live();
}
elsif ($action eq "upgrade-versions") {
	$response = vz_upgrade_versions();
}
elsif ($action eq "upgrade-run") {
	$response = is_post() ? vz_upgrade_run() : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "vzconf-add-channels") {
	$response = is_post() ? vz_conf_write("add-channels", $q->{channels}) : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
elsif ($action eq "meter-discover") {
	$response = is_post() ? vz_discover($q->{meter}) : { ok => JSON::PP::false, error_key => "UI_POST_REQUIRED" };
}
else {
	$response = { ok => JSON::PP::false, error_key => "UI_UNKNOWN_ACTION" };
}

print JSON::PP->new->utf8->canonical->encode($response);
exit;
