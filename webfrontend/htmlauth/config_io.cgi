#!/usr/bin/perl

# Backup / restore of the plugin configuration folder.
#
#   GET  ?action=export  -> streams a ZIP of every top-level file in the config
#                           folder as an attachment (smartmeter_ng_<ts>.zip).
#   POST  action=import  -> takes an uploaded ZIP (multipart), unpacks its files
#                           back into the config folder (overwriting), and
#                           returns JSON { ok, error_key }.
#
# Archive::Zip is not installed on LoxBerry, so the zip/unzip CLI tools are used.
# The exported ZIP stores the files flat (zip -j); the import therefore rejects
# any archive whose entries live in a sub-folder, which is the typical mistake
# of zipping the folder itself instead of its contents.

use strict;
use warnings;
use CGI;
use JSON::PP;
use File::Temp qw(tempfile tempdir);
use File::Copy qw(copy);
use File::Basename qw(basename);
use POSIX qw(strftime);
use LoxBerry::System;

# Cap the upload and the unpacked size so a malformed or hostile archive cannot
# fill the disk (a real config backup is only a few kilobytes).
$CGI::POST_MAX        = 25 * 1024 * 1024;   # 25 MiB upload
my $MAX_UNPACKED      = 50 * 1024 * 1024;   # 50 MiB unpacked
my $MAX_ENTRIES       = 500;
my $SAFE_NAME         = qr/\A[A-Za-z0-9._-]+\z/;

my $cgi       = CGI->new;
my $configdir = $lbpconfigdir;
my $action    = $cgi->param("action") || "";

if ($action eq "export" && ($ENV{REQUEST_METHOD} || "") eq "GET") {
	do_export();
} else {
	do_import();
}
exit;

# --------------------------------------------------------------------------

sub json_reply
{
	my ($res) = @_;
	print $cgi->header(-type => "application/json", -charset => "utf-8", -expires => "now");
	print JSON::PP->new->utf8->canonical->encode($res);
}

sub err { return { ok => JSON::PP::false, error_key => $_[0] }; }

# ---- Export --------------------------------------------------------------

sub do_export
{
	opendir(my $dh, $configdir) or do {
		print $cgi->header(-type => "text/plain", -charset => "utf-8");
		print "Configuration folder not readable.\n";
		return;
	};
	my @files = sort grep { -f "$configdir/$_" && !-l "$configdir/$_" } readdir($dh);
	closedir($dh);

	if (!@files) {
		print $cgi->header(-type => "text/plain", -charset => "utf-8");
		print "No configuration files to export.\n";
		return;
	}

	my (undef, $zip) = tempfile("smexport-XXXXXX", SUFFIX => ".zip", TMPDIR => 1, OPEN => 0);
	unlink($zip);   # zip creates it; a pre-existing empty file would be updated
	# List form (no shell); -j stores basenames only, so the archive is flat.
	my @full = map { "$configdir/$_" } @files;
	my $rc = system("zip", "-j", "-q", $zip, @full) >> 8;
	if ($rc != 0 || !-s $zip) {
		unlink($zip);
		print $cgi->header(-type => "text/plain", -charset => "utf-8");
		print "Could not create the ZIP archive.\n";
		return;
	}

	my $name = "smartmeter_ng_" . strftime("%Y%m%d_%H%M%S", localtime) . ".zip";
	my $size = -s $zip;
	open(my $zfh, "<:raw", $zip) or do { unlink($zip); return; };
	binmode(STDOUT);
	print $cgi->header(
		-type              => "application/zip",
		-attachment        => $name,
		"-Content-Length"  => $size,
		-expires           => "now",
	);
	my $buf;
	print $buf while (read($zfh, $buf, 65536));
	close($zfh);
	unlink($zip);
}

# ---- Import --------------------------------------------------------------

sub do_import
{
	json_reply(import_zip());
}

sub import_zip
{
	return err("UI_POST_REQUIRED") if (($ENV{REQUEST_METHOD} || "") ne "POST");
	return err("UI_IO_TOO_LARGE")  if ($cgi->cgi_error && $cgi->cgi_error =~ /413/);
	return err("UI_IO_BAD_ZIP")    if ($cgi->cgi_error);

	my $upload = $cgi->upload("file");
	return err("UI_IO_NO_FILE") if (!$upload);

	# Stash the upload in a private temp dir that is removed on exit.
	my $work = tempdir("smimport-XXXXXX", TMPDIR => 1, CLEANUP => 1);
	my $zip  = "$work/upload.zip";
	open(my $out, ">:raw", $zip) or return err("UI_IO_EXTRACT_FAILED");
	binmode($upload);
	my $buf;
	print $out $buf while (read($upload, $buf, 65536));
	close($out);
	return err("UI_IO_BAD_ZIP") if (!-s $zip);

	# Must be a valid archive.
	return err("UI_IO_BAD_ZIP") if ((system("unzip", "-t", "-qq", $zip) >> 8) != 0);

	# Enumerate the entries and validate every name before extracting anything.
	my @entries;
	open(my $ph, "-|", "unzip", "-Z1", $zip) or return err("UI_IO_BAD_ZIP");
	while (my $line = <$ph>) {
		chomp $line;
		next if ($line eq "");
		push @entries, $line;
	}
	close($ph);

	return err("UI_IO_EMPTY")     if (!@entries);
	return err("UI_IO_TOO_LARGE") if (@entries > $MAX_ENTRIES);

	my @names;
	foreach my $e (@entries) {
		# A backup produced by "export" is flat. Anything with a path separator
		# (or a directory entry) means the user zipped a folder, not its files.
		return err("UI_IO_SUBFOLDER") if ($e =~ m{[/\\]});
		return err("UI_IO_BAD_ZIP")   if ($e eq "." || $e eq ".." || $e =~ /\A\.+\z/);
		return err("UI_IO_BAD_ZIP")   if ($e !~ $SAFE_NAME);
		push @names, $e;
	}
	return err("UI_IO_EMPTY") if (!@names);

	# Guard against decompression bombs using the reported unpacked size.
	my $total = 0;
	if (open(my $lh, "-|", "unzip", "-l", $zip)) {
		while (my $l = <$lh>) { $total = $1 if ($l =~ /^\s*(\d+)\s+\d+\s+files?\s*$/); }
		close($lh);
	}
	return err("UI_IO_TOO_LARGE") if ($total > $MAX_UNPACKED);

	# Extract into a staging folder, then copy the validated files across. This
	# keeps unzip from ever writing directly into the config folder.
	my $stage = "$work/stage";
	mkdir($stage) or return err("UI_IO_EXTRACT_FAILED");
	return err("UI_IO_EXTRACT_FAILED") if ((system("unzip", "-o", "-qq", $zip, "-d", $stage) >> 8) != 0);

	my $restored = 0;
	foreach my $name (@names) {
		my $src = "$stage/$name";
		next if (!-f $src || -l $src);          # defence in depth
		copy($src, "$configdir/$name") or return err("UI_IO_EXTRACT_FAILED");
		$restored++;
	}
	return err("UI_IO_EMPTY") if (!$restored);

	return { ok => JSON::PP::true, restored => $restored };
}
