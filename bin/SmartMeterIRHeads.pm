package SmartMeterIRHeads;

use strict;
use warnings;
use Exporter qw(import);
use LoxBerry::JSON;

# Manages the list of I/R reading-head devices used later as the vzLogger
# "device" option.
#
# The plugin's udev rule (from daemon/daemon) creates a stable symlink per
# connected head:
#
#   /dev/serial/smartmeter/<ID_SERIAL_SHORT>  ->  /dev/ttyUSBx
#
# The symlink is bound to the adapter serial number, so it survives reconnects
# and reboots and is what vzLogger should read. Devices are kept in
# config/irheads.json, split into automatically detected heads (rebuilt from the
# symlink directory on every page load) and manually added ones (edited by the
# user). Both feed the device dropdown of the vzLogger configuration.

our @EXPORT_OK = qw(sync_and_load load_data save_data add_manual add_tibberpulse tibberpulse_probe remove_manual usb_port_short);

my $AUTO_DIR = "/dev/serial/smartmeter";

sub config_file
{
	my ($configdir) = @_;
	return "$configdir/irheads.json";
}

# Reads irheads.json, always returning the expected structure.
sub load_data
{
	my ($configdir) = @_;
	my $file = config_file($configdir);
	my $jsonobj = LoxBerry::JSON->new();
	my $data = eval { $jsonobj->open(filename => $file) };
	$data = {} if ($@ || ref($data) ne "HASH");
	$data->{auto}   = [] if (ref($data->{auto}) ne "ARRAY");
	$data->{manual} = [] if (ref($data->{manual}) ne "ARRAY");
	return ($data, $jsonobj);
}

sub save_data
{
	my ($jsonobj) = @_;
	return $jsonobj->write();
}

# Reads udev properties for a device path (KEY=VALUE lines from udevadm).
sub device_info
{
	my ($devpath) = @_;
	my %info;
	return \%info if (!-e $devpath);
	open(my $fh, "-|", "udevadm", "info", "--query=property", "--name=$devpath") or return \%info;
	while (my $line = <$fh>) {
		chomp($line);
		my ($key, $value) = split(/=/, $line, 2);
		$info{$key} = $value if (defined($key) && defined($value));
	}
	close($fh);
	return \%info;
}

# Shortens the udev ID_PATH to the USB port part. Handles both the tty
# interface form "...-usb-0:1.4:1.0" -> "1.4" and the device form
# "...-usb-0:1.4" -> "1.4". Falls back to the full value.
sub usb_port_short
{
	my ($id_path) = @_;
	return "" if (!defined($id_path) || $id_path eq "");
	return $1 if ($id_path =~ /usb-\d+:([\d.]+)/);
	return $id_path;
}

# Resolves the symlink target (the real ttyUSB device) for display.
sub symlink_target
{
	my ($devpath) = @_;
	return "" if (!-e $devpath);
	my $target = readlink($devpath);
	return $devpath if (!defined($target));
	# readlink usually returns something like ../../ttyUSB0
	$target =~ s{.*/}{};
	return "/dev/$target";
}

# Builds one automatically-detected head entry from its symlink.
sub _auto_entry
{
	my ($serial) = @_;
	my $device = "$AUTO_DIR/$serial";
	my $info = device_info($device);
	return {
		device  => $device,
		name    => $serial,
		serial  => ($info->{ID_SERIAL_SHORT} || $serial),
		target  => symlink_target($device),
		usbport => usb_port_short($info->{ID_PATH}),
		vendor  => ($info->{ID_VENDOR_FROM_DATABASE} || $info->{ID_VENDOR} || ""),
		model   => ($info->{ID_MODEL_FROM_DATABASE} || $info->{ID_MODEL} || ""),
	};
}

# Scans the udev symlink directory for connected heads.
sub scan_auto
{
	my @entries;
	return @entries if (!-d $AUTO_DIR);
	opendir(my $dh, $AUTO_DIR) or return @entries;
	my @serials = sort grep { $_ ne "." && $_ ne ".." } readdir($dh);
	closedir($dh);
	foreach my $serial (@serials) {
		push @entries, _auto_entry($serial);
	}
	return @entries;
}

# Rebuilds the auto list from the current symlink directory (adding new heads
# and dropping unplugged ones), leaves the manual list untouched, and persists
# the result. Returns the loaded data structure.
sub sync_and_load
{
	my ($configdir) = @_;
	my ($data, $jsonobj) = load_data($configdir);
	# Drop auto entries that are actually managed manually (e.g. a Tibber Pulse
	# whose virtual device lives under the same /dev/serial/smartmeter directory),
	# so they are not listed twice.
	my %manual_dev = map { (ref($_) eq "HASH" && defined($_->{device})) ? ($_->{device} => 1) : () } @{$data->{manual}};
	$data->{auto} = [ grep { !$manual_dev{$_->{device}} } scan_auto() ];
	save_data($jsonobj);
	return $data;
}

# Validates a manual device name: letters, digits, underscore and hyphen only.
sub valid_name
{
	my ($name) = @_;
	return defined($name) && $name =~ /\A[A-Za-z0-9_-]{1,64}\z/;
}

# Validates a manual device path: an absolute /dev path without shell traps.
sub valid_device
{
	my ($device) = @_;
	return defined($device) && $device =~ m{\A/dev/[A-Za-z0-9_./-]{1,120}\z};
}

