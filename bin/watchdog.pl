#!/usr/bin/perl

# Starts, stops and supervises the vzlogger process.
#
# vzlogger runs in the foreground (-f) as a child of this script instead of as a
# systemd service, so the plugin owns its lifecycle. The packaged systemd unit
# is disabled by bin/vzlogger_pkg.sh.
#
# Usage: watchdog.pl --action=start|stop|stop-discovery|end-discovery|restart|check|status [--verbose]
#
#   start           start vzlogger unless it is already running
#   stop            stop vzlogger and remember that this was intentional
#   stop-discovery  stop vzlogger and set the autodiscovery marker (not the
#                   manual one), so OBIS discovery can hold the device and a
#                   cron "check" does not restart it in the meantime
#   end-discovery   clear the autodiscovery marker and restart vzlogger (unless
#                   it had been stopped manually)
#   restart         stop, then start
#   check           restart vzlogger if it died unexpectedly (called from cron)
#   status          exit 0 if vzlogger is running, 1 otherwise
#   pid             print the running PID (unlogged, unlocked; for the web UI)
#
# Two markers gate the periodic check: the manual-stop marker (written by "stop")
# and the autodiscovery marker. "start" and "restart" clear both, because those
# are the explicit user actions that say "run it" - restart is also the only way
# back up from a manual stop, as the web interface has no separate start button.
#
# Nothing that runs unattended may use them for that reason. A stop is the user's
# decision and has to survive a reboot and a plugin upgrade, so the boot daemon
# and postroot.sh both call "check", not "start" or "restart" (issue #4).
#
# Logging: a run only writes a logfile when it actually does something. "check"
# runs from cron every five minutes and stays completely silent while there is
# nothing to do - see logsession() below (issue #5).

use strict;
use warnings;
use Getopt::Long;
use File::Path qw(make_path);
use POSIX qw(setsid);
use JSON::PP;
use FindBin;
use lib $FindBin::Bin;
use LoxBerry::System;
use LoxBerry::Log;

my $psubfolder = $lbpplugindir;
my $config_dir = "$lbhomedir/config/plugins/$psubfolder";
my $vzlogger_config = "$config_dir/vzlogger.conf";
my $runtime_dir = "/var/run/shm/$psubfolder";
my $pid_file = "$runtime_dir/vzlogger.pid";
my $stopped_marker = "$config_dir/vzlogger_stopped.cfg";
# While OBIS discovery runs, the main vzlogger is stopped without the manual
# marker but with this one, so a cron "check" does not race and restart it and
# grab the device. It is cleared on end-discovery, on a manual start and at boot.
my $autodiscovery_marker = "$config_dir/vzlogger_autodiscovery.cfg";
my $autodiscovery_stale = 120;
my $failure_file = "$runtime_dir/vzlogger_watchdog_failures";
my $max_failures = 5;

# Exit codes. The web interface turns them into a message, so they have to stay
# distinct: "could not even start" is a try-again, "tried and failed" is not.
my $EXIT_OK     = 0;   # the action was carried out
my $EXIT_FAILED = 1;   # the action was attempted and failed
my $EXIT_USAGE  = 2;   # no or unknown action
my $EXIT_BUSY   = 3;   # the lock was not free - nothing was done at all

my ($verbose, $action);
GetOptions("verbose=s" => \$verbose, "action=s" => \$action);
$action = "" if (!defined($action));

# Lightweight, unlogged status probe for the web interface, which polls it every
# few seconds. Prints the running vzlogger PID (empty line if not running) and
# exits without opening a log session or taking the watchdog lock.
if ($action eq "pid") {
	my $pid = vzlogger_running() ? (read_pid() || find_vzlogger_pid() || "") : "";
	print "$pid\n";
	exit 0;
}

# The log session is created on first use, never up front.
#
# cron runs "check" every five minutes, and every LoxBerry::Log session means a
# new timestamped file plus a database entry - roughly 288 logfiles a day on a
# RAM disk, almost all of them saying that everything is fine. A run with nothing
# to report now writes nothing at all, while every run that actually does
# something (start, stop, restart, or a check that has to restart vzlogger) still
# gets its own logfile (issue #5).
my $log;

