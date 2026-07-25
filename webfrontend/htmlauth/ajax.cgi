#!/usr/bin/perl

# AJAX endpoint for the web interface. Returns JSON. Mutating actions require
# POST. Error messages are returned as keys and localized in the browser, so
# this endpoint stays language-independent.

use strict;
use warnings;
use CGI;
use JSON::PP;
use FindBin;
use LoxBerry::System;
use lib "$FindBin::Bin/../../bin";
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
else {
	$response = { ok => JSON::PP::false, error_key => "UI_UNKNOWN_ACTION" };
}

print JSON::PP->new->utf8->canonical->encode($response);
exit;
