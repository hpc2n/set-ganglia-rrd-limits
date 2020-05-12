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
my %relist;
my @rrdtuneargs;

my %tune2info = (
	'--maximum' => 'max',
	'--minimum' => 'min',
);

my %flaghelp = (
	suminfoprod => 'SummaryInfo RRD limits are multiplied by num (default)',
	suminfosqrt => 'SummaryInfo RRD limits are multiplied by sqrt(num)',
	suminfoval  => 'SummaryInfo RRD limits are set to the given value',
	regex => 'RRD name is a regex',
# FIXME: Future stuff
	#sumnodec => 'Don't decrease values already set in SummaryInfo RRDs',
	#dir => 'RRD name includes directory component',
);


# ------------------------------------------------------------

sub usage
{
	print STDERR <<EOH;

Usage: $0 name.rrd:--[minimum|maximum]:value[:flag1,..,flagN] ...

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

	print STDERR "Per RRD flags understood:\n";
	foreach my $f (sort keys %flaghelp) {
		print STDERR "    $f: $flaghelp{$f}\n";
	}

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
    my ($matches, $file) = @_;

    my $info = RRDs::info $file;
    my $rc = RRDs::error;

    die "info error on $file: $rc" if($rc);

    debug "$file info:\n", Dumper $info;

    debug "matches:\n", Dumper $matches;

    foreach my $match (@{$matches}) {
        foreach my $k (sort keys %{$match}) {
            my $v = $match->{$k}{value};
            if($info->{'ds[num].last_ds'}) {
                # If it has a num DS it's a SummaryInfo RRD
                if($match->{$k}{flags}{suminfosqrt}) {
                    $v *= int(sqrt(abs($info->{'ds[num].last_ds'})));
                    if($info->{'ds[num].last_ds'} < 0) {
                        $v *= -1;
                    }
                    debug "Value modified by suminfosqrt flag\n";
                }
                elsif($match->{$k}{flags}{suminfoval}) {
                    debug "Value unmodified due to suminfoval flag\n";
                }
                else {
                    $v *= $info->{'ds[num].last_ds'};
                    debug "Value modified by suminfoprod flag\n";
                }
            }
            # Hard-coded, each Ganglia RRD only have the
            # sum data store.
            my $is = "ds[sum].$tune2info{$k}";
            my $oldval = "N/A";
            my $newval = format_bytes($v, bs=>1000);
            if(defined($info->{$is})) {
                $oldval = format_bytes($info->{$is}, bs=>1000);
            }

            if($oldval eq $newval) {
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
			
}

sub handle_dir
{
	my ($dir) = @_;

	my $handled = 0;

	opendir(my $dh, $dir) || die "opendir $dir: $!";
	my @rrds = sort grep { $_ =~ /.rrd$/ } readdir($dh);
	closedir($dh);

	foreach my $rrd (sort @rrds) {
		my $matches;
		if($tunings{$rrd}) {
			push @{$matches}, $tunings{$rrd};
		}
		if(!$matches) {
			foreach my $re (keys %relist) {
				if($rrd =~ m !$re!) {
					push @{$matches}, $relist{$re};
				}
			}
		}

		next unless($matches);

		my $f = "$dir/$rrd";

		next unless(-f $f);

		my $age = -M _;

		if($age > $maxage) {
			debug "Skipping $f due to age $age\n";
			next;
		}

		debug "Found: $f\n";

		handle_rrd($matches, $f);

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
	my ($rrd, $tun, $val, $flags) = split(/:/, $a);
	if(!defined($val) || $val eq "") {
		die "Couldn't understand argument '$a'";
	}
	if(!$tune2info{$tun}) {
		die "Don't understand $tun";
	}
	my $tref = {value => $val};
	my $name = $rrd;
	if($flags) {
		foreach my $f (split(/,/, $flags)) {
			if(!$flaghelp{$f}) {
				die "Unknown flag: $f";
			}
			$tref->{flags}{$f} = 1;

			if($f eq 'regex') {
				# Verify that rrd name is a valid RE
				eval {
					"s" =~ m !$rrd!;
				};
				if($@) {
					die "$rrd not a valid regex:\n",$@,"\n";
				}

				$name = "-$rrd-"; # Unique placeholder

 				$relist{$rrd}{$tun} = $tref;
			}
		}
	}
	if($tunings{$name} && $tunings{$name}{$tun}) {
		die "Can't specify $tun twice for $rrd";
	}
		
	$tunings{$name}{$tun} = $tref;
}

debug "tunings:\n", Dumper \%tunings;

debug "relist:\n", Dumper \%relist;

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
my @dirs = sort grep { $_ !~ '^(\.|__SummaryInfo__)' && -d $_ } readdir($dh);
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
	my @sdirs = sort grep { $_ !~ '^(\.|__SummaryInfo__)' && -d "$dir/$_" } readdir($sdh);
	closedir($sdh);

	my $subdirs = 0;
	foreach my $sd (@sdirs) {
		if(handle_dir("$dir/$sd")) {
			$subdirs++;
		}
	}

	debug "$dir: $subdirs of total " . scalar(@dirs) . " dirs considered\n";

	# Also add limits to SummaryInfo rrd:s if they exist, might not if
	# we are one level down in the tree.
	if(-d "$dir/__SummaryInfo__") {
		handle_dir("$dir/__SummaryInfo__");
		# FIXME: Set flag so we know how to handle top-level SummaryInfo
	}

	$totaldirs += $subdirs;
	$totalsubdirs += $subdirs;
}

debug "totaldirs=$totaldirs totalsubdirs=$totalsubdirs\n";

# Also add limits to top level SummaryInfo rrd:s
handle_dir("__SummaryInfo__");

exit 0;
