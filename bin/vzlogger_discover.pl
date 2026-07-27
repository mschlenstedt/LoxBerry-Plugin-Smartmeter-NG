#!/usr/bin/perl

# OBIS auto-discovery for a single meter.
#
# Runs vzLogger briefly against the meter's device with maximum verbosity into
# its own LoxBerry log (name "AutoDiscovery <METERNAME>"), parses the OBIS
# identifiers it observed and prints candidate channels as JSON. The main
# vzLogger is stopped via the watchdog (stop-discovery, no marker) for exclusive
# device access and restarted afterwards (check, which respects a manual stop).
#
# Usage:
#   vzlogger_discover.pl --meter=<name>          run discovery
#   vzlogger_discover.pl --parse-only=<logfile>  only parse a log file (tests)
#
# Env overrides (tests): SMARTMETER_CONFIG_DIR, SMARTMETER_VZLOGGER_CONFIG_FILE,
#   SMARTMETER_OBIS_CATALOG_FILE, SMARTMETER_DISCOVERY_TIMEOUT,
#   SMARTMETER_VZLOGGER_BIN, SMARTMETER_WATCHDOG

use strict;
use warnings;
use Getopt::Long;
use JSON::PP;
use File::Temp qw(tempfile);
use POSIX qw(setsid);
use FindBin;
use LoxBerry::System;
use LoxBerry::Log;

my $home         = $lbhomedir;
my $psub         = $lbpplugindir;
my $config_dir   = $ENV{SMARTMETER_CONFIG_DIR} || "$home/config/plugins/$psub";
my $config_file  = $ENV{SMARTMETER_VZLOGGER_CONFIG_FILE} || "$config_dir/vzlogger.conf";
my $catalog_file = $ENV{SMARTMETER_OBIS_CATALOG_FILE} || "$home/templates/plugins/$psub/obis_catalog.json";
my $timeout      = int($ENV{SMARTMETER_DISCOVERY_TIMEOUT} || 12);
my $watchdog     = $ENV{SMARTMETER_WATCHDOG} || "$lbpbindir/watchdog.pl";

my ($meter_name, $parse_only);
GetOptions("meter=s" => \$meter_name, "parse-only=s" => \$parse_only);

if (defined($parse_only)) {
	print out({ ok => JSON::PP::true, channels => parse_log($parse_only) });
	exit 0;
}
die "Usage: $0 --meter=<name> | --parse-only=<logfile>\n" if (!defined($meter_name) || $meter_name eq "");