# Adds a manual head. Returns (1, "") on success or (0, error-key) on failure.
sub add_manual
{
	my ($configdir, $device, $name) = @_;
	return (0, "UI_IRHEAD_INVALID_DEVICE") if (!valid_device($device));
	return (0, "UI_IRHEAD_INVALID_NAME") if (!valid_name($name));
	# The device must actually be present under /dev (a device node or a symlink,
	# e.g. one created by the udev rule); otherwise refuse to add it. Tests set
	# SMARTMETER_IRHEAD_SKIP_DEVICE_CHECK to use placeholder paths.
	return (0, "UI_IRHEAD_DEVICE_MISSING")
		if (!$ENV{SMARTMETER_IRHEAD_SKIP_DEVICE_CHECK} && !-e $device && !-l $device);
	my ($data, $jsonobj) = load_data($configdir);
	foreach my $entry (@{$data->{manual}}) {
		return (0, "UI_IRHEAD_DUPLICATE") if ($entry->{device} eq $device || $entry->{name} eq $name);
	}
	push @{$data->{manual}}, { device => $device, name => $name, type => "serial" };
	save_data($jsonobj);
	return (1, "");
}

# Validates a host: an IPv4 address or hostname, with an optional :port.
sub valid_host
{
	my ($host) = @_;
	return 0 if (!defined($host) || $host eq "" || length($host) > 258);
	if ($host =~ /\A(.+):(\d{1,5})\z/) {
		my $port = $2;
		return 0 if ($port < 1 || $port > 65535);
		$host = $1;
	}
	return ($host =~ /\A[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\z/) ? 1 : 0;
}

# Probes a Tibber Pulse bridge: reachable, credentials valid and a framed SML
# telegram is returned. Returns "" on success or a localizable error key. The
# password is passed via a 0600 curl config file, not the command line.
sub tibberpulse_probe
{
	my ($host, $node, $password) = @_;
	return "UI_TIBBER_INVALID_HOST" if (!valid_host($host));
	$node = "1" if (!defined($node) || $node eq "");
	return "UI_TIBBER_INVALID_NODE" if ($node !~ /\A\d+\z/);

	require File::Temp;
	my ($cfgfh, $cfg)   = File::Temp::tempfile("tibberprobe-XXXXXX", TMPDIR => 1, UNLINK => 1);
	my ($bodyfh, $body) = File::Temp::tempfile("tibberbody-XXXXXX",  TMPDIR => 1, UNLINK => 1);
	close($bodyfh);
	chmod(0600, $cfg);
	(my $pw = defined($password) ? $password : "") =~ s/([\\"])/\\$1/g;
	print $cfgfh "url = \"http://$host/data.json?node_id=$node\"\n";
	print $cfgfh "user = \"admin:$pw\"\n";
	close($cfgfh);

	my $code = `curl -sS --max-time 6 -o \Q$body\E -w '%{http_code}' -K \Q$cfg\E 2>/dev/null`;
	my $rc = $?;
	unlink($cfg);
	if ($rc != 0 || !defined($code) || $code !~ /\A\d{3}\z/ || $code eq "000") {
		unlink($body); return "UI_TIBBER_UNREACHABLE";
	}
	if ($code == 401) { unlink($body); return "UI_TIBBER_AUTH_FAILED"; }
	if ($code != 200) { unlink($body); return "UI_TIBBER_HTTP_ERROR"; }

	my $hdr = "";
	if (open(my $bf, "<:raw", $body)) { read($bf, $hdr, 8); close($bf); }
	unlink($body);
	return "UI_TIBBER_NO_SML" if (unpack("H*", $hdr) !~ /\A1b1b1b1b01010101/i);
	return "";
}

# Adds a Tibber Pulse as a manual head after a successful probe. Stores host,
# node and password; the virtual device is created later by tibberpulse_meter.sh.
sub add_tibberpulse
{
	my ($configdir, $name, $host, $node, $password) = @_;
	return (0, "UI_IRHEAD_INVALID_NAME") if (!valid_name($name));
	return (0, "UI_TIBBER_INVALID_HOST") if (!valid_host($host));
	$node = "1" if (!defined($node) || $node eq "");
	return (0, "UI_TIBBER_INVALID_NODE") if ($node !~ /\A\d+\z/);
	my $err = tibberpulse_probe($host, $node, $password);
	return (0, $err) if ($err ne "");
	my ($data, $jsonobj) = load_data($configdir);
	my $device = "$AUTO_DIR/$name";
	foreach my $entry (@{$data->{manual}}) {
		return (0, "UI_IRHEAD_DUPLICATE") if (($entry->{name} // "") eq $name || ($entry->{device} // "") eq $device);
	}
	push @{$data->{manual}}, {
		name     => $name,
		device   => $device,
		type     => "tibberpulse",
		host     => $host,
		node     => "$node",
		password => (defined($password) ? $password : ""),
	};
	save_data($jsonobj);
	return (1, "");
}

# Removes a manual head by device path.
sub remove_manual
{
	my ($configdir, $device) = @_;
	my ($data, $jsonobj) = load_data($configdir);
	my $before = scalar(@{$data->{manual}});
	@{$data->{manual}} = grep { $_->{device} ne $device } @{$data->{manual}};
	return (0, "UI_IRHEAD_NOT_FOUND") if (scalar(@{$data->{manual}}) == $before);
	save_data($jsonobj);
	return (1, "");
}

1;
