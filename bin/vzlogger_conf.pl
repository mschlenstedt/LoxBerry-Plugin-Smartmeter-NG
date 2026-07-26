#!/usr/bin/perl

# Reads and writes vzlogger.conf, the single source of truth for the plugin.
# Called from ajax.cgi and usable from the shell / tests.
#
# Subcommands:
#   get                  Print the current vzlogger.conf as JSON (a default
#                        skeleton if none exists yet; the file is not created).
#   save [FILE]          Read a full config from FILE/STDIN, keep the meters,
#                        re-derive every automatic value, write atomically.
#   set-settings [FILE]  Read a settings patch (retry, local.port, mqtt.topic)
#                        from FILE/STDIN, apply it to the stored config (meters
#                        untouched), re-derive automatics, write.
#
# Only three values are user-controlled: mqtt.topic, local.port and retry.
# Everything else is derived automatically on every write:
#   verbosity  <- plugin loglevel (LoxBerry 0-7 mapped to vzlogger 0/1/3/5/10)
#   log        <- the plugin's vzlogger log path
#   local      <- enabled/index/timeout/buffer fixed; only port from the user
#   mqtt       <- connection from LoxBerry::IO::mqtt_connectiondetails()
#                 (host/port/user/pass/TLS); qos=0, retain=1, timestamp=1,
#                 rawAndAgg=1, enabled=1, keepalive=30, id=smartmeter-ng-<uuid>
#   push       <- never written (the plugin does not use the VZ middleware)
#
# Test overrides (env): SMARTMETER_CONFIG_DIR, SMARTMETER_VZLOGGER_CONFIG_FILE,
#   SMARTMETER_GENERAL_JSON, SMARTMETER_MQTT_JSON, SMARTMETER_LOGLEVEL

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
	print encode_config(load_config() || skeleton());
	exit 0;
}
if ($action eq "save") {
	my $incoming = decode_input(read_input(shift(@ARGV)), "configuration");
	my $data = { %$incoming };
	$data->{meters} = (ref($incoming->{meters}) eq "ARRAY") ? $incoming->{meters} : [];
	enforce_auto($data);
	save_config($data) or die "Could not write $config_file\n";
	print encode_config($data);
	exit 0;
}
if ($action eq "set-settings") {
	my $patch = decode_input(read_input(shift(@ARGV)), "settings");
	my $data = load_config() || skeleton();
	apply_user_settings($data, $patch);
	enforce_auto($data);
	save_config($data) or die "Could not write $config_file\n";
	print encode_config($data);
	exit 0;
}

die "Usage: $0 get|save [FILE]|set-settings [FILE]\n";

# ---------------------------------------------------------------------------

sub encode_config { return JSON::PP->new->utf8->canonical->pretty->encode($_[0]); }

sub decode_input
{
	my ($raw, $what) = @_;
	my $data = eval { JSON::PP->new->relaxed->utf8->decode($raw) };
	die "Invalid $what JSON.\n" if ($@ || ref($data) ne "HASH");
	return $data;
}

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

sub load_config { return read_json_file($config_file, undef); }

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

# Applies the three user-controlled values from a patch; nothing else.
sub apply_user_settings
{
	my ($data, $patch) = @_;
	$data->{retry} = $patch->{retry} if (exists $patch->{retry});
	$data->{local} = {} if (ref($data->{local}) ne "HASH");
	$data->{mqtt}  = {} if (ref($data->{mqtt}) ne "HASH");
	$data->{local}{port} = $patch->{local}{port} if (ref($patch->{local}) eq "HASH" && exists $patch->{local}{port});
	$data->{mqtt}{topic} = $patch->{mqtt}{topic} if (ref($patch->{mqtt}) eq "HASH" && exists $patch->{mqtt}{topic});
	return $data;
}

sub skeleton
{
	my $data = { retry => 30, meters => [] };
	enforce_auto($data);
	return $data;
}

