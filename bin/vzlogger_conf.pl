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
#   verbosity  <- plugin loglevel (LoxBerry 0-7 mapped to vzlogger -1/0/1/3/5/10)
#   log        <- the plugin's vzlogger log path (log/plugins/<folder>/vzlogger.log,
#                 the file the watchdog also passes as -o and the Logfiles tab links)
#   local      <- enabled/index/timeout/buffer fixed; only port from the user
#   mqtt       <- connection from LoxBerry::IO::mqtt_connectiondetails()
#                 (host/port/user/pass/TLS); qos=0, retain=1, timestamp=1,
#                 rawAndAgg=1, enabled=1, keepalive=30, id=smartmeter-ng-<uuid>
#   push       <- never written (the plugin does not use the VZ middleware)
#
# Test overrides (env): SMARTMETER_CONFIG_DIR, SMARTMETER_VZLOGGER_CONFIG_FILE,
#   SMARTMETER_MQTT_JSON, SMARTMETER_LOXBERRYID_FILE, SMARTMETER_LOGLEVEL

use strict;
use warnings;
use FindBin;
use JSON::PP;
use LoxBerry::System;

my $home         = $lbhomedir;
my $psub         = $lbpplugindir;
my $config_dir   = $ENV{SMARTMETER_CONFIG_DIR} || "$home/config/plugins/$psub";
my $config_file  = $ENV{SMARTMETER_VZLOGGER_CONFIG_FILE} || "$config_dir/vzlogger.conf";
my $loxberryid_file = $ENV{SMARTMETER_LOXBERRYID_FILE} || "$lbsconfigdir/loxberryid.cfg";

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
if ($action eq "refresh") {
	# Re-derive only the auto-managed fields on the existing config (verbosity from
	# the live plugin loglevel, log path, local httpd, mqtt). Used before starting
	# vzLogger so a changed plugin loglevel takes effect on restart. User data and
	# meters/channels are preserved. Does nothing if no config exists yet.
	my $data = load_config();
	if (!$data) { print encode_config(skeleton()); exit 0; }
	enforce_auto($data);
	save_config($data) or die "Could not write $config_file\n";
	print encode_config($data);
	exit 0;
}
if ($action eq "add-meter" || $action eq "update-meter" || $action eq "remove-meter") {
	my $form = decode_input(read_input(shift(@ARGV)), "meter");
	my $data = load_config() || skeleton();
	my ($ok, $err);
	if    ($action eq "add-meter")    { ($ok, $err) = meter_add($data, $form); }
	elsif ($action eq "update-meter") { ($ok, $err) = meter_update($data, $form); }
	else                              { ($ok, $err) = meter_remove($data, trimmed($form->{name})); }
	# Validation problems are reported as an error key (exit 0) so the web UI can
	# localize them; only real write failures are fatal.
	if (!$ok) { print encode_config({ error_key => $err }); exit 0; }
	enforce_auto($data);
	save_config($data) or die "Could not write $config_file\n";
	print encode_config($data);
	exit 0;
}
if ($action eq "add-channel" || $action eq "update-channel" || $action eq "remove-channel" || $action eq "add-channels") {
	my $form = decode_input(read_input(shift(@ARGV)), "channel");
	my $data = load_config() || skeleton();
	my ($ok, $err);
	if    ($action eq "add-channel")    { ($ok, $err) = channel_add($data, $form); }
	elsif ($action eq "update-channel") { ($ok, $err) = channel_update($data, $form); }
	elsif ($action eq "remove-channel") { ($ok, $err) = channel_remove($data, $form); }
	else                                { ($ok, $err) = channels_add_many($data, $form); }
	if (!$ok) { print encode_config({ error_key => $err }); exit 0; }
	enforce_auto($data);
	save_config($data) or die "Could not write $config_file\n";
	print encode_config($data);
	exit 0;
}

die "Usage: $0 get|refresh|save [FILE]|set-settings [FILE]|add-meter [FILE]|update-meter [FILE]|remove-meter [FILE]|add-channel [FILE]|update-channel [FILE]|remove-channel [FILE]|add-channels [FILE]\n";