sub logsession
{
	return $log if ($log);
	$log = LoxBerry::Log->new(name => "watchdog", package => $psubfolder);
	if ($verbose) {
		$log->stdout(1);
		$log->loglevel(7);
	}
	# Claim the exported LOG* functions explicitly instead of relying on being
	# the first session created - new() only takes that role when no object
	# holds it yet.
	$log->default();
	LOGSTART("watchdog action=$action");
	return $log;
}

sub wlog_inf  { logsession(); LOGINF(@_);  }
sub wlog_warn { logsession(); LOGWARN(@_); }
sub wlog_err  { logsession(); LOGERR(@_);  }

# Written whatever the configured loglevel is - as long as logging is on at all.
#
# LoxBerry::Log drops anything whose severity is above the plugin loglevel, so at
# loglevel 3 (ERROR) a perfectly normal stop or restart would leave a logfile
# containing nothing but its header - which would defeat the whole point of
# writing one only for real actions. Starting and stopping vzlogger is precisely
# what one opens this log for, so those lines must not be filtered, and must not
# pretend to be errors either, which would colour a routine stop red.
#
# The mechanism is the one the core uses for its own header lines: write() skips
# the loglevel filter for a negative severity and then adds no tag of its own, so
# the tag travels inside the text and the log viewer still colours the line.
# Loglevel 0 is the one exception - it suppresses the file entirely, which is
# what "logging off" is supposed to mean.
sub wlog_event
{
	my ($tag, $message) = @_;
	logsession();
	$log->write(-1, "<$tag> $message");
	$log->close();
	return;
}

# An explicit --verbose run is always meant to be watched, so it opens the
# session even when the outcome turns out to be "nothing to do".
logsession() if ($verbose);

# The runtime directory (PID file, failure counter) is on a tmpfs and is gone
# after a reboot; daemon/daemon recreates it as root at boot. Creating it from
# here can legitimately fail - as loxberry, a directory directly under /run is
# not ours to make - and make_path() croaks by default, which would take the
# whole watchdog down instead of just costing it the PID file. Everything below
# falls back to scanning /proc, so a warning is the right response.
my $mkpath_err;
make_path($runtime_dir, { error => \$mkpath_err }) if (!-d $runtime_dir);
if (!-d $runtime_dir) {
	# Reported only for the actions somebody triggered and is waiting on. This
	# degrades to a /proc scan rather than failing, and letting the five-minute
	# check report it would turn a merely degraded runtime directory into the
	# very flood of logfiles that issue #5 is about.
	wlog_event("WARNING", "Could not create $runtime_dir - continuing without a PID file.")
		if ($action ne "check" && $action ne "status");
}

# Serialize against a parallel run, for example cron firing while the web
# interface triggers a restart.
#
# The periodic check can afford to queue behind whatever is running; the web
# interface cannot, because a CGI that blocks for two minutes reads as a hang.
# Note that LoxBerry::System::lock() waits on more than this lock file: it also
# blocks while apt/dpkg or an unattended-upgrade is running, and on the lbupdate
# and plugininstall locks - so this branch is not exotic on a Raspberry Pi that
# installs its updates in the background.
my $lockwait = ($action eq "check") ? 120 : 15;
my $lockstate = LoxBerry::System::lock(lockfile => "smartmeter-watchdog", wait => $lockwait);
if ($lockstate) {
	# Nothing was done here - that has to reach the caller, otherwise a blocked
	# lock looks exactly like a successful action (issue #2). An event rather
	# than a warning, because at the default loglevel a warning would be dropped
	# and this is the line that explains why an action did nothing.
	wlog_event("WARNING", "Lock not free within ${lockwait}s (blocked by: $lockstate). Nothing was done.");
	print "Blocked by $lockstate - nothing was done.\n";
	LOGEND() if ($log);
	exit $EXIT_BUSY;
}

