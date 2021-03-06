# set-ganglia-rrd-limits.pl

## Introduction

This script checks RRDs found in the Ganglia RRD directory and ensures that
min/max is set to the desired values.

RRDs in the `__SummaryInfo__` directories receive special handling, by default the max value is set to the desired per-host value multiplied with the number of hosts in that hierarchy. This can be changed by per-RRD flags, see below.

Supports rrdcached via the `RRDCACHED_ADDRESS` environment variable.

## Usage

This script is designed to be used by a helper script, commonly maintained
by a configuration management system, run at regular intervals from a crontab
or similar to catch new/changed hosts.

For an example, see [example/set-ganglia-rrd-limits-hpc2n.sh](example/set-ganglia-rrd-limits-hpc2n.sh)

### Display the help text

```
$ ./set-ganglia-rrd-limits.pl --help

Usage: ./set-ganglia-rrd-limits.pl name.rrd:--[minimum|maximum]:value[:flag1,..,flagN] ...

Options:
        --quiet   - Be quiet
        --verbose - Be verbose
        --debug   - Print debug messages
        --rrddir  - Ganglia RRD base directory (default: /var/lib/ganglia/rrds)
        --maxage  - Max mtime of RRDs to modify (default: 90 days)
        --dry-run - Dry-run, don't apply any changes

Environment variables:
        RRDCACHED_ADDRESS - rrdcached address

Per RRD flags understood:
    regex: RRD name is a regex
    suminfoprod: SummaryInfo RRD limits are multiplied by num (default)
    suminfosqrt: SummaryInfo RRD limits are multiplied by sqrt(num)
    suminfoval: SummaryInfo RRD limits are set to the given value
Exiting...
```

### Example usage

Set the min/max limits of bytes_in.rrd, bytes_out.rrd, pkts_in.rrd and
pkts_out.rrd in the default Ganglia RRD directory, leveraging the rrdcached
that our example Ganglia setup also uses:

```
env RRDCACHED_ADDRESS="unix:/var/run/rrdcached.sock" ./set-ganglia-rrd-limits.pl --dry-run --verbose bytes_in.rrd:--maximum:50000000000 bytes_in.rrd:--minimum:0 bytes_out.rrd:--maximum:50000000000 bytes_out.rrd:--minimum:0 pkts_in.rrd:--maximum:595000000 pkts_in.rrd:--minimum:0 pkts_out.rrd:--maximum:595000000 pkts_out.rrd:--minimum:0
```

Or for a shorter to write but takes a bit longer to run version:
```
env RRDCACHED_ADDRESS="unix:/var/run/rrdcached.sock" ./set-ganglia-rrd-limits.pl --dry-run --verbose "(bytes|pkts)_(in|out).rrd:--minimum:0:regex" "bytes_(in|out).rrd:--maximum:50000000000:regex" "pkts_(in|out).rrd:--maximum:595000000:regex"
```
