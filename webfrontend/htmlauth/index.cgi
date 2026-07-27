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

if ($q->{form} eq "smartmeter") {
	$template = LoxBerry::System::read_file("$lbptemplatedir/tab_smartmeter.html");
	&form_smartmeter();
}
elsif ($q->{form} eq "channels") {
	$template = LoxBerry::System::read_file("$lbptemplatedir/tab_channels.html");
	&form_channels();
}
elsif ($q->{form} eq "settings") {
	$template = LoxBerry::System::read_file("$lbptemplatedir/tab_settings.html");
	&form_settings();
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

sub form_irheads    { &preparetemplate(); return(); }
sub form_smartmeter { &preparetemplate(); return(); }
sub form_channels   { &preparetemplate(); return(); }
sub form_settings   { &preparetemplate(); return(); }
sub form_upgrade    { &preparetemplate(); return(); }
sub form_livedata   { &preparetemplate(); return(); }

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
	# Append the shared JavaScript to every tab. It runs through HTML::Template
	# too, so it can use <TMPL_VAR> for localized strings, and fetches its data
	# from ajax.cgi.
	$template .= LoxBerry::System::read_file("$lbptemplatedir/javascript.js");

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

	$navbar{20}{Name}   = $L{'COMMON.TAB_SMARTMETER'};
	$navbar{20}{URL}    = 'index.cgi?form=smartmeter';
	$navbar{20}{active} = 1 if ($q->{form} eq "smartmeter");

	$navbar{30}{Name}   = $L{'COMMON.TAB_CHANNELS'};
	$navbar{30}{URL}    = 'index.cgi?form=channels';
	$navbar{30}{active} = 1 if ($q->{form} eq "channels");

	$navbar{40}{Name}   = $L{'COMMON.TAB_SETTINGS'};
	$navbar{40}{URL}    = 'index.cgi?form=settings';
	$navbar{40}{active} = 1 if ($q->{form} eq "settings");

	$navbar{50}{Name}   = $L{'COMMON.TAB_UPGRADE'};
	$navbar{50}{URL}    = 'index.cgi?form=upgrade';
	$navbar{50}{active} = 1 if ($q->{form} eq "upgrade");

	$navbar{60}{Name}   = $L{'COMMON.TAB_LIVEDATA'};
	$navbar{60}{URL}    = 'index.cgi?form=livedata';
	$navbar{60}{active} = 1 if ($q->{form} eq "livedata");

	$navbar{70}{Name}   = $L{'COMMON.TAB_LOGFILES'};
	$navbar{70}{URL}    = 'index.cgi?form=logfiles';
	$navbar{70}{active} = 1 if ($q->{form} eq "logfiles");

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