my $config = read_json($config_file) || {};
my ($meter) = grep { ref($_) eq "HASH" && (($_->{name} // "") eq $meter_name) }
	@{ref($config->{meters}) eq "ARRAY" ? $config->{meters} : []};
if (!$meter) {
	print out({ ok => JSON::PP::false, error_key => "UI_DISCOVER_METER_NOT_FOUND" });
	exit 0;
}

# OBIS discovery only makes sense for the real reading protocols.
my $proto = $meter->{protocol} // "";
if ($proto !~ /\A(?:sml|d0|oms)\z/) {
	print out({ ok => JSON::PP::true, channels => [] });
	exit 0;
}

# Own LoxBerry log for this run; vzLogger writes into it (like the watchdog).
my $log = LoxBerry::Log->new(name => "AutoDiscovery $meter_name", package => $psub);
$log->LOGSTART("OBIS auto-discovery for meter '$meter_name'");
my $logfile = $log->filename();

# Temporary vzLogger config: this meter without channels, verbosity 15 so every
# reading (incl. unconfigured OBIS) is logged, local httpd off.
my %disc_meter = %$meter;
delete $disc_meter{channels};
delete $disc_meter{name};
$disc_meter{enabled} = JSON::PP::true;
my $disc_config = {
	verbosity => 15,
	log       => $logfile,
	local     => { enabled => JSON::PP::false, port => 18099, index => JSON::PP::false, timeout => 0, buffer => 0 },
	meters    => [ \%disc_meter ],
};
my ($cfg_fh, $cfg_file) = tempfile("vzdiscover-XXXXXX", DIR => $config_dir, SUFFIX => ".conf", UNLINK => 0);
print $cfg_fh JSON::PP->new->utf8->canonical->pretty->encode($disc_config);
close($cfg_fh);
chmod(0640, $cfg_file);

# Free the device (stop the running vzLogger without the manual-stop marker).
run_quiet("$watchdog --action=stop-discovery");

# Run vzLogger for the timeout, then stop it.
my $bin = $ENV{SMARTMETER_VZLOGGER_BIN} || vzlogger_binary();
if ($bin) {
	my $pid = fork();
	if (defined($pid) && $pid == 0) {
		setsid();
		open(STDIN, "<", "/dev/null");
		open(STDOUT, ">>", "/dev/null");
		open(STDERR, ">&", \*STDOUT);
		exec($bin, "-f", "-c", $cfg_file, "-o", $logfile);
		exit 1;
	}
	if ($pid) {
		sleep($timeout);
		kill("TERM", $pid);
		select(undef, undef, undef, 0.5);
		kill("KILL", $pid);
		waitpid($pid, 0);
	}
}

unlink($cfg_file);

# Clear the autodiscovery marker and restart the main service (does nothing if
# the user had manually stopped it).
run_quiet("$watchdog --action=end-discovery");

$log->LOGEND("OBIS auto-discovery finished");

print out({ ok => JSON::PP::true, channels => parse_log($logfile) });
exit 0;

# ---------------------------------------------------------------------------

sub out { return JSON::PP->new->utf8->canonical->encode($_[0]); }

sub run_quiet { my ($cmd) = @_; system("$cmd >/dev/null 2>&1"); }

sub vzlogger_binary
{
	foreach my $candidate ("/usr/bin/vzlogger", "/usr/local/bin/vzlogger") {
		return $candidate if (-x $candidate);
	}
	foreach my $dir (split(/:/, $ENV{PATH} || "")) {
		return "$dir/vzlogger" if (-x "$dir/vzlogger");
	}
	return undef;
}

sub read_json
{
	my ($file) = @_;
	return undef if (!defined($file) || !-e $file);
	open(my $fh, "<", $file) or return undef;
	local $/;
	my $raw = <$fh>;
	close($fh);
	my $data = eval { JSON::PP->new->relaxed->utf8->decode(defined($raw) ? $raw : "") };
	return (ref($data) eq "HASH") ? $data : undef;
}

# Maps OBIS codes to their catalog output_name (a ready-to-use channel name).
sub obis_names
{
	my %map;
	my $cat = read_json($catalog_file) || {};
	foreach my $entry (@{ref($cat->{entries}) eq "ARRAY" ? $cat->{entries} : []}) {
		next if (ref($entry) ne "HASH");
		my $code = $entry->{code};
		my $name = $entry->{output_name};
		$map{$code} = $name if (defined($code) && defined($name) && $name =~ /\A[A-Za-z0-9_-]+\z/);
	}
	return \%map;
}

# Extracts the distinct OBIS identifiers from vzLogger's "Reading:" log lines and
# returns candidate channels [{identifier, name}]. Storage *255 (current value)
# is stripped to the conventional form users configure.
sub parse_log
{
	my ($file) = @_;
	my $names = obis_names();
	my %seen;
	my @out;
	open(my $fh, "<", $file) or return \@out;
	while (my $line = <$fh>) {
		next if ($line !~ /Reading:/);
		while ($line =~ /(\d+-\d+:\d+\.\d+\.\d+(?:\*\d+)?)/g) {
			my $raw = $1;
			(my $ident = $raw) =~ s/\*255\z//;
			(my $code  = $raw) =~ s/\*\d+\z//;
			next if ($seen{$ident}++);
			my $name = $names->{$code} || sanitize_name($ident);
			push @out, { identifier => $ident, name => $name };
		}
	}
	close($fh);
	return \@out;
}

sub sanitize_name
{
	my ($s) = @_;
	$s =~ s/[^A-Za-z0-9_-]/_/g;
	$s = substr($s, 0, 64);
	return $s ne "" ? $s : "Channel";
}
