#!/usr/bin/perl

# Reads and writes vzlogger.conf, the single source of truth for the plugin.
# Called from ajax.cgi and usable from the shell / tests.
#
# Subcommands:
#   get           Print the current vzlogger.conf as JSON. If it does not exist
#                 yet, print a default skeleton (without creating the file).
#   save [FILE]   Read a full configuration as JSON from FILE (or STDIN), force
#                 the automatic parts (the MQTT connection is always taken from
#                 the LoxBerry MQTT gateway, never from the UI), write
#                 vzlogger.conf atomically, and print the stored result.
#
# Overridable via environment for tests:
#   SMARTMETER_CONFIG_DIR, SMARTMETER_VZLOGGER_CONFIG_FILE, SMARTMETER_GENERAL_JSON

use strict;
use warnings;
use FindBin;
use JSON::PP;
use LoxBerry::System;

my $home         = $lbhomedir;
my $psub         = $lbpplugindir;
my $config_dir   = $ENV{SMARTMETER_CONFIG_DIR} || "$home/config/plugins/$psub";
my $config_file  = $ENV{SMARTMETER_VZLOGGER_CONFIG_FILE} || "$config_dir/vzlogger.conf";
my $general_json = $ENV{SMARTMETER_GENERAL_JSON} || "$home/config/system/general.json";

my $action = shift(@ARGV) || "";

if ($action eq "get") {
	my $data = load_config() || default_skeleton();
	print encode_config($data);
	exit 0;
}
if ($action eq "save") {
	my $raw = read_input(shift(@ARGV));
	my $incoming = eval { JSON::PP->new->relaxed->utf8->decode($raw) };
	die "Invalid configuration JSON.\n" if ($@ || ref($incoming) ne "HASH");
	my $data = merge_config($incoming);
	save_config($data) or die "Could not write $config_file\n";
	print encode_config($data);
	exit 0;
}

die "Usage: $0 get|save [FILE]\n";

# ---------------------------------------------------------------------------

sub encode_config { return JSON::PP->new->utf8->canonical->pretty->encode($_[0]); }

sub read_input
{
	my ($file) = @_;
	local $/;
	if (defined($file) && $file ne "") {
		open(my $fh, "<", $file) or die "Could not read $file: $!\n";
		my $raw = <$fh>;
		close($fh);
		return defined($raw) ? $raw : "";
	}
	my $raw = <STDIN>;
	return defined($raw) ? $raw : "";
}

sub load_config
{
	return undef if (!-e $config_file);
	open(my $fh, "<", $config_file) or return undef;
	local $/;
	my $raw = <$fh>;
	close($fh);
	my $data = eval { JSON::PP->new->relaxed->utf8->decode(defined($raw) ? $raw : "") };
	return (ref($data) eq "HASH") ? $data : undef;
}

sub save_config
{
	my ($data) = @_;
	make_path_for($config_file);
	my $tmp = "$config_file.tmp.$$";
	open(my $fh, ">", $tmp) or return 0;
	print $fh encode_config($data);
	close($fh) or return 0;
	chmod(0640, $tmp);
	return rename($tmp, $config_file) ? 1 : 0;
}

sub make_path_for
{
	my ($file) = @_;
	my ($dir) = $file =~ m{\A(.*)/[^/]+\z};
	return if (!$dir || -d $dir);
	require File::Path;
	File::Path::make_path($dir);
}

# Builds the full config from the incoming UI object: keep the user-managed
# parts (meters, local, and the mqtt topic/qos/retain/... settings) but always
# overwrite the MQTT connection with the current LoxBerry MQTT gateway details.
sub merge_config
{
	my ($incoming) = @_;
	my $skeleton = default_skeleton();
	my $data = { %$skeleton, %$incoming };
	$data->{meters} = (ref($incoming->{meters}) eq "ARRAY") ? $incoming->{meters} : [];
	$data->{local}  = merge_hash($skeleton->{local}, $incoming->{local});
	$data->{mqtt}   = merge_hash($skeleton->{mqtt}, $incoming->{mqtt});
	apply_gateway_mqtt($data->{mqtt});
	return $data;
}

sub merge_hash
{
	my ($base, $override) = @_;
	my %out = %{ref($base) eq "HASH" ? $base : {}};
	if (ref($override) eq "HASH") { $out{$_} = $override->{$_} for keys %$override; }
	return \%out;
}

# The MQTT connection is automatic and must not come from the UI.
sub apply_gateway_mqtt
{
	my ($mqtt) = @_;
	my $gw = mqtt_from_gateway();
	$mqtt->{host} = $gw->{host};
	$mqtt->{port} = $gw->{port};
	set_or_delete($mqtt, "user", $gw->{user});
	set_or_delete($mqtt, "pass", $gw->{pass});
	return $mqtt;
}

sub set_or_delete
{
	my ($hash, $key, $value) = @_;
	if (defined($value) && $value ne "") { $hash->{$key} = "$value"; }
	else { delete $hash->{$key}; }
}

sub default_skeleton
{
	my $mqtt = {
		enabled   => JSON::PP::true,
		topic     => "smartmeter",
		qos       => 0,
		retain    => JSON::PP::true,
		keepalive => 30,
	};
	apply_gateway_mqtt($mqtt);
	return {
		retry     => 30,
		verbosity => 0,
		log       => "/dev/null",
		local     => { enabled => JSON::PP::true, port => 18080, index => JSON::PP::true, timeout => 30, buffer => -1 },
		mqtt      => $mqtt,
		meters    => [],
	};
}

# Reads the MQTT broker connection from the LoxBerry MQTT gateway
# (config/system/general.json -> Mqtt section).
sub mqtt_from_gateway
{
	my %s = (host => "127.0.0.1", port => 1883, user => "", pass => "");
	return \%s if (!-e $general_json);
	open(my $fh, "<", $general_json) or return \%s;
	local $/;
	my $raw = <$fh>;
	close($fh);
	my $general = eval { JSON::PP->new->relaxed->utf8->decode(defined($raw) ? $raw : "") };
	return \%s if ($@ || ref($general) ne "HASH" || ref($general->{Mqtt}) ne "HASH");
	my $m = $general->{Mqtt};
	$s{host} = first_value($m, qw(Host Hostname Broker Brokerhost Server IpAddress Ipaddress)) || $s{host};
	$s{port} = clean_number(first_value($m, qw(Port Brokerport Mqttport)), $s{port});
	$s{user} = first_value($m, qw(Brokeruser Brokerusername User Username Login)) || "";
	$s{pass} = first_value($m, qw(Brokerpass Brokerpassword Pass Password)) || "";
	return \%s;
}

sub first_value
{
	my ($hash, @keys) = @_;
	foreach my $key (@keys) {
		return $hash->{$key} if (defined($hash->{$key}) && !ref($hash->{$key}) && $hash->{$key} ne "");
	}
	return undef;
}

sub clean_number
{
	my ($value, $default) = @_;
	return $default if (!defined($value) || ref($value));
	return ($value =~ /\A\s*(\d+)\s*\z/) ? int($1) : $default;
}