my $exit = 0;
if ($action eq "start") { $exit = do_start(); }
elsif ($action eq "stop") { $exit = do_stop(1); }
elsif ($action eq "stop-discovery") { write_marker($autodiscovery_marker); $exit = do_stop(0); }
elsif ($action eq "end-discovery") { unlink($autodiscovery_marker); $exit = do_end_discovery(); }
elsif ($action eq "restart") { $exit = do_restart(); }
elsif ($action eq "check") { $exit = do_check(); }
elsif ($action eq "status") { $exit = vzlogger_running() ? $EXIT_OK : $EXIT_FAILED; }
else {
	wlog_err("No valid action. --action=start|stop|stop-discovery|end-discovery|restart|check|status is required.");
	print "No valid action specified. --action=start|stop|stop-discovery|end-discovery|restart|check|status is required.\n";
	$exit = $EXIT_USAGE;
}

LoxBerry::System::unlock(lockfile => "smartmeter-watchdog");
LOGEND() if ($log);
exit $exit;

sub do_start
{
	# A manual/boot start hard-clears both markers.
	unlink($stopped_marker) if (-e $stopped_marker);
	unlink($autodiscovery_marker) if (-e $autodiscovery_marker);

	if (vzlogger_running()) {
		wlog_event("OK", "vzlogger is already running.");
		print "vzlogger is already running.\n";
		return 0;
	}
	if (!vzlogger_mode_enabled()) {
		wlog_inf("vzLogger mode is not active. Not starting vzlogger.");
		print "vzLogger mode is not active. Did not start vzlogger.\n";
		return 0;
	}
	my $binary = vzlogger_binary();
	if (!$binary) {
		wlog_err("vzlogger binary not found. Install it from the plugin page.");
		print "vzlogger binary not found.\n";
		return 1;
	}
	if (!-e $vzlogger_config) {
		wlog_err("Generated configuration is missing: $vzlogger_config");
		print "Generated vzLogger configuration is missing. Use Save and apply first.\n";
		return 1;
	}

	# Re-derive the auto-managed fields (in particular the verbosity from the
	# current plugin loglevel) so that changing the loglevel and restarting takes
	# effect without a manual Save.
	refresh_config();

	# Start the Tibber Pulse bridges first so their virtual devices exist before
	# vzlogger opens them.
	ensure_tibberpulse();

	# Do not start against unplugged reading heads: if an enabled meter's device
	# is not present under /dev, vzlogger would start and flood the log with read
	# errors. Refuse the start and name the missing device(s) instead.
	my @missing = missing_devices();
	if (@missing) {
		my $list = join(", ", @missing);
		wlog_err("Not starting vzlogger: device(s) not present under /dev: $list. Reconnect the reading head, then start again.");
		print "vzLogger not started - device(s) missing: $list\n";
		return 1;
	}

	my $logfile = vzlogger_logfile();
	wlog_inf("Starting $binary with $vzlogger_config, logging to $logfile");
	my $pid = fork();
	if (!defined($pid)) {
		wlog_err("Could not fork: $!");
		return 1;
	}
	if ($pid == 0) {
		# Detach so vzlogger survives the watchdog and its caller.
		setsid();
		open(STDIN, "<", "/dev/null");
		# vzlogger writes to stdout/stderr only while its parent is not init, so
		# after this process has exited everything goes through its own log file.
		# The redirect still catches what comes before that: a failing exec and
		# vzlogger's own complaint if it cannot open the log file at all.
		open(STDOUT, ">>", $logfile) or open(STDOUT, ">", "/dev/null");
		open(STDERR, ">&", \*STDOUT);
		exec($binary, "-f", "-c", $vzlogger_config, "-o", $logfile);
		exit 1;
	}

	write_pid($pid);
	# Give it a moment so an immediate failure is reported instead of a
	# success that is already gone.
	sleep 2;
	if (!vzlogger_running()) {
		wlog_err("vzlogger exited right after the start. See $logfile.");
		print "vzlogger did not stay running. Check the vzLogger log.\n";
		return 1;
	}
	reset_failures();
	wlog_event("OK", "vzlogger started (PID $pid).");
	print "Started vzlogger (PID $pid).\n";
	return 0;
}

