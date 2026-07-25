#!/usr/bin/perl

use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterConfig;

my $dir = tempdir(CLEANUP => 1);

sub slurp_json
{
	my ($file) = @_;
	open(my $fh, "<", $file) or die "cannot read $file: $!";
	local $/;
	my $content = <$fh>;
	close($fh);
	return JSON::PP->new->utf8->decode($content);
}

# A missing file is an error, matching the previous Config::Simple behaviour
# that the "or die" call sites rely on.
is(SmartMeterConfig->new("$dir/does-not-exist.json"), undef, "missing configuration reports an error");
ok(SmartMeterConfig->error(), "an error message is available");

my $file = "$dir/smartmeter.json";
my $cfg = SmartMeterConfig->create($file);
ok($cfg, "create() starts a new configuration");

# Global sections and meter sections use the same flat accessor.
$cfg->param("MAIN.IMPLEMENTATION", "vzlogger");
$cfg->param("MAIN.MQTTTOPIC", "1");
$cfg->param("VZLOGGER.LOCALPORT", "18080");
$cfg->param("reader1.SERIAL", "reader1");
$cfg->param("reader1.METER", "sml");
$cfg->save;

is($cfg->param("MAIN.IMPLEMENTATION"), "vzlogger", "global value round-trips");
is($cfg->param("reader1.METER"), "sml", "meter value round-trips");
is($cfg->param("MAIN.MISSING"), undef, "unknown key is undef");
is($cfg->param("nosuchreader.METER"), undef, "unknown meter is undef");

my $stored = slurp_json($file);
is($stored->{MAIN}->{IMPLEMENTATION}, "vzlogger", "global sections stay top level");
is($stored->{METERS}->{reader1}->{METER}, "sml", "meters are nested below METERS");
ok(!exists($stored->{reader1}), "meters do not leak into the top level");

# Reopening reads the same values back.
my $reopened = SmartMeterConfig->new($file);
ok($reopened, "existing configuration opens");
is($reopened->param("VZLOGGER.LOCALPORT"), "18080", "value survives a reopen");
is_deeply([sort $reopened->param()],
	[sort qw(MAIN.IMPLEMENTATION MAIN.MQTTTOPIC VZLOGGER.LOCALPORT reader1.SERIAL reader1.METER)],
	"param() lists global and meter keys as SECTION.KEY");

# delete() removes the key and drops the meter once it is empty.
$reopened->delete("reader1.METER");
is($reopened->param("reader1.METER"), undef, "deleted key is gone");
is($reopened->param("reader1.SERIAL"), "reader1", "sibling key is retained");
$reopened->delete("reader1.SERIAL");
$reopened->save;
ok(!exists(slurp_json($file)->{METERS}->{reader1}), "empty meter section is removed");

# import_from fills the flat hash the generator uses to find readers.
my $flat_file = "$dir/flat.json";
my $flat_cfg = SmartMeterConfig->create($flat_file);
$flat_cfg->param("MAIN.MQTTTOPIC", "1");
$flat_cfg->param("readerA.SERIAL", "readerA");
$flat_cfg->save;
my %flat;
ok(SmartMeterConfig->import_from($flat_file, \%flat), "import_from succeeds");
is($flat{"MAIN.MQTTTOPIC"}, "1", "flat hash contains global keys");
is($flat{"readerA.SERIAL"}, "readerA", "flat hash contains meter keys as <serial>.KEY");

done_testing();
