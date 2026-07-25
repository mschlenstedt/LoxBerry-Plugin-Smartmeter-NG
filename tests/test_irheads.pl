#!/usr/bin/perl

use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterIRHeads qw(load_data add_manual remove_manual usb_port_short);

my $dir = tempdir(CLEANUP => 1);

sub read_manual
{
	my ($data) = load_data($dir);
	return $data->{manual};
}

# A fresh directory yields the empty structure.
my ($data) = load_data($dir);
is_deeply($data->{auto}, [], "auto list starts empty");
is_deeply($data->{manual}, [], "manual list starts empty");

# usb_port_short extracts the port from a udev ID_PATH.
is(usb_port_short("platform-xhci-hcd.0-usb-0:1.2:1.0"), "1.2", "USB port is extracted from ID_PATH");
is(usb_port_short(""), "", "empty ID_PATH yields empty port");
is(usb_port_short("something-else"), "something-else", "unparsable ID_PATH falls back to the raw value");

# Adding a valid manual head.
my ($ok, $err) = add_manual($dir, "/dev/ttyUSB0", "Kitchen_Meter");
ok($ok, "a valid manual head is added");
is($err, "", "no error on a valid add");
my $manual = read_manual();
is(scalar(@$manual), 1, "one manual head is stored");
is($manual->[0]->{device}, "/dev/ttyUSB0", "device path is stored");
is($manual->[0]->{name}, "Kitchen_Meter", "name is stored");

# Invalid device path and name are rejected.
($ok, $err) = add_manual($dir, "not-a-dev-path", "Name");
ok(!$ok, "a non /dev path is rejected");
is($err, "UI_IRHEAD_INVALID_DEVICE", "invalid device reports the right key");

($ok, $err) = add_manual($dir, "/dev/ttyUSB1", "invalid name");
ok(!$ok, "a name with a space is rejected");
is($err, "UI_IRHEAD_INVALID_NAME", "invalid name reports the right key");

($ok, $err) = add_manual($dir, "/dev/ttyUSB1", "bad/char");
ok(!$ok, "a name with a slash is rejected");
is($err, "UI_IRHEAD_INVALID_NAME", "special characters in the name are rejected");

# Duplicate device or name is rejected.
($ok, $err) = add_manual($dir, "/dev/ttyUSB0", "Other_Name");
ok(!$ok, "a duplicate device is rejected");
is($err, "UI_IRHEAD_DUPLICATE", "duplicate device reports the right key");

($ok, $err) = add_manual($dir, "/dev/ttyUSB9", "Kitchen_Meter");
ok(!$ok, "a duplicate name is rejected");
is($err, "UI_IRHEAD_DUPLICATE", "duplicate name reports the right key");

# A second valid head can be added.
($ok, $err) = add_manual($dir, "/dev/serial/by-id/usb-abc", "Cellar-Meter");
ok($ok, "a second valid manual head with a hyphen name is added");
is(scalar(@{read_manual()}), 2, "two manual heads are stored");

# Removing by device path.
($ok, $err) = remove_manual($dir, "/dev/ttyUSB0");
ok($ok, "an existing manual head is removed");
$manual = read_manual();
is(scalar(@$manual), 1, "one manual head remains");
is($manual->[0]->{device}, "/dev/serial/by-id/usb-abc", "the correct head remains");

# Removing a non-existent device reports an error.
($ok, $err) = remove_manual($dir, "/dev/ttyUSB0");
ok(!$ok, "removing an absent head fails");
is($err, "UI_IRHEAD_NOT_FOUND", "absent head reports the right key");

# The stored file is valid JSON with the expected shape.
open(my $fh, "<", "$dir/irheads.json") or die "cannot read irheads.json: $!";
local $/;
my $raw = <$fh>;
close($fh);
my $stored = JSON::PP->new->decode($raw);
ok(ref($stored->{manual}) eq "ARRAY", "irheads.json keeps manual as an array");
ok(exists($stored->{auto}), "irheads.json keeps the auto key");

done_testing();
