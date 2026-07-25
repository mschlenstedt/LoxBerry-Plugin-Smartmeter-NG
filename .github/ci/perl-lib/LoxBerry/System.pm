package LoxBerry::System;
use strict;
use warnings;

our $lbhomedir = '/opt/loxberry';
our $lbpplugindir = 'smartmeter-ng';
our $lbpbindir = '/opt/loxberry/bin/plugins/smartmeter-ng';
our $lbpconfigdir = '/opt/loxberry/config/plugins/smartmeter-ng';
our $lbptemplatedir = '/opt/loxberry/templates/plugins/smartmeter-ng';
our $lbplogdir = '/opt/loxberry/log/plugins/smartmeter-ng';

sub import {
	my $caller = caller;
	no strict 'refs';
	*{"${caller}::lbhomedir"} = \$lbhomedir;
	*{"${caller}::lbpplugindir"} = \$lbpplugindir;
	*{"${caller}::lbpbindir"} = \$lbpbindir;
	*{"${caller}::lbpconfigdir"} = \$lbpconfigdir;
	*{"${caller}::lbptemplatedir"} = \$lbptemplatedir;
	*{"${caller}::lbplogdir"} = \$lbplogdir;
}

sub pluginversion { return "0.0.0"; }
sub lock { return undef; }
sub unlock { return 1; }
sub readlanguage { return (); }
sub execute { my (%p) = @_; my $out = `$p{command} 2>&1`; return ($? >> 8, $out); }
sub read_file { my ($f) = @_; open(my $fh, "<", $f) or return ""; local $/; my $c = <$fh>; close($fh); return $c; }

1;
