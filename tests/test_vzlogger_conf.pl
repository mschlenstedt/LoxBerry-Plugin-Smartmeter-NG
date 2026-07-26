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

my $dir = tempdir(CLEANUP => 1);

# A LoxBerry MQTT gateway definition, used to fill the connection automatically.
open(my $gh, ">", "$dir/general.json") or die "cannot write general.json: $!";
print $gh '{"Mqtt":{"Host":"mqtt.example","Port":1884,"Brokeruser":"gwuser","Brokerpass":"gwpass"}}';
close($gh);

$ENV{SMARTMETER_CONFIG_DIR}   = $dir;
$ENV{SMARTMETER_GENERAL_JSON} = "$dir/general.json";

sub run_conf
{
	my (@args) = @_;
	my $cmd = join(" ", map { "'$_'" } ($^X, "-I", $lib, "-I", $bin, $script, @args));
	my $out = `$cmd`;
	return ($out, $? >> 8);
}

# get on a fresh directory returns the default skeleton with the gateway MQTT.
my ($out, $rc) = run_conf("get");
is($rc, 0, "get exits cleanly");
my $skeleton = JSON::PP->new->decode($out);
is(ref($skeleton->{meters}), "ARRAY", "skeleton has a meters array");
is(scalar(@{$skeleton->{meters}}), 0, "skeleton has no meters");
is($skeleton->{mqtt}->{host}, "mqtt.example", "MQTT host comes from the gateway");
is($skeleton->{mqtt}->{port}, 1884, "MQTT port comes from the gateway");
is($skeleton->{mqtt}->{user}, "gwuser", "MQTT user comes from the gateway");
is($skeleton->{mqtt}->{topic}, "smartmeter", "default base topic is smartmeter");
ok(!-e "$dir/vzlogger.conf", "get does not create the file");

# save keeps the meters and the user base topic, but forces the MQTT connection
# to the gateway (ignoring a UI-provided host/user).
my $incoming = {
	%$skeleton,
	meters => [ { enabled => JSON::PP::true, protocol => "sml", device => "/dev/ttyUSB0", channels => [] } ],
	mqtt   => { %{$skeleton->{mqtt}}, topic => "haus", host => "attacker", user => "eve" },
};
open(my $ih, ">", "$dir/in.json") or die "cannot write in.json: $!";
print $ih JSON::PP->new->encode($incoming);
close($ih);

($out, $rc) = run_conf("save", "$dir/in.json");
is($rc, 0, "save exits cleanly");
ok(-e "$dir/vzlogger.conf", "save writes vzlogger.conf");
my $saved = JSON::PP->new->decode($out);
is(scalar(@{$saved->{meters}}), 1, "the meter is stored");
is($saved->{meters}->[0]->{device}, "/dev/ttyUSB0", "meter device is stored");
is($saved->{mqtt}->{topic}, "haus", "user base topic is kept");
is($saved->{mqtt}->{host}, "mqtt.example", "UI cannot override the MQTT host");
is($saved->{mqtt}->{user}, "gwuser", "UI cannot override the MQTT user");

# get now returns the saved configuration.
($out, $rc) = run_conf("get");
my $reloaded = JSON::PP->new->decode($out);
is(scalar(@{$reloaded->{meters}}), 1, "get returns the saved meter");
is($reloaded->{mqtt}->{topic}, "haus", "get returns the saved base topic");

done_testing();