# Re-applies the auto-derived fields to the existing vzlogger.conf via the config
# helper (verbosity from the live plugin loglevel, log path, local httpd, mqtt),
# so a changed loglevel takes effect on the next start. Best effort: a failure is
# logged but does not block the start with the previous config.
sub refresh_config
{
	my $helper = "$FindBin::Bin/vzlogger_conf.pl";
	if (!-e $helper) {
		wlog_warn("Config helper not found ($helper); starting with existing config.");
		return;
	}
	my $rc = system("perl '$helper' refresh >/dev/null 2>&1");
	wlog_warn("Could not refresh vzLogger config before start (rc=$rc).") if ($rc != 0);
}

sub do_stop
{
	my ($manual) = @_;
	if ($manual) {
		my $fh;
		if (open($fh, ">", $stopped_marker)) {
			print $fh "1\n";
			close($fh);
		}
		# A manual stop takes the Tibber Pulse bridges down too; a plain restart
		# (do_stop(0)) leaves them running so vzlogger just reconnects.
		stop_all_tibberpulse();
	}
	my $pid = read_pid();
	if (!$pid || !process_is_vzlogger($pid)) {
		$pid = find_vzlogger_pid();
	}
	if (!$pid) {
		wlog_event("OK", "vzlogger is not running.");
		print "vzlogger is not running.\n";
		unlink($pid_file);
		return 0;
	}

	wlog_event("INFO", "Stopping vzlogger (PID $pid).");
	kill("TERM", $pid);
	for (1 .. 20) {
		last if (!process_is_vzlogger($pid));
		select(undef, undef, undef, 0.25);
	}
	if (process_is_vzlogger($pid)) {
		wlog_warn("vzlogger did not stop on TERM, sending KILL.");
		kill("KILL", $pid);
		select(undef, undef, undef, 0.5);
	}
	unlink($pid_file);
	if (process_is_vzlogger($pid)) {
		wlog_err("Could not stop vzlogger (PID $pid).");
		print "Could not stop vzlogger.\n";
		return 1;
	}
	wlog_event("OK", "vzlogger stopped.");
	print "Stopped vzlogger.\n";
	return 0;
}

# A restart has to actually replace the process. That something called vzlogger
# is running afterwards proves nothing: a survivor with the old configuration in
# memory looks identical from the outside, and that is precisely the state the
# web interface used to report as success (issue #2). So the old PID is noted
# first and compared afterwards.
sub do_restart
{
	my $oldpid = read_pid() || find_vzlogger_pid() || 0;

	my $rc = do_stop(0);
	if ($rc != $EXIT_OK) {
		# Deliberately no start attempt here: the old process still holds the
		# serial device, so a second instance would only add a second failure.
		wlog_err("Not restarting - the running vzlogger could not be stopped.");
		print "Could not stop the running vzlogger - not restarted.\n";
		return $EXIT_FAILED;
	}

	sleep 1;
	$rc = do_start();
	return $rc if ($rc != $EXIT_OK);

	my $newpid = read_pid() || find_vzlogger_pid() || 0;
	if ($oldpid && $newpid == $oldpid) {
		wlog_err("Restart did not take effect: vzlogger is still PID $oldpid and therefore still running its previous configuration.");
		print "Restart did not replace the running process (PID $oldpid).\n";
		return $EXIT_FAILED;
	}
	wlog_event("OK", "vzlogger restarted (PID $oldpid -> $newpid).") if ($newpid);
	return $EXIT_OK;
}

