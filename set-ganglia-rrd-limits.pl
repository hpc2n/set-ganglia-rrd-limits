#!/usr/bin/perl

# Set Ganglia RRD min/max limits. This script checks RRDs found in the Ganglia
# RRD directory and ensures that min/max is set to the desired values.
# Supports rrdcached.
#
# Written by Niklas Edmundsson in April 2020

# Copyright (C) 2020 Niklas Edmundsson <Niklas.Edmundsson@hpc2n.umu.se>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


use strict;
use warnings;

use RRDs;
use Getopt::Long 2.24 qw(:config pass_through);
use Number::Bytes::Human qw(format_bytes);


use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

# Options
my $quiet;
my $verbose;
my $debug;
my $rrddir = '/var/lib/ganglia/rrds';
my $maxage = 90;
my $dryrun;
my $help;

# Lovely global variables :-)
my %tunings;
my @rrdtuneargs;

my %tune2info = (
	'--maximum' => 'max',
	'--minimum' => 'min',
);


# ------------------------------------------------------------

sub usage
{
	print STDERR <<EOH

Usage: $0 name.rrd:--[minimum|maximum]|value ...

Options:
	--quiet   - Be quiet
	--verbose - Be verbose
	--debug   - Print debug messages
	--rrddir  - Ganglia RRD base directory (default: $rrddir)
	--maxage  - Max mtime of RRDs to modify (default: $maxage days)
	--dry-run - Dry-run, don't apply any changes

Environment variables:
	RRDCACHED_ADDRESS - rrdcached address
	
EOH
}

sub message
{
	return if($quiet);

	print @_;
}

sub verbose
{
	return unless($verbose);

	message @_;
}

sub debug
{
	return unless($debug);

	print @_;
}

sub handle_rrd
{
	my ($rrd, $file, $multiplier) = @_;

	my $info = RRDs::info $file;
	my $rc = RRDs::error;

	die "info error on $file: $rc" if($rc);

	debug "$file info:\n", Dumper $info;

	foreach my $k (sort keys %{$tunings{$rrd}}) {
		my $v = $tunings{$rrd}{$k};
		if($multiplier) {
			$v *= $multiplier;
		}
		# Hard-coded, each Ganglia RRD only have the
		# sum data store.
		my $is = "ds[sum].$tune2info{$k}";
		my $oldval = "N/A";
		my $newval = format_bytes($v, bs=>1000);
		if(defined($info->{$is})) {
			$oldval = format_bytes($info->{$is}, bs=>1000);
		}

		if(defined($info->{$is}) && $info->{$is} == $v) {
			verbose "$file: $k already $oldval, skipping\n";
			next;
		}

		if($dryrun) {
			message "$file: want to tune $k from $oldval to $newval\n";
		}
		else {
			message "$file: tuning $k from $oldval to $newval\n";
			RRDs::tune $file, @rrdtuneargs, $k, "sum:$v";
			$rc = RRDs::error;
			die "Error tuning $k to $v on $file: $rc" if($rc);
		}
	}
			
}

sub handle_dir
{
	my ($dir, $multiplier) = @_;

	my $handled = 0;

	foreach my $rrd (sort keys %tunings) {
		my $f = "$dir/$rrd";

		next unless(-f $f);

		my $age = -M _;

		if($age > $maxage) {
			debug "Skipping $f due to age $age\n";
			next;
		}

		debug "Found: $f\n";

		handle_rrd($rrd, $f, $multiplier);

		$handled++;
	}

	return $handled;
}

# =======================================================================

if(!GetOptions ("quiet" => \$quiet, "verbose" => \$verbose, "debug" => \$debug, "rrddir=s" => \$rrddir, "maxage=i" => \$maxage, "dry-run|dryrun|noop" => \$dryrun, "help|h" => \$help)) {
	usage;
	die "Command argument parse error\n";
}

if($help || !$ARGV[0]) {
	usage();
	die "Exiting...\n";
}

foreach my $a (@ARGV) {
	my ($rrd, $tun, $val) = split(/:/, $a);
	if(!defined($val)) {
		usage();
		die "Exiting...";
	}
	if(!$tune2info{$tun}) {
		die "Don't understand $tun";
	}
	if(defined($tunings{$rrd}{$tun})) {
		die "Can't specify $tun twice for $rrd";
	}

	$tunings{$rrd}{$tun} = $val;
}

debug "tunings:\n", Dumper \%tunings;

chdir $rrddir || die "Unable to chdir to $rrddir: $!";

verbose "Using RRD directory: $rrddir\n";

if($dryrun) {
	message "In dry-run mode, won't apply any changes.\n";
}

# rrdtune doesn't respect RRDCACHED_ADDRESS
if($ENV{'RRDCACHED_ADDRESS'}) {
	push @rrdtuneargs, '--daemon', $ENV{'RRDCACHED_ADDRESS'};
}

opendir(my $dh, ".") || die "opendir .: $!";
my @dirs = grep { $_ !~ '^(\.|__SummaryInfo__)' && -d $_ } readdir($dh);
closedir($dh);

my $totaldirs = 0;
my $totalsubdirs = 0;

foreach my $dir (@dirs) {
	# Support to give a Ganglia RRD subdirectory as rrddir argument
	if(handle_dir($dir)) {
		$totaldirs++;
	}

	# For top level, we need to ascend into the subdirectories
	opendir(my $sdh, $dir) || die "opendir $dir: $!";
	my @sdirs = grep { $_ !~ '^(\.|__SummaryInfo__)' && -d "$dir/$_" } readdir($sdh);
	closedir($sdh);

	my $subdirs = 0;
	foreach my $sd (@sdirs) {
		if(handle_dir("$dir/$sd")) {
			$subdirs++;
		}
	}

	debug "$dir: $subdirs of total " . scalar(@dirs) . " dirs considered\n";

	# Also add limits to SummaryInfo rrd:s, use number of subdirs as
	# multiplier.
	handle_dir("$dir/__SummaryInfo__", $subdirs);

	$totaldirs += $subdirs;
	$totalsubdirs += $subdirs;
}

debug "totaldirs: $totaldirs\n";

# Also add limits to top level SummaryInfo rrd:s
if($totaldirs) {
	my $multiplier = $totaldirs;
	if($totalsubdirs) {
		# Avoid setting an insanely large limit on the top-level
		# SummaryInfo, sqrt() chosen on a whim.
		$multiplier = int(sqrt($totaldirs));
	}
	handle_dir("__SummaryInfo__", $multiplier);
}

exit 0;
