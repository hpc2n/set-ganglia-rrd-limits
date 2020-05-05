#!/bin/bash
#
# Apply hpc2n preferences for min/max on ganglia RRD:s that are historically
# troublesome.

# This script is explicitly unlicensed, so you can base whatever site
# specific thing you want to do on it.

# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <https://unlicense.org>


dir=$(dirname $0)

export RRDCACHED_ADDRESS="unix:/var/run/rrdcached.sock"

# Dual 100 gigabit with a factor of 2 margin if reporting is uneven over time
let netmax=2*2*100*1000*1000*1000/8

# Derive max packet rate from network rate (84 bytes is the minimum ethernet
# packet size) and round it to even millions
let pktmax=$netmax/84/1000000*1000000

$dir/set-ganglia-rrd-limits.pl --dry-run bytes_in.rrd:--maximum:$netmax bytes_in.rrd:--minimum:0 bytes_out.rrd:--maximum:$netmax bytes_out.rrd:--minimum:0 pkts_in.rrd:--maximum:$pktmax pkts_in.rrd:--minimum:0 pkts_out.rrd:--maximum:$pktmax pkts_out.rrd:--minimum:0