# ---------------------------------------------------------------------------

sub encode_config
{
	my $json = JSON::PP->new->utf8->canonical->pretty->encode($_[0]);
	# vzLogger's "random" protocol requires min/max as JSON doubles and throws on
	# integers; JSON::PP emits whole numbers without a decimal, so append ".0" to
	# integer min/max values (these keys only occur in random meters).
	$json =~ s/("(?:min|max)"\s*:\s*-?\d+)(?=\s*[,\n}])/$1.0/g;
	return $json;
}

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

# ---- Meters -------------------------------------------------------------

# A meter is identified by its (unique) plugin name, stored as an extra "name"
# key. vzLogger passes unknown meter keys through untouched, so this stays inside
# vzlogger.conf. One meter maps to exactly one device.
sub meter_index
{
	my ($data, $name) = @_;
	return -1 if (ref($data->{meters}) ne "ARRAY" || !defined($name) || $name eq "");
	for my $i (0 .. $#{$data->{meters}}) {
		my $m = $data->{meters}[$i];
		return $i if (ref($m) eq "HASH" && defined($m->{name}) && $m->{name} eq $name);
	}
	return -1;
}

sub meter_validate
{
	my ($data, $form, $skip_idx) = @_;
	my $name   = trimmed($form->{name});
	my $device = trimmed($form->{device});
	my $proto  = trimmed($form->{protocol});
	return (0, "UI_METER_INVALID_NAME")     if ($name !~ /\A[A-Za-z0-9_-]{1,64}\z/);
	return (0, "UI_METER_INVALID_PROTOCOL") if ($proto !~ /\A(?:sml|d0|oms|random|exec)\z/);
	# random and exec have no device; every serial protocol needs one.
	return (0, "UI_METER_INVALID_DEVICE")   if ($proto ne "random" && $proto ne "exec" && $device !~ m{\A/dev/[A-Za-z0-9_./-]{1,120}\z});
	return (0, "UI_METER_COMMAND_REQUIRED") if ($proto eq "exec" && trimmed($form->{command}) eq "");
	for my $i (0 .. $#{$data->{meters}}) {
		next if (defined($skip_idx) && $i == $skip_idx);
		my $m = $data->{meters}[$i];
		next if (ref($m) ne "HASH");
		return (0, "UI_METER_DUPLICATE_NAME")   if (defined($m->{name}) && $m->{name} eq $name);
		return (0, "UI_METER_DUPLICATE_DEVICE") if ($device ne "" && defined($m->{device}) && $m->{device} eq $device);
	}
	return (1, "");
}

sub meter_add
{
	my ($data, $form) = @_;
	my ($ok, $err) = meter_validate($data, $form, undef);
	return (0, $err) if (!$ok);
	$data->{meters} = [] if (ref($data->{meters}) ne "ARRAY");
	push @{$data->{meters}}, normalize_meter($form, []);
	return (1, "");
}

sub meter_update
{
	my ($data, $form) = @_;
	my $idx = meter_index($data, trimmed($form->{original_name}));
	return (0, "UI_METER_NOT_FOUND") if ($idx < 0);
	my ($ok, $err) = meter_validate($data, $form, $idx);
	return (0, $err) if (!$ok);
	# Keep the channels that were configured for this meter.
	my $channels = (ref($data->{meters}[$idx]{channels}) eq "ARRAY") ? $data->{meters}[$idx]{channels} : [];
	$data->{meters}[$idx] = normalize_meter($form, $channels);
	return (1, "");
}

sub meter_remove
{
	my ($data, $name) = @_;
	my $idx = meter_index($data, $name);
	return (0, "UI_METER_NOT_FOUND") if ($idx < 0);
	splice(@{$data->{meters}}, $idx, 1);
	return (1, "");
}

