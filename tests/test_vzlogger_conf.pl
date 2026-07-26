#!/usr/bin/perl

use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;
use Test::More;

my $lib    = "$FindBin::Bin/../.github/ci/perl-lib";
my $bin    = "$FindBin::Bin/../bin";
my $script = "$bin/vzlogger_conf.pl";
my $dir    = tempdir(CLEANUP => 1);

sub write_file
{
	my ($path, $content) = @_;
	open(my $fh, ">", $path) or die "cannot write $path: $!";
	print $fh $content;
	close($fh);
}

# A plain (non-TLS) LoxBerry MQTT gateway and a unique installation id.
write_file("$dir/mqtt.json", '{"brokerhost":"mqtt.example","brokerport":1884,"brokeruser":"gwuser","brokerpass":"gwpass","tls":0}');
write_file("$dir/loxberryid.cfg", "LB-UUID-123\n");

$ENV{SMARTMETER_CONFIG_DIR}      = $dir;
$ENV{SMARTMETER_MQTT_JSON}       = "$dir/mqtt.json";
$ENV{SMARTMETER_LOXBERRYID_FILE} = "$dir/loxberryid.cfg";
$ENV{SMARTMETER_LOGLEVEL}        = 6;

sub run_conf
{
	my (@args) = @_;
	my $cmd = join(" ", map { "'$_'" } ($^X, "-I", $lib, "-I", $bin, $script, @args));
	my $out = `$cmd`;
	return ($out, $? >> 8);
}

sub get_skeleton
{
	unlink("$dir/vzlogger.conf");
	my ($out, $rc) = run_conf("get");
	die "get failed" if ($rc != 0);
	return JSON::PP->new->decode($out);
}

# verbosity is derived from the plugin loglevel (LoxBerry 0-7 -> vzlogger).
$ENV{SMARTMETER_LOGLEVEL} = 6; is(get_skeleton()->{verbosity}, 5,  "loglevel 6 (info) -> verbosity 5");
$ENV{SMARTMETER_LOGLEVEL} = 7; is(get_skeleton()->{verbosity}, 10, "loglevel 7 (debug) -> verbosity 10");
$ENV{SMARTMETER_LOGLEVEL} = 4; is(get_skeleton()->{verbosity}, 3,  "loglevel 4 (warning) -> verbosity 3");
$ENV{SMARTMETER_LOGLEVEL} = 0; is(get_skeleton()->{verbosity}, 0,  "loglevel 0 (emerg) -> verbosity 0");
$ENV{SMARTMETER_LOGLEVEL} = 6;

# Default skeleton and automatic values.
my $sk = get_skeleton();
is($sk->{mqtt}{topic}, "smartmeter-ng", "default base topic is smartmeter-ng");
is($sk->{local}{port}, 18080, "default local port is 18080");
ok($sk->{local}{enabled}, "local httpd is enabled");
is($sk->{retry}, 30, "default retry is 30");
is($sk->{mqtt}{host}, "mqtt.example", "MQTT host from the gateway");
is($sk->{mqtt}{port}, 1884, "MQTT plain port from the gateway");
is($sk->{mqtt}{user}, "gwuser", "MQTT user from the gateway");
is($sk->{mqtt}{qos}, 0, "qos is fixed at 0");
ok($sk->{mqtt}{retain}, "retain is on");
ok($sk->{mqtt}{timestamp}, "timestamp is on");
ok($sk->{mqtt}{rawAndAgg}, "rawAndAgg is on");
is($sk->{mqtt}{id}, "smartmeter-ng-LB-UUID-123", "client id carries the LoxBerry uuid");
ok(!exists $sk->{push}, "push is never written");
is(ref($sk->{meters}), "ARRAY", "meters is an array");

# Without a loxberryid.cfg (send-statistics off) the client id stays plain.
$ENV{SMARTMETER_LOXBERRYID_FILE} = "$dir/does-not-exist.cfg";
is(get_skeleton()->{mqtt}{id}, "smartmeter-ng", "client id falls back to smartmeter-ng without a LoxBerry id");
$ENV{SMARTMETER_LOXBERRYID_FILE} = "$dir/loxberryid.cfg";

# save keeps the meter but forces the automatic MQTT connection.
write_file("$dir/in.json", JSON::PP->new->encode({
	retry  => 30,
	local  => { port => 18080 },
	mqtt   => { topic => "smartmeter-ng", host => "attacker", user => "eve" },
	meters => [ { enabled => JSON::PP::true, protocol => "sml", device => "/dev/ttyUSB0", channels => [] } ],
}));
my ($out, $rc) = run_conf("save", "$dir/in.json");
is($rc, 0, "save exits cleanly");
my $saved = JSON::PP->new->decode($out);
is(scalar(@{$saved->{meters}}), 1, "the meter is stored");
is($saved->{mqtt}{host}, "mqtt.example", "UI cannot override the MQTT host");
is($saved->{mqtt}{user}, "gwuser", "UI cannot override the MQTT user");

# set-settings changes the three user values and keeps the meter.
write_file("$dir/patch.json", JSON::PP->new->encode({ retry => 60, local => { port => 9090 }, mqtt => { topic => "haus" } }));
($out, $rc) = run_conf("set-settings", "$dir/patch.json");
is($rc, 0, "set-settings exits cleanly");
my $s2 = JSON::PP->new->decode($out);
is($s2->{retry}, 60, "retry updated");
is($s2->{local}{port}, 9090, "local port updated");
is($s2->{mqtt}{topic}, "haus", "base topic updated");
is(scalar(@{$s2->{meters}}), 1, "set-settings keeps the meter");
is($s2->{mqtt}{host}, "mqtt.example", "connection still from the gateway");

# TLS gateway: use the TLS port and point cafile at the local CA.
write_file("$dir/mqtt.json", '{"brokerhost":"broker","brokerport":1883,"tls":1,"tls_brokerport":8883,"tls_cafile":"/etc/mosquitto/tls/ca.crt"}');
my $t = get_skeleton();
is($t->{mqtt}{port}, 8883, "TLS broker port is used");
is($t->{mqtt}{cafile}, "/etc/mosquitto/tls/ca.crt", "cafile points at the local CA");

done_testing();