# Brings vzlogger back up after OBIS discovery has released the device.
#
# Not do_check(): discovery stopped vzlogger itself, so finding it stopped here
# is expected, not a crash. Routing this through the periodic check counted a
# failure and logged "vzlogger is not running (failure 1 of 5). Restarting." for
# every perfectly ordinary discovery run - which reads like something went wrong
# and, since that line is written regardless of loglevel, was impossible to
# overlook. A manual stop still wins over the restart.
sub do_end_discovery
{
	return $EXIT_OK if (-e $stopped_marker);
	return $EXIT_OK if (vzlogger_running());
	# The stop was ours, so it must not count towards the give-up threshold.
	reset_failures();
	wlog_event("INFO", "OBIS discovery finished. Starting vzlogger again.");
	return do_start();
}

# Called periodically. Restarts vzlogger only if it should be running and was
# not stopped on purpose, and gives up after repeated failures so a broken
# configuration is not restarted forever.
sub do_check
{
	# Every path that concludes "nothing to do" returns SILENTLY - no log call,
	# so no log session and no logfile. This runs from cron every five minutes;
	# a line saying that all is well, written 288 times a day onto a RAM disk,
	# buries the runs that actually matter. Only acting is worth recording.
	#
	# An explicit --verbose run still logs, because logsession() is opened up
	# front for it.

	return 0 if (-e $stopped_marker);

	# Keep the Tibber Pulse bridges alive independently of vzlogger, so a crashed
	# bridge is restarted even while vzlogger itself is fine. Starting one is an
	# action and logs; finding them all alive is silent.
	ensure_tibberpulse();

	# Do not restart while OBIS discovery holds the device. A stale marker (e.g.
	# discovery was killed) is cleaned up so the service is not stuck forever.
	if (-e $autodiscovery_marker) {
		my $age = time - (stat($autodiscovery_marker))[9];
		return 0 if ($age < $autodiscovery_stale);
		wlog_event("WARNING", "Stale autodiscovery marker (${age}s old). Removing it.");
		unlink($autodiscovery_marker);
	}

	return 0 if (!vzlogger_mode_enabled());

	if (vzlogger_running()) {
		reset_failures();
		return 0;
	}

	my $failures = read_failures() + 1;
	write_failures($failures);
	if ($failures > $max_failures) {
		wlog_err("vzlogger failed $failures times in a row. Not restarting again until it is started manually.");
		return 1;
	}
	wlog_event("WARNING", "vzlogger is not running (failure $failures of $max_failures). Restarting.");
	return do_start();
}

# vzLogger is considered "active" when its generated configuration exists and
# contains at least one enabled meter. There is no separate on/off flag anymore
# (the vzlogger.conf is the single source of truth).
sub vzlogger_mode_enabled
{
	return 0 if (!-e $vzlogger_config);
	open(my $fh, "<", $vzlogger_config) or return 0;
	local $/;
	my $raw = <$fh>;
	close($fh);
	my $data = eval { JSON::PP->new->relaxed->decode($raw) };
	return 0 if (!$data || ref($data->{meters}) ne "ARRAY");
	foreach my $meter (@{$data->{meters}}) {
		next if (ref($meter) ne "HASH");
		my $enabled = $meter->{enabled};
		return 1 if (JSON::PP::is_bool($enabled) ? $enabled : (defined($enabled) && !ref($enabled) && $enabled && $enabled ne "0"));
	}
	return 0;
}