# Builds a vzLogger meter entry from the UI form. Fields with a real default are
# always written; free-text fields (host, pullseq, key) are omitted when empty,
# as vzLogger expects (its OptionList treats absent options as the default).
sub normalize_meter
{
	my ($form, $channels) = @_;
	my $proto = trimmed($form->{protocol});
	$proto = "sml" if ($proto !~ /\A(?:sml|d0|oms|random|exec)\z/);
	my $m = {
		name             => trimmed($form->{name}),
		enabled          => as_bool($form->{enabled}),
		protocol         => $proto,
		device           => trimmed($form->{device}),
		interval         => as_int($form->{interval}, -1),
		aggtime          => -1,
		allowskip        => JSON::PP::true,
		aggfixedinterval => JSON::PP::false,
		channels         => [],
	};
	if ($proto eq "sml") {
		set_if($m, "host", trimmed($form->{host}));
		$m->{baudrate}       = as_int($form->{baudrate}, 9600);
		$m->{parity}         = valid_parity($form->{parity}, "8n1");
		set_if($m, "pullseq", trimmed($form->{pullseq}));
		$m->{use_local_time} = as_bool($form->{use_local_time});
	} elsif ($proto eq "d0") {
		set_if($m, "host", trimmed($form->{host}));
		$m->{baudrate}       = as_int($form->{baudrate}, 300);
		$m->{baudrate_read}  = as_int($form->{baudrate_read}, 300);
		$m->{parity}         = valid_parity($form->{parity}, "7e1");
		$m->{read_timeout}   = as_int($form->{read_timeout}, 10);
		set_if($m, "pullseq", trimmed($form->{pullseq}));
		my $ack = trimmed($form->{ackseq});
		$m->{ackseq}         = ($ack ne "") ? $ack : "auto";
		my $ws = trimmed($form->{wait_sync});
		$m->{wait_sync}      = ($ws =~ /\A(?:end|off)\z/) ? $ws : "off";
		$m->{baudrate_change_delay} = as_int($form->{baudrate_change_delay}, 0);
	} elsif ($proto eq "oms") {
		$m->{baudrate}       = as_int($form->{baudrate}, 9600);
		set_if($m, "key", trimmed($form->{key}));
		$m->{use_local_time} = as_bool($form->{use_local_time});
		$m->{mbus_debug}     = JSON::PP::false;
	} elsif ($proto eq "random") {
		# Test protocol: generates random values, no device needed.
		delete $m->{device};
		$m->{min} = as_double($form->{min}, 0);
		$m->{max} = as_double($form->{max}, 100);
	} elsif ($proto eq "exec") {
		# Reads from the output of a shell command; no device.
		delete $m->{device};
		set_if($m, "command", trimmed($form->{command}));
		set_if($m, "format", trimmed($form->{format}));
	}
	# Rebuild the channels so mqtt_topic follows the (possibly new) meter name.
	$m->{channels} = normalize_channels($m->{name}, $channels);
	return $m;
}

# ---- Channels -----------------------------------------------------------

# A channel: api=null (MQTT + local httpd, no middleware), a stable uuid, the
# OBIS identifier, aggmode always "none" (per spec), plus mqtt_topic and name.
sub channel_entry
{
	my ($meter_name, $identifier, $name, $uuid) = @_;
	$uuid = new_uuid() if (!defined($uuid) || $uuid !~ /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/);
	return {
		api        => "null",
		uuid       => $uuid,
		identifier => "$identifier",
		name       => "$name",
		mqtt_topic => "$meter_name/$name",
		aggmode    => "none",
	};
}

# Rebuilds a meter's channels: refreshes mqtt_topic for the (possibly renamed)
# meter and enforces api/aggmode while keeping existing uuids stable.
sub normalize_channels
{
	my ($meter_name, $channels) = @_;
	my @out;
	foreach my $ch (@{ref($channels) eq "ARRAY" ? $channels : []}) {
		next if (ref($ch) ne "HASH");
		my $name  = (defined($ch->{name}) && !ref($ch->{name})) ? "$ch->{name}" : "";
		my $ident = (defined($ch->{identifier}) && !ref($ch->{identifier})) ? "$ch->{identifier}" : "";
		push @out, channel_entry($meter_name, $ident, $name, $ch->{uuid});
	}
	return \@out;
}

