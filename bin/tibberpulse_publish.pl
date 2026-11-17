#!/usr/bin/perl

# Publishes JSON documents of a Tibber Pulse (its metrics) retained to the
# LoxBerry MQTT broker, under
#   <base topic>/tibberpulse/<name>/<suffix>
# <base topic> is the plugin's MQTT base topic (mqtt.topic in vzlogger.conf,
# default "smartmeter-ng"), the same prefix vzLogger publishes the meter values
# under. Each document is decoded and re-encoded compactly, so only valid JSON
# objects reach the broker; the MQTT Gateway can expand their fields.
#
# Called by tibberpulse_meter.sh once per metrics interval.
#
# Usage: tibberpulse_publish.pl <name> <suffix> <file> [<suffix> <file> ...]
# Exit:  0 all published, 1 usage error or a file without a JSON object (the
#        other files are still published), 2 no connection to the broker.
#
# Test override (env): SMARTMETER_VZLOGGER_CONFIG_FILE

use strict;
use warnings;
use JSON::PP;
use LoxBerry::System;
use LoxBerry::IO;

my ($name, @pairs) = @ARGV;
exit 1 if (!defined($name) || $name !~ /\A[A-Za-z0-9_-]+\z/ || !@pairs || @pairs % 2);

my $json = JSON::PP->new->utf8->canonical;
my $base = base_topic();
my $rc   = 0;

while (my ($suffix, $file) = splice(@pairs, 0, 2)) {
	if ($suffix !~ /\A[a-z]+\z/) { $rc = 1; next; }
	my $data = eval { $json->decode(slurp($file)) };
	if (ref($data) ne "HASH") { $rc = 1; next; }
	exit 2 if (!defined(LoxBerry::IO::mqtt_retain("$base/tibberpulse/$name/$suffix", $json->encode($data))));
}
exit $rc;

sub slurp
{
	my ($file) = @_;
	open(my $fh, "<:raw", $file) or return "";
	local $/;
	my $raw = <$fh>;
	close($fh);
	return defined($raw) ? $raw : "";
}

# The plugin's MQTT base topic, as vzlogger_conf.pl stores it.
sub base_topic
{
	my $file = $ENV{SMARTMETER_VZLOGGER_CONFIG_FILE} || "$lbpconfigdir/vzlogger.conf";
	my $conf = eval { JSON::PP->new->relaxed->utf8->decode(slurp($file)) };
	my $topic = (ref($conf) eq "HASH" && ref($conf->{mqtt}) eq "HASH") ? $conf->{mqtt}{topic} : undef;
	$topic = "smartmeter-ng" if (!defined($topic) || $topic eq "");
	$topic =~ s{/+\z}{};
	return $topic;
}
