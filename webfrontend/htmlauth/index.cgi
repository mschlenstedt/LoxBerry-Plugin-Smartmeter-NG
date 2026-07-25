#!/usr/bin/perl

# Smartmeter-NG web interface.
#
# Uses the LoxBerry Design System (lb-* classes), not jQuery Mobile: the fourth
# argument to lbheader() is "nojqm". The page is a set of tabs, one template per
# tab, selected through the ?form= parameter and rendered as a navbar. The tabs
# are still empty scaffolding; their content is added step by step.

use strict;
use warnings;
use CGI;
use LoxBerry::System;
use LoxBerry::Web;
use LoxBerry::Log;

my $cgi = CGI->new;
my $q   = $cgi->Vars;

my $version = LoxBerry::System::pluginversion();

my $log = LoxBerry::Log->new(
	name    => "index",
	package => $lbpplugindir,
	addtime => 1,
);

$q->{form} = "irheads" if (!$q->{form});
$log->LOGSTART("index.cgi form=$q->{form}");

my $template;
my $templateout;
my %L;

if ($q->{form} eq "vzlogger") {
	$template = LoxBerry::System::read_file("$lbptemplatedir/tab_vzlogger.html");
	&form_vzlogger();
}
elsif ($q->{form} eq "upgrade") {
	$template = LoxBerry::System::read_file("$lbptemplatedir/tab_upgrade.html");
	&form_upgrade();
}
elsif ($q->{form} eq "livedata") {
	$template = LoxBerry::System::read_file("$lbptemplatedir/tab_livedata.html");
	&form_livedata();
}
elsif ($q->{form} eq "logfiles") {
	$template = LoxBerry::System::read_file("$lbptemplatedir/tab_logfiles.html");
	&form_logfiles();
}
else {
	$template = LoxBerry::System::read_file("$lbptemplatedir/tab_irheads.html");
	&form_irheads();
}

&printtemplate();
exit;

##########################################################################
# Tab forms (empty scaffolding for now)
##########################################################################

sub form_irheads  { &preparetemplate(); return(); }
sub form_vzlogger { &preparetemplate(); return(); }
sub form_upgrade  { &preparetemplate(); return(); }
sub form_livedata { &preparetemplate(); return(); }

sub form_logfiles
{
	&preparetemplate();
	$templateout->param("LOGLIST", LoxBerry::Web::loglist_html());
	return();
}

##########################################################################
# Template and navbar
##########################################################################

sub preparetemplate
{
	$templateout = HTML::Template->new_scalar_ref(
		\$template,
		global_vars       => 1,
		loop_context_vars => 1,
		die_on_bad_params => 0,
	);
	%L = LoxBerry::System::readlanguage($templateout, "language.ini");

	# Navbar entries. Numeric keys control the display order.
	our %navbar;

	$navbar{10}{Name}   = $L{'COMMON.TAB_IRHEADS'};
	$navbar{10}{URL}    = 'index.cgi?form=irheads';
	$navbar{10}{active} = 1 if ($q->{form} eq "irheads");

	$navbar{20}{Name}   = $L{'COMMON.TAB_VZLOGGER'};
	$navbar{20}{URL}    = 'index.cgi?form=vzlogger';
	$navbar{20}{active} = 1 if ($q->{form} eq "vzlogger");

	$navbar{30}{Name}   = $L{'COMMON.TAB_UPGRADE'};
	$navbar{30}{URL}    = 'index.cgi?form=upgrade';
	$navbar{30}{active} = 1 if ($q->{form} eq "upgrade");

	$navbar{40}{Name}   = $L{'COMMON.TAB_LIVEDATA'};
	$navbar{40}{URL}    = 'index.cgi?form=livedata';
	$navbar{40}{active} = 1 if ($q->{form} eq "livedata");

	$navbar{50}{Name}   = $L{'COMMON.TAB_LOGFILES'};
	$navbar{50}{URL}    = 'index.cgi?form=logfiles';
	$navbar{50}{active} = 1 if ($q->{form} eq "logfiles");

	return();
}

sub printtemplate
{
	# "nojqm" selects the LoxBerry Design System instead of jQuery Mobile.
	LoxBerry::Web::lbheader($L{'COMMON.PLUGIN_TITLE'} . " V$version", "https://wiki.loxberry.de", "", "nojqm");
	print LoxBerry::Log::get_notifications_html($lbpplugindir);
	print $templateout->output();
	LoxBerry::Web::lbfooter();
	return();
}