sub channel_add
{
	my ($data, $form) = @_;
	my $meter_name = trimmed($form->{meter});
	my $idx = meter_index($data, $meter_name);
	return (0, "UI_CHANNEL_METER_NOT_FOUND") if ($idx < 0);
	my $name  = trimmed($form->{name});
	my $ident = trimmed($form->{identifier});
	return (0, "UI_CHANNEL_INVALID_NAME")       if ($name !~ /\A[A-Za-z0-9_-]{1,64}\z/);
	return (0, "UI_CHANNEL_INVALID_IDENTIFIER") if ($ident eq "");
	my $meter = $data->{meters}[$idx];
	$meter->{channels} = [] if (ref($meter->{channels}) ne "ARRAY");
	foreach my $ch (@{$meter->{channels}}) {
		return (0, "UI_CHANNEL_DUPLICATE_NAME") if (ref($ch) eq "HASH" && defined($ch->{name}) && $ch->{name} eq $name);
	}
	push @{$meter->{channels}}, channel_entry($meter_name, $ident, $name, undef);
	return (1, "");
}

# Adds several channels at once (used by "apply selected" and by the automatic
# discovery on meter save). Existing names and invalid entries are skipped, so it
# is idempotent.
sub channels_add_many
{
	my ($data, $form) = @_;
	my $meter_name = trimmed($form->{meter});
	my $idx = meter_index($data, $meter_name);
	return (0, "UI_CHANNEL_METER_NOT_FOUND") if ($idx < 0);
	my $meter = $data->{meters}[$idx];
	$meter->{channels} = [] if (ref($meter->{channels}) ne "ARRAY");
	my %have = map { (ref($_) eq "HASH" && defined($_->{name})) ? ($_->{name} => 1) : () } @{$meter->{channels}};
	foreach my $ch (@{ref($form->{channels}) eq "ARRAY" ? $form->{channels} : []}) {
		next if (ref($ch) ne "HASH");
		my $name  = trimmed($ch->{name});
		my $ident = trimmed($ch->{identifier});
		next if ($name !~ /\A[A-Za-z0-9_-]{1,64}\z/ || $ident eq "" || $have{$name}++);
		push @{$meter->{channels}}, channel_entry($meter_name, $ident, $name, undef);
	}
	return (1, "");
}

# Updates a channel identified by its uuid (in original_meter): changes name and
# identifier, and can move it to another meter. The uuid stays stable.
sub channel_update
{
	my ($data, $form) = @_;
	my $uuid      = trimmed($form->{uuid});
	my $old_meter = trimmed($form->{original_meter});
	my $new_meter = trimmed($form->{meter});
	my $name      = trimmed($form->{name});
	my $ident     = trimmed($form->{identifier});
	return (0, "UI_CHANNEL_INVALID_NAME")       if ($name !~ /\A[A-Za-z0-9_-]{1,64}\z/);
	return (0, "UI_CHANNEL_INVALID_IDENTIFIER") if ($ident eq "");
	my $oidx = meter_index($data, $old_meter);
	my $nidx = meter_index($data, $new_meter);
	return (0, "UI_CHANNEL_METER_NOT_FOUND") if ($oidx < 0 || $nidx < 0);
	my $ometer = $data->{meters}[$oidx];
	my $ochans = (ref($ometer->{channels}) eq "ARRAY") ? $ometer->{channels} : [];
	my ($found) = grep { ref($_) eq "HASH" && defined($_->{uuid}) && $_->{uuid} eq $uuid } @$ochans;
	return (0, "UI_CHANNEL_NOT_FOUND") if (!$found);
	my $nmeter = $data->{meters}[$nidx];
	$nmeter->{channels} = [] if (ref($nmeter->{channels}) ne "ARRAY");
	foreach my $ch (@{$nmeter->{channels}}) {
		next if (ref($ch) ne "HASH" || (defined($ch->{uuid}) && $ch->{uuid} eq $uuid));
		return (0, "UI_CHANNEL_DUPLICATE_NAME") if (defined($ch->{name}) && $ch->{name} eq $name);
	}
	if ($oidx == $nidx) {
		%$found = %{ channel_entry($new_meter, $ident, $name, $uuid) };
	} else {
		@{$ometer->{channels}} = grep { !(ref($_) eq "HASH" && defined($_->{uuid}) && $_->{uuid} eq $uuid) } @$ochans;
		push @{$nmeter->{channels}}, channel_entry($new_meter, $ident, $name, $uuid);
	}
	return (1, "");
}