# Returns the device paths of enabled serial meters (sml/d0/oms) whose device is
# not physically present under /dev (neither a node nor a symlink). Used to avoid
# starting vzlogger against an unplugged reading head, which floods the log.
sub missing_devices
{
	return () if (!-e $vzlogger_config);
	open(my $fh, "<", $vzlogger_config) or return ();
	local $/;
	my $raw = <$fh>;
	close($fh);
	my $data = eval { JSON::PP->new->relaxed->decode($raw) };
	return () if (!$data || ref($data->{meters}) ne "ARRAY");
	my @missing;
	foreach my $meter (@{$data->{meters}}) {
		next if (ref($meter) ne "HASH");
		my $enabled = $meter->{enabled};
		my $is_enabled = JSON::PP::is_bool($enabled) ? $enabled
			: (defined($enabled) && !ref($enabled) && $enabled && $enabled ne "0");
		next if (!$is_enabled);
		next if (($meter->{protocol} // "") !~ /\A(?:sml|d0|oms)\z/);
		my $dev = $meter->{device};
		next if (!defined($dev) || $dev eq "");
		push @missing, $dev if (!-e $dev && !-l $dev);
	}
	return @missing;
}

# -------------------------------------------------------------- Tibber Pulse
# A Tibber Pulse is a manual head of type "tibberpulse" in irheads.json. Each one
# is served by its own tibberpulse_meter.sh (curl -> socat PTY), started as root
# via sudo. The bridges must run before vzlogger so its device is present.

sub tibberpulse_script { return "$FindBin::Bin/tibberpulse_meter.sh"; }

sub tibberpulse_heads
{
	my $file = "$config_dir/irheads.json";
	return () if (!-e $file);
	open(my $fh, "<", $file) or return ();
	local $/;
	my $raw = <$fh>;
	close($fh);
	my $data = eval { JSON::PP->new->relaxed->decode($raw) };
	return () if (!$data || ref($data->{manual}) ne "ARRAY");
	return grep {
		ref($_) eq "HASH" && ($_->{type} // "") eq "tibberpulse"
		&& ($_->{name} // "") =~ /\A[A-Za-z0-9_-]+\z/
	} @{$data->{manual}};
}

sub tibberpulse_running
{
	my ($name) = @_;
	my $pf = "$runtime_dir/tibberpulse-$name.pid";
	return 0 if (!-e $pf);
	open(my $fh, "<", $pf) or return 0;
	my $pid = <$fh>;
	close($fh);
	$pid = defined($pid) ? $pid : "";
	$pid =~ s/\s+//g;
	# The bridge runs as root; use /proc (readable by anyone) instead of kill(0),
	# which loxberry may not be allowed to send to a root process.
	return 0 if ($pid !~ /\A\d+\z/ || !-d "/proc/$pid");
	if (open(my $cf, "<", "/proc/$pid/cmdline")) {
		local $/;
		my $cmd = <$cf>;
		close($cf);
		$cmd = defined($cmd) ? $cmd : "";
		$cmd =~ s/\0/ /g;
		return 0 if ($cmd ne "" && $cmd !~ /tibberpulse_meter\.sh/);
	}
	return 1;
}

sub start_tibberpulse
{
	my ($name) = @_;
	return if (tibberpulse_running($name));
	my $script = tibberpulse_script();
	return if (!-e $script);
	wlog_event("INFO", "Starting Tibber Pulse bridge '$name'.");
	my $pid = fork();
	return if (!defined($pid));
	if ($pid == 0) {
		setsid();
		open(STDIN, "<", "/dev/null");
		open(STDOUT, ">", "/dev/null");
		open(STDERR, ">&", \*STDOUT);
		exec("sudo", "-n", $script, $name);
		exit 1;
	}
	# Detached bridge; do not wait for it.
}

sub stop_tibberpulse
{
	my ($name) = @_;
	system("sudo", "-n", tibberpulse_script(), "stop", $name);
}

# Starts every configured Tibber Pulse bridge that is not running and waits (a
# few seconds) for its virtual device to appear, so vzLogger finds it on start.
sub ensure_tibberpulse
{
	my @heads = tibberpulse_heads();
	return if (!@heads);
	my @started;
	foreach my $h (@heads) {
		if (!tibberpulse_running($h->{name})) {
			start_tibberpulse($h->{name});
			push @started, $h;
		}
	}
	return if (!@started);
	for (my $i = 0; $i < 20; $i++) {
		my $missing = 0;
		foreach my $h (@started) {
			my $dev = $h->{device};
			$missing++ if (defined($dev) && $dev ne "" && !-e $dev && !-l $dev);
		}
		last if (!$missing);
		select(undef, undef, undef, 0.5);
	}
}

sub stop_all_tibberpulse
{
	foreach my $h (tibberpulse_heads()) {
		stop_tibberpulse($h->{name});
	}
}

sub vzlogger_binary
{
	foreach my $candidate ("/usr/bin/vzlogger", "/usr/local/bin/vzlogger") {
		return $candidate if (-x $candidate);
	}
	foreach my $dir (split(/:/, $ENV{PATH} || "")) {
		return "$dir/vzlogger" if (-x "$dir/vzlogger");
	}
	return undef;
}

# vzLogger logs through its own "log" option, which vzlogger_conf.pl writes into
# the generated configuration together with a "verbosity" derived from the plugin
# loglevel. This is a plain file, not a LoxBerry log session, for two reasons:
# vzlogger keeps the handle open for its whole lifetime (a session file, renamed
# or removed under it, would leave it writing into a deleted inode), and its
# lines carry no LoxBerry <INFO>/<ERROR> tags, so the log manager would add
# nothing but a new, mostly empty file per start. The Logfiles tab links it
# directly instead.
#
# The same path is passed on the command line as well: vzlogger parses the
# command line, then the configuration, then the command line again (checked in
# the 0.8.x sources), so -o overrides the "log" key. Pointing both at one file
# makes that order irrelevant.
#
# Size and age are the core's business, not the plugin's: log_maint.pl runs
# hourly over log/plugins, gzips a *.log above 3 MB and truncates it in place
# (copytruncate) - which is exactly right here, because vzlogger opens the file
# with fopen(..., "a") and simply continues at the beginning afterwards.
sub vzlogger_logfile
{
	my $dir = "$lbhomedir/log/plugins/$psubfolder";
	make_path($dir) if (!-d $dir);
	return "$dir/vzlogger.log";
}

sub vzlogger_running
{
	my $pid = read_pid();
	return 1 if ($pid && process_is_vzlogger($pid));
	my $found = find_vzlogger_pid();
	write_pid($found) if ($found);
	return $found ? 1 : 0;
}

sub process_is_vzlogger
{
	my ($pid) = @_;
	return 0 if (!$pid || $pid !~ /\A\d+\z/ || !-d "/proc/$pid");
	open(my $fh, "<", "/proc/$pid/cmdline") or return 0;
	local $/;
	my $cmdline = <$fh> || "";
	close($fh);
	my @args = grep { defined($_) && $_ ne "" } split(/\0/, $cmdline);
	return 0 if (!@args);
	return 0 if ($args[0] !~ m{(?:\A|/)vzlogger\z});
	# Only our own instance, identified by the generated configuration.
	return (grep { $_ eq $vzlogger_config } @args) ? 1 : 0;
}

sub find_vzlogger_pid
{
	opendir(my $proc, "/proc") or return undef;
	my @pids = sort { $a <=> $b } grep { /\A\d+\z/ } readdir($proc);
	closedir($proc);
	foreach my $pid (@pids) {
		return $pid if (process_is_vzlogger($pid));
	}
	return undef;
}

sub read_pid
{
	return undef if (!-e $pid_file);
	open(my $fh, "<", $pid_file) or return undef;
	my $pid = <$fh>;
	close($fh);
	chomp($pid) if (defined($pid));
	return (defined($pid) && $pid =~ /\A\d+\z/) ? $pid : undef;
}

sub write_pid
{
	my ($pid) = @_;
	open(my $fh, ">", $pid_file) or return;
	print $fh "$pid\n";
	close($fh);
}

sub read_failures
{
	return 0 if (!-e $failure_file);
	open(my $fh, "<", $failure_file) or return 0;
	my $count = <$fh>;
	close($fh);
	chomp($count) if (defined($count));
	return (defined($count) && $count =~ /\A\d+\z/) ? $count : 0;
}

sub write_failures
{
	my ($count) = @_;
	open(my $fh, ">", $failure_file) or return;
	print $fh "$count\n";
	close($fh);
}

sub reset_failures { unlink($failure_file) if (-e $failure_file); }

sub write_marker
{
	my ($file) = @_;
	my $fh;
	if (open($fh, ">", $file)) { print $fh "1\n"; close($fh); }
}