# Re-derives every automatic value, keeping only retry, local.port, mqtt.topic
# and the meters as user data.
sub enforce_auto
{
	my ($data) = @_;
	$data->{retry}     = clean_number($data->{retry}, 30);
	$data->{verbosity} = auto_verbosity();
	$data->{log}       = "$home/log/plugins/$psub/vzlogger.log";
	delete $data->{push};
	my $port = clean_number(ref($data->{local}) eq "HASH" ? $data->{local}{port} : undef, 18080);
	$data->{local} = { enabled => JSON::PP::true, port => $port, index => JSON::PP::true, timeout => 30, buffer => -1 };
	my $topic = (ref($data->{mqtt}) eq "HASH" && defined($data->{mqtt}{topic}) && $data->{mqtt}{topic} ne "")
		? "$data->{mqtt}{topic}" : "smartmeter-ng";
	$data->{mqtt} = auto_mqtt($topic);
	$data->{meters} = [] if (ref($data->{meters}) ne "ARRAY");
	return $data;
}

# vzlogger verbosity from the plugin's LoxBerry loglevel (0-7).
sub auto_verbosity
{
	my %map = (0 => 0, 1 => 0, 2 => 1, 3 => 1, 4 => 3, 5 => 5, 6 => 5, 7 => 10);
	my $ll = plugin_loglevel();
	$ll = 3 if (!defined($ll) || $ll !~ /\A\d+\z/ || $ll > 7);
	return $map{$ll};
}

sub plugin_loglevel
{
	return $ENV{SMARTMETER_LOGLEVEL} if (defined($ENV{SMARTMETER_LOGLEVEL}) && $ENV{SMARTMETER_LOGLEVEL} ne "");
	my $ll = eval { LoxBerry::System::pluginloglevel($psub) };
	return (defined($ll) && $ll =~ /\A\d+\z/) ? $ll : undef;
}

sub auto_mqtt
{
	my ($topic) = @_;
	my $c = mqtt_connection();
	my $tls  = $c->{tls} ? 1 : 0;
	my $host = (defined($c->{brokerhost}) && $c->{brokerhost} ne "") ? "$c->{brokerhost}" : "127.0.0.1";
	my $port = $tls ? clean_number($c->{tls_brokerport}, 8883) : clean_number($c->{brokerport}, 1883);
	my $uuid = loxberry_uuid();
	my $mqtt = {
		enabled   => JSON::PP::true,
		host      => $host,
		port      => $port,
		id        => "smartmeter-ng" . ($uuid ne "" ? "-$uuid" : ""),
		topic     => "$topic",
		qos       => 0,
		retain    => JSON::PP::true,
		timestamp => JSON::PP::true,
		rawAndAgg => JSON::PP::true,
		keepalive => 30,
	};
	set_or_delete($mqtt, "user", $c->{brokeruser});
	set_or_delete($mqtt, "pass", $c->{brokerpass});
	set_or_delete($mqtt, "cafile", $tls ? $c->{tls_cafile} : undef);
	return $mqtt;
}

# MQTT broker connection from the LoxBerry gateway (self-signed TLS -> the API
# returns tls_verify=0 and the local CA file, which is what we point vzlogger to).
sub mqtt_connection
{
	if (defined($ENV{SMARTMETER_MQTT_JSON}) && -e $ENV{SMARTMETER_MQTT_JSON}) {
		return read_json_file($ENV{SMARTMETER_MQTT_JSON}, {});
	}
	my $c = eval { require LoxBerry::IO; LoxBerry::IO::mqtt_connectiondetails(); };
	return (ref($c) eq "HASH") ? $c : {};
}

# The unique LoxBerry installation id (general.json -> Ssdp.Uuid).
sub loxberry_uuid
{
	my $g = read_json_file($general_json, {});
	return "" if (ref($g->{Ssdp}) ne "HASH");
	my $u = $g->{Ssdp}{Uuid};
	return (defined($u) && !ref($u)) ? "$u" : "";
}

sub read_json_file
{
	my ($file, $default) = @_;
	return $default if (!defined($file) || !-e $file);
	open(my $fh, "<", $file) or return $default;
	local $/;
	my $raw = <$fh>;
	close($fh);
	my $data = eval { JSON::PP->new->relaxed->utf8->decode(defined($raw) ? $raw : "") };
	return (ref($data) eq "HASH") ? $data : $default;
}

sub set_or_delete
{
	my ($hash, $key, $value) = @_;
	if (defined($value) && !ref($value) && $value ne "") { $hash->{$key} = "$value"; }
	else { delete $hash->{$key}; }
}

sub clean_number
{
	my ($value, $default) = @_;
	return $default if (!defined($value) || ref($value));
	return ($value =~ /\A\s*(\d+)\s*\z/) ? int($1) : $default;
}