sub channel_remove
{
	my ($data, $form) = @_;
	my $idx = meter_index($data, trimmed($form->{meter}));
	return (0, "UI_CHANNEL_METER_NOT_FOUND") if ($idx < 0);
	my $uuid = trimmed($form->{uuid});
	my $meter = $data->{meters}[$idx];
	my $channels = (ref($meter->{channels}) eq "ARRAY") ? $meter->{channels} : [];
	my $before = scalar(@$channels);
	@{$meter->{channels}} = grep { !(ref($_) eq "HASH" && defined($_->{uuid}) && $_->{uuid} eq $uuid) } @$channels;
	return (0, "UI_CHANNEL_NOT_FOUND") if (scalar(@{$meter->{channels}}) == $before);
	return (1, "");
}

sub new_uuid
{
	my $hex = "";
	$hex .= sprintf("%02x", int(rand(256))) for (1 .. 16);
	return join("-", substr($hex, 0, 8), substr($hex, 8, 4), substr($hex, 12, 4), substr($hex, 16, 4), substr($hex, 20, 12));
}

sub set_if { my ($h, $k, $v) = @_; $h->{$k} = "$v" if (defined($v) && $v ne ""); }
sub as_bool { my ($v) = @_; return (defined($v) && $v ne "" && $v ne "0" && $v ne "false") ? JSON::PP::true : JSON::PP::false; }
sub as_int { my ($v, $d) = @_; return (defined($v) && !ref($v) && $v =~ /\A\s*(-?\d+)\s*\z/) ? int($1) : $d; }
sub as_double { my ($v, $d) = @_; return (defined($v) && !ref($v) && $v =~ /\A\s*(-?\d+(?:\.\d+)?)\s*\z/) ? ($1 + 0) : $d; }
sub valid_parity { my ($v, $d) = @_; $v = trimmed($v); return ($v =~ /\A(?:8n1|7n1|7e1|7o1)\z/) ? $v : $d; }
sub trimmed { my ($v) = @_; return "" if (!defined($v) || ref($v)); $v =~ s/\A\s+|\s+\z//g; return $v; }

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
#
# vzlogger drops a message when its level is greater than the verbosity, and its
# levels are alert=0, error=1, warning=3, info=5, debug=10, finest=15. So the
# verbosity is not a scale of its own but the highest level still written, which
# maps onto the LoxBerry levels almost one to one:
#
#   0 off      -> -1  nothing at all (0 would still let alerts through)
#   1 alert    ->  0
#   2 critical ->  1  (vzlogger has no separate critical level)
#   3 error    ->  1
#   4 warning  ->  3
#   5 ok       ->  5  (vzlogger has no "ok"; info is the next one up)
#   6 info     ->  5
#   7 debug    -> 10
#
# Worth knowing when reading the log: at the LoxBerry default of 3 vzlogger says
# nothing but errors. Lines like "meter connection established" or the hint that
# a meter sends no clock are info level and need loglevel 6.
sub auto_verbosity
{
	my %map = (0 => -1, 1 => 0, 2 => 1, 3 => 1, 4 => 3, 5 => 5, 6 => 5, 7 => 10);
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

# The unique LoxBerry installation id (config/system/loxberryid.cfg, created by
# the core's setloxberryid.pl). The file only exists when the user enabled
# send-statistics; without it the client id stays "smartmeter-ng".
sub loxberry_uuid
{
	return "" if (!-e $loxberryid_file);
	open(my $fh, "<", $loxberryid_file) or return "";
	my $id = <$fh>;
	close($fh);
	return "" if (!defined($id));
	$id =~ s/^\s+|\s+$//g;
	return $id;
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
