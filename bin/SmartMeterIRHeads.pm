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

our @EXPORT_OK = qw(sync_and_load load_data save_data add_manual remove_manual usb_port_short);

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
	$data->{auto} = [ scan_auto() ];
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
	push @{$data->{manual}}, { device => $device, name => $name };
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
